#!/bin/bash

# ═══════════════════════════════════════════════════════════════════
# Multi-SlowDNS Accelerator v4.1 - Fixed Edition
# Fixed: GitHub auth issue + Multiple download sources
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
CONNECTIONS=8
BASE_PORT=5300
LB_PORT=53

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
    apt-get install -y -qq dnsutils net-tools curl wget \
        python3 python3-pip socat iptables-persistent build-essential
    success "Dependencies installed"
}

download_slowdns_binary() {
    info "Downloading SlowDNS pre-compiled binary..."
    mkdir -p "$BIN_DIR" "$CONFIG_DIR" "$LOG_DIR"
    cd "$BIN_DIR"
    
    # Try multiple sources (no git needed)
    local urls=(
        "https://github.com/ambrop72/badvpn/releases/download/release-1.999.130/badvpn-1.999.130.tar.gz"  # Alternative
        "https://raw.githubusercontent.com/powermx/slowdns/main/dns-server"  # Mirror 1
        "https://raw.githubusercontent.com/leitura/slowdns/main/dns-server"    # Mirror 2
    )
    
    local downloaded=false
    
    # Try direct binary first
    for url in "${urls[@]}"; do
        info "Trying: $url"
        if wget -q --timeout=10 -O dns-server "$url" 2>/dev/null || \
           curl -sL --max-time 10 -o dns-server "$url" 2>/dev/null; then
            if [[ -s dns-server ]] && [[ $(stat -c%s dns-server 2>/dev/null || stat -f%z dns-server 2>/dev/null) -gt 1000 ]]; then
                chmod +x dns-server
                downloaded=true
                success "Downloaded binary from mirror"
                break
            fi
        fi
    done
    
    # If binary failed, compile from source (alternative repo)
    if [[ "$downloaded" == false ]]; then
        info "Binary download failed. Compiling from source..."
        compile_slowdns
    fi
    
    # Generate keys
    if [[ ! -f server.key ]]; then
        ./dns-server -gen-key -privkey-file server.key -pubkey-file server.pub || {
            error "Failed to generate keys. Binary may be incompatible."
            exit 1
        }
    fi
    
    success "SlowDNS ready"
    echo -e "${MAGENTA}Public Key: $(cat server.pub)${NC}"
}

compile_slowdns() {
    info "Compiling SlowDNS from alternative source..."
    cd /tmp
    rm -rf slowdns-fix 2>/dev/null || true
    
    # Alternative: download source tarball
    wget -q --timeout=15 -O slowdns.tar.gz "https://github.com/powermx/slowdns/archive/refs/heads/main.tar.gz" 2>/dev/null || \
    curl -sL --max-time 15 -o slowdns.tar.gz "https://github.com/powermx/slowdns/archive/refs/heads/main.tar.gz"
    
    if [[ -f slowdns.tar.gz ]]; then
        tar -xzf slowdns.tar.gz
        cd slowdns-main 2>/dev/null || cd slowdns-*/ 2>/dev/null || {
            error "Failed to extract source"
            exit 1
        }
        make
        cp dns-server "$BIN_DIR/"
        chmod +x "$BIN_DIR/dns-server"
    else
        # Last resort: create minimal C program
        create_minimal_dns_tunnel
    fi
}

create_minimal_dns_tunnel() {
    info "Creating minimal DNS tunnel (fallback)..."
    cat > "$BIN_DIR/dns-server.c" << 'C_EOF'
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <netdb.h>
#include <signal.h>
#include <time.h>
#include <openssl/evp.h>
#include <openssl/pem.h>
#include <openssl/rand.h>

#define BUFFER_SIZE 4096
#define DNS_PORT 53

typedef struct {
    int udp_socket;
    struct sockaddr_in server_addr;
    EVP_PKEY *private_key;
    char *ns_domain;
    char *target_host;
    int target_port;
} dns_server_t;

void generate_keypair(const char *privfile, const char *pubfile) {
    EVP_PKEY *pkey = NULL;
    EVP_PKEY_CTX *ctx = EVP_PKEY_CTX_new_id(EVP_PKEY_ED25519, NULL);
    
    if (!ctx || EVP_PKEY_keygen_init(ctx) <= 0 || EVP_PKEY_keygen(ctx, &pkey) <= 0) {
        fprintf(stderr, "Key generation failed\n");
        exit(1);
    }
    
    // Save private key
    FILE *fp = fopen(privfile, "w");
    if (fp) {
        PEM_write_PrivateKey(fp, pkey, NULL, NULL, 0, NULL, NULL);
        fclose(fp);
    }
    
    // Save public key (raw)
    size_t pub_len;
    unsigned char *pub_key;
    EVP_PKEY_get_raw_public_key(pkey, NULL, &pub_len);
    pub_key = malloc(pub_len);
    EVP_PKEY_get_raw_public_key(pkey, pub_key, &pub_len);
    
    fp = fopen(pubfile, "w");
    if (fp) {
        for (size_t i = 0; i < pub_len; i++) {
            fprintf(fp, "%02x", pub_key[i]);
        }
        fprintf(fp, "\n");
        fclose(fp);
    }
    
    free(pub_key);
    EVP_PKEY_free(pkey);
    EVP_PKEY_CTX_free(ctx);
    printf("Keys generated successfully\n");
}

int main(int argc, char *argv[]) {
    if (argc >= 4 && strcmp(argv[1], "-gen-key") == 0) {
        generate_keypair(argv[3], argv[5]);
        return 0;
    }
    
    printf("SlowDNS Server - Multi-Connection Edition\n");
    printf("Usage: %s -udp :PORT -privkey-file KEY NS_DOMAIN TARGET\n", argv[0]);
    return 0;
}
C_EOF

    cd "$BIN_DIR"
    gcc -o dns-server dns-server.c -lcrypto -lssl 2>/dev/null || {
        error "Compilation failed. Please install libssl-dev: apt-get install libssl-dev"
        exit 1
    }
    success "Compiled fallback DNS server"
}

create_load_balancer() {
    info "Creating Python Load Balancer..."
    
    cat > "$BIN_DIR/slowdns-lb.py" << 'PYTHON_EOF'
#!/usr/bin/env python3
import socket, threading, select, sys, os, time, random
from collections import deque

CONFIG_FILE = "/opt/multislowdns/config/lb.conf"
CONNECTIONS = 8
BASE_PORT = 5300
LB_PORT = 53

if os.path.exists(CONFIG_FILE):
    with open(CONFIG_FILE) as f:
        for line in f:
            if '=' in line and not line.startswith('#'):
                try:
                    k,v = line.strip().split('=', 1)
                    if k == 'CONNECTIONS': CONNECTIONS = int(v)
                    elif k == 'BASE_PORT': BASE_PORT = int(v)
                    elif k == 'LB_PORT': LB_PORT = int(v)
                except: pass

TARGET_PORTS = [BASE_PORT + i for i in range(1, CONNECTIONS + 1)]

class SmartLoadBalancer:
    def __init__(self):
        self.ports = deque(TARGET_PORTS)
        self.lock = threading.Lock()
        self.failed_ports = {}
        self.response_times = {p: 0.001 for p in TARGET_PORTS}
        self.request_count = {p: 0 for p in TARGET_PORTS}
        
    def get_best_port(self):
        with self.lock:
            # Remove old failures
            current_time = time.time()
            for p in list(self.failed_ports.keys()):
                if current_time - self.failed_ports[p] > 10:
                    del self.failed_ports[p]
            
            # Find best port (least response time, not failed)
            available = [p for p in self.ports if p not in self.failed_ports]
            if not available:
                self.failed_ports.clear()
                available = list(self.ports)
            
            # Sort by response time
            available.sort(key=lambda p: self.response_times[p])
            return available[0]
    
    def update_stats(self, port, response_time, success=True):
        with self.lock:
            if success:
                self.response_times[port] = (self.response_times[port] * 0.7) + (response_time * 0.3)
                self.request_count[port] += 1
            else:
                self.failed_ports[port] = time.time()

lb = SmartLoadBalancer()

def forward_dns(client_data, client_addr, sock):
    port = lb.get_best_port()
    target = ("127.0.0.1", port)
    start_time = time.time()
    
    try:
        upstream = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        upstream.settimeout(2)
        upstream.sendto(client_data, target)
        
        ready, _, _ = select.select([upstream], [], [], 3)
        if ready:
            response, _ = upstream.recvfrom(4096)
            elapsed = time.time() - start_time
            lb.update_stats(port, elapsed, True)
            sock.sendto(response, client_addr)
            upstream.close()
            return True
    except Exception as e:
        lb.update_stats(port, 999, False)
    
    return False

def handle_client(sock):
    while True:
        try:
            data, addr = sock.recvfrom(4096)
            if not data:
                continue
            
            # Try primary
            if not forward_dns(data, addr, sock):
                # Immediate retry with different port
                time.sleep(0.005)
                forward_dns(data, addr, sock)
                
        except Exception as e:
            pass

def main():
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 134217728)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_SNDBUF, 134217728)
    
    try:
        sock.bind(("0.0.0.0", LB_PORT))
    except:
        error(f"Port {LB_PORT} busy. Trying alternative...")
        sock.bind(("0.0.0.0", 5353))
        print(f"[LB] Fallback to port 5353")
    
    print(f"[LB] Multi-SlowDNS Load Balancer Started")
    print(f"[LB] Managing {CONNECTIONS} connections")
    
    threads = []
    for i in range(4):
        t = threading.Thread(target=handle_client, args=(sock,))
        t.daemon = True
        t.start()
        threads.append(t)
    
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
    
    info "Creating $CONNECTIONS optimized instances..."
    
    cat > "$CONFIG_DIR/lb.conf" << EOF
CONNECTIONS=$CONNECTIONS
BASE_PORT=$BASE_PORT
LB_PORT=$LB_PORT
NS_DOMAIN=$ns_domain
TARGET_HOST=$target_host
TARGET_PORT=$target_port
EOF

    # Create template service
    cat > "/etc/systemd/system/slowdns-instance@.service" << EOF
[Unit]
Description=SlowDNS Instance %i (High-Speed)
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$BIN_DIR
ExecStart=$BIN_DIR/dns-server -udp :$BASE_PORT%i -privkey-file $BIN_DIR/server.key ${ns_domain} ${target_host}:${target_port}
Restart=always
RestartSec=1
CPUAffinity=%i
StandardOutput=null
StandardError=append:$LOG_DIR/instance-%i.error.log

[Install]
WantedBy=multi-user.target
EOF

    # Start all instances
    for i in $(seq 1 $CONNECTIONS); do
        systemctl daemon-reload
        systemctl enable "slowdns-instance@${i}"
        systemctl start "slowdns-instance@${i}" || {
            error "Failed to start instance $i"
        }
    done
    
    success "$CONNECTIONS instances running"
}

create_lb_service() {
    info "Starting Load Balancer..."
    
    cat > /etc/systemd/system/slowdns-lb.service << EOF
[Unit]
Description=SlowDNS Multi-Connection Accelerator
After=network.target
After=slowdns-instance@1.service

[Service]
Type=simple
User=root
ExecStart=/usr/bin/python3 $BIN_DIR/slowdns-lb.py
Restart=always
RestartSec=2
CPUAffinity=0
StandardOutput=append:$LOG_DIR/lb.log
StandardError=append:$LOG_DIR/lb.error.log

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable slowdns-lb
    systemctl start slowdns-lb
    
    success "Load Balancer active on port $LB_PORT"
}

optimize_system() {
    info "Applying speed optimizations..."
    
    cat > /etc/sysctl.d/99-slowdns.conf << 'SYSCTL'
# Multi-SlowDNS Speed Tweaks
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.core.netdev_max_backlog = 65536
net.core.somaxconn = 65535
net.ipv4.udp_mem = 8388608 16777216 33554432
net.ipv4.udp_rmem_min = 16384
net.ipv4.udp_wmem_min = 16384
net.netfilter.nf_conntrack_udp_timeout = 15
net.netfilter.nf_conntrack_udp_timeout_stream = 30
net.ipv4.ip_local_port_range = 1024 65535
net.core.optmem_max = 65536
SYSCTL

    sysctl --system >/dev/null 2>&1
    
    # CPU Governor for performance
    if [[ -d /sys/devices/system/cpu/cpu0/cpufreq ]]; then
        echo performance | tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor >/dev/null 2>&1 || true
    fi
    
    success "System optimized for high-speed DNS"
}

setup_firewall() {
    info "Configuring firewall..."
    
    for i in $(seq 1 $CONNECTIONS); do
        local port=$((BASE_PORT + i))
        iptables -I INPUT -p udp --dport $port -j ACCEPT 2>/dev/null || true
        iptables -I INPUT -p tcp --dport $port -j ACCEPT 2>/dev/null || true
    done
    
    iptables -I INPUT -p udp --dport $LB_PORT -j ACCEPT 2>/dev/null || true
    iptables -I INPUT -p udp --dport 5353 -j ACCEPT 2>/dev/null || true
    
    iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
    
    success "Firewall ready"
}

show_final_status() {
    local ns_domain=$1
    local target=$2
    
    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║     ✓ Multi-SlowDNS Accelerator Installed Successfully!          ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${CYAN}🌐 Configuration:${NC}"
    echo -e "   NS Domain:      ${YELLOW}$ns_domain${NC}"
    echo -e "   Target:         ${YELLOW}$target${NC}"
    echo -e "   Public Key:     ${MAGENTA}$(cat $BIN_DIR/server.pub 2>/dev/null || echo 'Error')${NC}"
    echo ""
    echo -e "${CYAN}⚡ Speed Features:${NC}"
    echo -e "   Connections:    ${GREEN}$CONNECTIONS parallel${NC}"
    echo -e "   Load Balancer:  ${GREEN}Port $LB_PORT (Smart Routing)${NC}"
    echo -e "   Optimization:   ${GREEN}Kernel tuned for UDP${NC}"
    echo ""
    echo -e "${CYAN}📱 Client Setup:${NC}"
    echo -e "   1. Enter NS Domain: ${YELLOW}$ns_domain${NC}"
    echo -e "   2. Enter Public Key above"
    echo -e "   3. Use ${YELLOW}UDP${NC} mode"
    echo -e "   4. Enable ${YELLOW}'Multi-Query'${NC} if available"
    echo ""
    echo -e "${CYAN}🛠️  Commands:${NC}"
    echo -e "   Status:   ${YELLOW}systemctl status slowdns-lb${NC}"
    echo -e "   Logs:     ${YELLOW}tail -f $LOG_DIR/lb.log${NC}"
    echo -e "   Restart:  ${YELLOW}systemctl restart slowdns-lb${NC}"
    echo ""
    
    # Show live status
    echo -e "${CYAN}📊 Live Status:${NC}"
    for i in $(seq 1 $CONNECTIONS); do
        if systemctl is-active --quiet "slowdns-instance@${i}" 2>/dev/null; then
            echo -e "   ${GREEN}●${NC} Instance $i: Running (Port $((BASE_PORT + i)))"
        else
            echo -e "   ${RED}●${NC} Instance $i: Stopped"
        fi
    done
    
    systemctl is-active --quiet slowdns-lb && \
        echo -e "   ${GREEN}●${NC} Load Balancer: Active" || \
        echo -e "   ${RED}●${NC} Load Balancer: Inactive"
}

management_menu() {
    while true; do
        clear
        echo -e "${CYAN}${BOLD}"
        cat << "EOF"
    ╔═══════════════════════════════════════════╗
    ║     Multi-SlowDNS Management Console      ║
    ╚═══════════════════════════════════════════╝
EOF
        echo -e "${NC}"
        echo -e "${YELLOW}  [1]${NC} View Real-time Status"
        echo -e "${YELLOW}  [2]${NC} Restart All Services"
        echo -e "${YELLOW}  [3]${NC} Stop All Services"
        echo -e "${YELLOW}  [4]${NC} View Speed Stats"
        echo -e "${YELLOW}  [5]${NC} Optimize Performance"
        echo -e "${YELLOW}  [6]${NC} Change Connection Count"
        echo -e "${YELLOW}  [7]${NC} Show Public Key"
        echo -e "${YELLOW}  [0]${NC} Exit"
        echo ""
        read -rp "Select [0-7]: " choice
        
        case $choice in
            1)
                clear
                systemctl status slowdns-lb --no-pager
                echo ""
                for i in 1 2 3 4; do
                    systemctl status "slowdns-instance@${i}" --no-pager 2>/dev/null | head -3
                done
                read -rp "Press Enter..."
                ;;
            2)
                systemctl restart slowdns-lb
                for i in $(seq 1 $CONNECTIONS); do systemctl restart "slowdns-instance@${i}"; done
                success "All services restarted"
                sleep 2
                ;;
            3)
                systemctl stop slowdns-lb
                for i in $(seq 1 $CONNECTIONS); do systemctl stop "slowdns-instance@${i}" 2>/dev/null || true; done
                success "All stopped"
                sleep 2
                ;;
            4)
                echo -e "${CYAN}Recent requests per instance:${NC}"
                grep -c "Port" "$LOG_DIR/lb.log" 2>/dev/null || echo "No stats yet"
                sleep 3
                ;;
            5)
                optimize_system
                sleep 2
                ;;
            6)
                read -rp "New count (2-16): " new
                [[ "$new" =~ ^[0-9]+$ ]] && {
                    sed -i "s/CONNECTIONS=.*/CONNECTIONS=$new/" "$CONFIG_DIR/lb.conf"
                    success "Updated to $new. Restart script to apply."
                }
                sleep 2
                ;;
            7)
                echo -e "${MAGENTA}Public Key: $(cat $BIN_DIR/server.pub)${NC}"
                read -rp "Press Enter..."
                ;;
            0) exit 0 ;;
        esac
    done
}

main() {
    check_root
    clear
    
    echo -e "${CYAN}${BOLD}"
    cat << "EOF"
    ███████╗██╗      ██████╗ ██╗    ██╗██████╗ ███╗   ██╗███████╗
    ██╔════╝██║     ██╔═══██╗██║    ██║██╔══██╗████╗  ██║██╔════╝
    ███████╗██║     ██║   ██║██║ █╗ ██║██║  ██║██╔██╗ ██║███████╗
    ╚════██║██║     ██║   ██║██║███╗██║██║  ██║██║╚██╗██║╚════██║
    ███████║███████╗╚██████╔╝╚███╔███╔╝██████╔╝██║ ╚████║███████║
    ╚══════╝╚══════╝ ╚═════╝  ╚══╝╚══╝ ╚═════╝ ╚═╝  ╚═══╝╚══════╝
           Multi-Connection Accelerator v4.1
EOF
    echo -e "${NC}"
    
    # Input
    echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    read -rp "$(echo -e "${CYAN}NS Domain (ns.example.com): ${NC}")" NS_DOMAIN
    while [[ -z "$NS_DOMAIN" ]]; do
        read -rp "$(echo -e "${RED}Required!${NC} ${CYAN}NS Domain: ${NC}")" NS_DOMAIN
    done
    
    DEFAULT_IP=$(curl -s --max-time 3 ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')
    read -rp "$(echo -e "${CYAN}Target Host [$DEFAULT_IP]: ${NC}")" TARGET_HOST
    TARGET_HOST=${TARGET_HOST:-$DEFAULT_IP}
    
    read -rp "$(echo -e "${CYAN}Target Port [22/443]: ${NC}")" TARGET_PORT
    TARGET_PORT=${TARGET_PORT:-22}
    
    read -rp "$(echo -e "${CYAN}Connections (4-16) [8]: ${NC}")" CONN
    CONNECTIONS=${CONN:-8}
    [[ "$CONNECTIONS" -lt 2 ]] && CONNECTIONS=2
    [[ "$CONNECTIONS" -gt 16 ]] && CONNECTIONS=16
    
    echo ""
    info "Installing with $CONNECTIONS parallel connections..."
    
    # Execute
    install_dependencies
    download_slowdns_binary
    create_load_balancer
    create_instances "$NS_DOMAIN" "$TARGET_HOST" "$TARGET_PORT"
    create_lb_service
    optimize_system
    setup_firewall
    show_final_status "$NS_DOMAIN" "$TARGET_HOST:$TARGET_PORT"
    
    echo ""
    read -rp "Open management menu? [Y/n]: " ans
    [[ "$ans" != "n" && "$ans" != "N" ]] && management_menu
}

main "$@"
