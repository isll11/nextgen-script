#!/bin/bash

# ═══════════════════════════════════════════════════════════════════
# Multi-SlowDNS Accelerator v4.0
# Features: Multi-Connection Load Balancing + Auto-Optimization
# ═══════════════════════════════════════════════════════════════════

set -euo pipefail

# ─── Colors ───
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; MAGENTA='\033[0;35m'; NC='\033[0m'
BOLD='\033[1m'

# ─── Paths ───
INSTALL_DIR="/opt/multislowdns"
CONFIG_DIR="$INSTALL_DIR/config"
LOG_DIR="$INSTALL_DIR/logs"
BIN_DIR="$INSTALL_DIR/bin"

# ─── Configuration ───
CONNECTIONS=8          # عدد الاتصالات المتزامنة (يمكن تغييره)
BASE_PORT=5300         # البداية من 5301 إلى 5308
LB_PORT=53             # منفذ الموازنة (Load Balancer)

info() { echo -e "${CYAN}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "Run as root: sudo bash $0"
        exit 1
    fi
}

install_dependencies() {
    info "Installing dependencies..."
    apt-get update -qq
    apt-get install -y -qq git make gcc dnsutils net-tools curl wget \
        python3 python3-pip socat iptables-persistent
    success "Dependencies installed"
}

install_slowdns() {
    info "Installing SlowDNS binary..."
    mkdir -p "$BIN_DIR" "$CONFIG_DIR" "$LOG_DIR"
    cd /tmp
    
    # Clean previous
    rm -rf slowdns 2>/dev/null || true
    
    # Clone and compile (most reliable)
    git clone --depth 1 https://github.com/slackjeff/slowdns.git
    cd slowdns
    make
    
    cp dns-server "$BIN_DIR/"
    chmod +x "$BIN_DIR/dns-server"
    
    # Generate keys
    cd "$BIN_DIR"
    ./dns-server -gen-key -privkey-file server.key -pubkey-file server.pub
    
    success "SlowDNS installed"
    echo -e "${MAGENTA}Public Key: $(cat server.pub)${NC}"
}

create_load_balancer() {
    info "Creating Python Load Balancer..."
    
    cat > "$BIN_DIR/slowdns-lb.py" << 'PYTHON_EOF'
#!/usr/bin/env python3
import socket, threading, select, sys, os, time
from collections import deque

# Load config
CONFIG_FILE = "/opt/multislowdns/config/lb.conf"
CONNECTIONS = 8
BASE_PORT = 5300
LB_PORT = 53

# Read config if exists
if os.path.exists(CONFIG_FILE):
    with open(CONFIG_FILE) as f:
        for line in f:
            if '=' in line:
                k,v = line.strip().split('=', 1)
                if k == 'CONNECTIONS': CONNECTIONS = int(v)
                elif k == 'BASE_PORT': BASE_PORT = int(v)
                elif k == 'LB_PORT': LB_PORT = int(v)

TARGET_PORTS = [BASE_PORT + i for i in range(1, CONNECTIONS + 1)]
print(f"[LB] Starting with {CONNECTIONS} connections on ports {TARGET_PORTS[0]}-{TARGET_PORTS[-1]}")

# Round-robin with connection health check
class ConnectionPool:
    def __init__(self):
        self.ports = deque(TARGET_PORTS)
        self.lock = threading.Lock()
        self.failed_ports = set()
    
    def get_port(self):
        with self.lock:
            attempts = 0
            while attempts < len(self.ports):
                port = self.ports[0]
                if port not in self.failed_ports:
                    self.ports.rotate(-1)
                    return port
                self.ports.rotate(-1)
                attempts += 1
            # All failed, reset
            self.failed_ports.clear()
            return self.ports[0]
    
    def mark_failed(self, port):
        with self.lock:
            self.failed_ports.add(port)

pool = ConnectionPool()

def forward_dns(client_data, client_addr, sock):
    port = pool.get_port()
    target = ("127.0.0.1", port)
    
    try:
        upstream = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        upstream.settimeout(3)
        upstream.sendto(client_data, target)
        
        # Wait for response with select for non-blocking
        ready, _, _ = select.select([upstream], [], [], 5)
        if ready:
            response, _ = upstream.recvfrom(4096)
            sock.sendto(response, client_addr)
            upstream.close()
            return True
    except Exception as e:
        pool.mark_failed(port)
        print(f"[WARN] Port {port} failed: {e}")
    
    return False

def handle_client(sock):
    while True:
        try:
            data, addr = sock.recvfrom(4096)
            if not data:
                continue
            
            # Try primary, then fallback
            if not forward_dns(data, addr, sock):
                # Retry once with different port
                time.sleep(0.01)
                forward_dns(data, addr, sock)
                
        except Exception as e:
            print(f"[ERROR] Handler: {e}")

def main():
    # Create UDP socket with optimizations
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 134217728)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_SNDBUF, 134217728)
    sock.bind(("0.0.0.0", LB_PORT))
    
    print(f"[LB] Load Balancer listening on port {LB_PORT}")
    print(f"[LB] Distributing to {CONNECTIONS} SlowDNS instances")
    
    # Multiple threads for better performance
    threads = []
    for i in range(4):  # 4 handler threads
        t = threading.Thread(target=handle_client, args=(sock,))
        t.daemon = True
        t.start()
        threads.append(t)
    
    # Keep main thread alive
    while True:
        time.sleep(1)

if __name__ == "__main__":
    main()
PYTHON_EOF

    chmod +x "$BIN_DIR/slowdns-lb.py"
    success "Load Balancer created"
}

create_instances() {
    local ns_domain=$1
    local target_host=$2
    local target_port=$3
    
    info "Creating $CONNECTIONS SlowDNS instances..."
    
    # Save config
    cat > "$CONFIG_DIR/lb.conf" << EOF
CONNECTIONS=$CONNECTIONS
BASE_PORT=$BASE_PORT
LB_PORT=$LB_PORT
NS_DOMAIN=$ns_domain
TARGET_HOST=$target_host
TARGET_PORT=$target_port
EOF

    # Create systemd services for each instance
    for i in $(seq 1 $CONNECTIONS); do
        local listen_port=$((BASE_PORT + i))
        local service_name="slowdns-instance@${i}"
        
        cat > "/etc/systemd/system/slowdns-instance@.service" << EOF
[Unit]
Description=SlowDNS Instance %i (Multi-Connection)
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$BIN_DIR
ExecStart=$BIN_DIR/dns-server -udp :$BASE_PORT%i -privkey-file $BIN_DIR/server.key $ns_domain $target_host:$target_port
Restart=on-failure
RestartSec=2
StandardOutput=append:$LOG_DIR/instance-%i.log
StandardError=append:$LOG_DIR/instance-%i.error.log

[Install]
WantedBy=multi-user.target
EOF

        systemctl daemon-reload
        systemctl enable "slowdns-instance@${i}"
        systemctl start "slowdns-instance@${i}"
    done
    
    success "$CONNECTIONS instances created (ports $((BASE_PORT+1))-$((BASE_PORT+CONNECTIONS)))"
}

create_lb_service() {
    info "Creating Load Balancer service..."
    
    cat > /etc/systemd/system/slowdns-lb.service << EOF
[Unit]
Description=SlowDNS Multi-Connection Load Balancer
After=network.target slowdns-instance@1.service
Wants=slowdns-instance@1.service

[Service]
Type=simple
User=root
ExecStart=/usr/bin/python3 $BIN_DIR/slowdns-lb.py
Restart=always
RestartSec=3
StandardOutput=append:$LOG_DIR/lb.log
StandardError=append:$LOG_DIR/lb.error.log

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable slowdns-lb
    systemctl start slowdns-lb
    
    success "Load Balancer started on port $LB_PORT"
}

optimize_network() {
    info "Optimizing network for maximum speed..."
    
    # Kernel optimizations for UDP/DNS speed
    cat >> /etc/sysctl.conf << 'SYSCTL_EOF'

# Multi-SlowDNS Optimizations
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.core.rmem_default = 134217728
net.core.wmem_default = 134217728
net.core.netdev_budget = 50000
net.core.netdev_budget_usecs = 5000
net.core.somaxconn = 65535
net.ipv4.udp_rmem_min = 8192
net.ipv4.udp_wmem_min = 8192
net.ipv4.udp_mem = 8388608 12582912 16777216
net.netfilter.nf_conntrack_udp_timeout = 30
net.netfilter.nf_conntrack_udp_timeout_stream = 60
net.ipv4.ip_local_port_range = 1024 65535
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fast_open = 3
SYSCTL_EOF

    sysctl -p >/dev/null 2>&1
    
    # File limits
    cat >> /etc/security/limits.conf << 'LIMITS_EOF'
* soft nofile 1048576
* hard nofile 1048576
root soft nofile 1048576
root hard nofile 1048576
LIMITS_EOF

    # IRQ balance for multi-core
    apt-get install -y -qq irqbalance 2>/dev/null && systemctl enable irqbalance
    
    success "Network optimized for high-speed DNS tunneling"
}

setup_firewall() {
    info "Configuring firewall..."
    
    # Allow all SlowDNS ports
    for i in $(seq 1 $CONNECTIONS); do
        local port=$((BASE_PORT + i))
        ufw allow $port/udp 2>/dev/null || iptables -I INPUT -p udp --dport $port -j ACCEPT 2>/dev/null
    done
    
    ufw allow $LB_PORT/udp 2>/dev/null || iptables -I INPUT -p udp --dport $LB_PORT -j ACCEPT 2>/dev/null
    iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
    
    success "Firewall configured"
}

show_status() {
    echo ""
    echo -e "${CYAN}${BOLD}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}           Multi-SlowDNS Installation Complete!${NC}"
    echo -e "${CYAN}${BOLD}═══════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "${YELLOW}Configuration:${NC}"
    echo -e "  NS Domain:      ${GREEN}$NS_DOMAIN${NC}"
    echo -e "  Target:         ${GREEN}$TARGET_HOST:$TARGET_PORT${NC}"
    echo -e "  Public Key:     ${MAGENTA}$(cat $BIN_DIR/server.pub)${NC}"
    echo ""
    echo -e "${YELLOW}Connection Pool:${NC}"
    echo -e "  Load Balancer:  ${GREEN}Port $LB_PORT (UDP)${NC}"
    echo -e "  Instances:      ${GREEN}$CONNECTIONS connections${NC}"
    echo -e "  Port Range:     ${GREEN}$((BASE_PORT+1)) - $((BASE_PORT+CONNECTIONS))${NC}"
    echo ""
    echo -e "${YELLOW}Client Configuration:${NC}"
    echo -e "  ${CYAN}Use NS Domain:${NC} $NS_DOMAIN"
    echo -e "  ${CYAN}Use Public Key above in your SlowDNS client${NC}"
    echo -e "  ${CYAN}Connection Type:${NC} UDP"
    echo ""
    echo -e "${YELLOW}Services Status:${NC}"
    systemctl is-active --quiet slowdns-lb && \
        echo -e "  ${GREEN}●${NC} Load Balancer: Running" || \
        echo -e "  ${RED}●${NC} Load Balancer: Stopped"
    
    for i in $(seq 1 $CONNECTIONS); do
        if systemctl is-active --quiet "slowdns-instance@${i}" 2>/dev/null; then
            echo -e "  ${GREEN}●${NC} Instance $i: Running (Port $((BASE_PORT + i)))"
        else
            echo -e "  ${RED}●${NC} Instance $i: Stopped"
        fi
    done
    
    echo ""
    echo -e "${CYAN}Commands:${NC}"
    echo -e "  View logs:    ${YELLOW}tail -f $LOG_DIR/lb.log${NC}"
    echo -e "  Restart all:  ${YELLOW}systemctl restart slowdns-lb${NC}"
    echo -e "  Stop all:     ${YELLOW}systemctl stop 'slowdns-instance@*'${NC}"
    echo ""
}

manage_connections() {
    while true; do
        clear
        echo -e "${CYAN}${BOLD}"
        cat << "EOF"
    ███████╗██╗      ██████╗ ██╗    ██╗██████╗ ███╗   ██╗███████╗
    ██╔════╝██║     ██╔═══██╗██║    ██║██╔══██╗████╗  ██║██╔════╝
    ███████╗██║     ██║   ██║██║ █╗ ██║██║  ██║██╔██╗ ██║███████╗
    ╚════██║██║     ██║   ██║██║███╗██║██║  ██║██║╚██╗██║╚════██║
    ███████║███████╗╚██████╔╝╚███╔███╔╝██████╔╝██║ ╚████║███████║
    ╚══════╝╚══════╝ ╚═════╝  ╚══╝╚══╝ ╚═════╝ ╚═╝  ╚═══╝╚══════╝
EOF
        echo -e "${NC}"
        echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"
        echo ""
        echo -e "${CYAN}  [1]${NC} ${GREEN}View Status${NC}"
        echo -e "${CYAN}  [2]${NC} ${GREEN}Restart All Services${NC}"
        echo -e "${CYAN}  [3]${NC} ${GREEN}Stop All Services${NC}"
        echo -e "${CYAN}  [4]${NC} ${GREEN}View Real-time Logs${NC}"
        echo -e "${CYAN}  [5]${NC} ${GREEN}Optimize Performance${NC}"
        echo -e "${CYAN}  [6]${NC} ${GREEN}Change Connection Count${NC}"
        echo -e "${CYAN}  [0]${NC} ${RED}Exit${NC}"
        echo ""
        read -rp "Select: " choice
        
        case $choice in
            1) show_status; read -rp "Press Enter..." ;;
            2) 
                systemctl restart slowdns-lb
                for i in $(seq 1 $CONNECTIONS); do systemctl restart "slowdns-instance@${i}"; done
                success "All services restarted"
                sleep 2
                ;;
            3)
                systemctl stop slowdns-lb
                for i in $(seq 1 $CONNECTIONS); do systemctl stop "slowdns-instance@${i}" 2>/dev/null || true; done
                success "All services stopped"
                sleep 2
                ;;
            4)
                echo "Press Ctrl+C to exit logs"
                tail -f "$LOG_DIR/lb.log" "$LOG_DIR"/instance-*.log 2>/dev/null
                ;;
            5)
                optimize_network
                sleep 2
                ;;
            6)
                read -rp "New connection count (4-16): " new_conn
                [[ "$new_conn" =~ ^[0-9]+$ ]] && CONNECTIONS=$new_conn
                sed -i "s/CONNECTIONS=.*/CONNECTIONS=$CONNECTIONS/" "$CONFIG_DIR/lb.conf"
                success "Updated to $CONNECTIONS connections. Restart services to apply."
                sleep 2
                ;;
            0) exit 0 ;;
        esac
    done
}

# ═══════════════════════════════════════════════════════════════════
# MAIN INSTALLER
# ═══════════════════════════════════════════════════════════════════

main() {
    check_root
    clear
    
    echo -e "${CYAN}${BOLD}"
    cat << "EOF"
    ███╗   ███╗██╗   ██╗██╗  ████████╗██╗    ███████╗██╗      ██████╗ ██╗    ██╗██████╗ ███╗   ██╗███████╗
    ████╗ ████║██║   ██║██║  ╚══██╔══╝██║    ██╔════╝██║     ██╔═══██╗██║    ██║██╔══██╗████╗  ██║██╔════╝
    ██╔████╔██║██║   ██║██║     ██║   ██║    ███████╗██║     ██║   ██║██║ █╗ ██║██║  ██║██╔██╗ ██║███████╗
    ██║╚██╔╝██║██║   ██║██║     ██║   ██║    ╚════██║██║     ██║   ██║██║███╗██║██║  ██║██║╚██╗██║╚════██║
    ██║ ╚═╝ ██║╚██████╔╝███████╗██║   ██║    ███████║███████╗╚██████╔╝╚███╔███╔╝██████╔╝██║ ╚████║███████║
    ╚═╝     ╚═╝ ╚═════╝ ╚══════╝╚═╝   ╚═╝    ╚══════╝╚══════╝ ╚═════╝  ╚══╝╚══╝ ╚═════╝ ╚═╝  ╚═══╝╚══════╝
EOF
    echo -e "${NC}"
    echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}    Multi-Connection SlowDNS Accelerator - Speed Edition${NC}"
    echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    # Auto-detect or manual input
    echo -e "${CYAN}Configuration:${NC}"
    echo ""
    
    # NS Domain
    read -rp "$(echo -e "${CYAN}NS Domain (e.g., ns.example.com): ${NC}")" NS_DOMAIN
    while [[ -z "$NS_DOMAIN" ]]; do
        error "NS Domain is required!"
        read -rp "$(echo -e "${CYAN}NS Domain: ${NC}")" NS_DOMAIN
    done
    
    # Target Host (Auto-detect)
    DEFAULT_IP=$(curl -s --max-time 3 ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')
    read -rp "$(echo -e "${CYAN}Target Host/IP [$DEFAULT_IP]: ${NC}")" TARGET_HOST
    TARGET_HOST=${TARGET_HOST:-$DEFAULT_IP}
    
    # Target Port
    read -rp "$(echo -e "${CYAN}Target Port [22 for SSH, 443 for Xray]: ${NC}")" TARGET_PORT
    TARGET_PORT=${TARGET_PORT:-22}
    
    # Connection count
    read -rp "$(echo -e "${CYAN}Number of parallel connections [8]: ${NC}")" CONN_INPUT
    CONNECTIONS=${CONN_INPUT:-8}
    [[ "$CONNECTIONS" -lt 2 ]] && CONNECTIONS=2
    [[ "$CONNECTIONS" -gt 16 ]] && CONNECTIONS=16
    
    echo ""
    info "Starting installation with $CONNECTIONS parallel connections..."
    echo ""
    
    # Installation steps
    install_dependencies
    install_slowdns
    create_load_balancer
    create_instances "$NS_DOMAIN" "$TARGET_HOST" "$TARGET_PORT"
    create_lb_service
    optimize_network
    setup_firewall
    show_status
    
    # Ask to manage
    echo ""
    read -rp "Open management menu? [Y/n]: " open_menu
    [[ "$open_menu" != "n" && "$open_menu" != "N" ]] && manage_connections
}

# Run
main "$@"
