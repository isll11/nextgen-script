#!/bin/bash

# NeXTGen Script - Complete Version
# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'
BOLD='\033[1m'

SCRIPT_DIR="/etc/nextgen"
CONFIG_DIR="$SCRIPT_DIR/config"
LOG_DIR="$SCRIPT_DIR/logs"
SLOWDNS_DIR="$SCRIPT_DIR/slowdns"

mkdir -p $SCRIPT_DIR $CONFIG_DIR $LOG_DIR $SLOWDNS_DIR

show_banner() {
    clear
    echo -e "${CYAN}${BOLD}"
    cat << "EOF"
    ███╗   ██╗███████╗██╗  ██╗████████╗ ██████╗ ███████╗███╗   ██╗
    ████╗  ██║██╔════╝╚██╗██╔╝╚══██╔══╝██╔════╝ ██╔════╝████╗  ██║
    ██╔██╗ ██║█████╗   ╚███╔╝    ██║   ██║  ███╗█████╗  ██╔██╗ ██║
    ██║╚██╗██║██╔══╝   ██╔██╗    ██║   ██║   ██║██╔══╝  ██║╚██╗██║
    ██║ ╚████║███████╗██╔╝ ██╗   ██║   ╚██████╔╝███████╗██║ ╚████║
    ╚═╝  ╚═══╝╚══════╝╚═╝  ╚═╝   ╚═╝    ╚═════╝ ╚══════╝╚═╝  ╚═══╝
EOF
    echo -e "${MAGENTA}${BOLD}                    S C R I P T${NC}"
    echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}              Ultimate VPS & Tunneling Manager${NC}"
    echo -e "${CYAN}                    Version: 2.0 | Premium${NC}"
    echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
}

main_menu() {
    while true; do
        show_banner
        echo -e "${WHITE}${BOLD}                         MAIN MENU${NC}"
        echo -e "${YELLOW}───────────────────────────────────────────────────────────────${NC}"
        echo ""
        echo -e "${CYAN}  [01]${NC} ${GREEN}• SSH/WS MENU${NC}          ${CYAN}[05]${NC} ${GREEN}• SOCKS MENU${NC}"
        echo -e "${CYAN}  [02]${NC} ${GREEN}• VMESS MENU${NC}           ${CYAN}[06]${NC} ${GREEN}• SQUID PROXY${NC}"
        echo -e "${CYAN}  [03]${NC} ${GREEN}• VLESS MENU${NC}           ${CYAN}[07]${NC} ${MAGENTA}• SLOWDNS MANAGER${NC}"
        echo -e "${CYAN}  [04]${NC} ${GREEN}• TROJAN MENU${NC}          ${CYAN}[08]${NC} ${MAGENTA}• MULTI-SLOWDNS${NC}"
        echo ""
        echo -e "${CYAN}  [09]${NC} ${YELLOW}• SYSTEM STATUS${NC}        ${CYAN}[10]${NC} ${YELLOW}• OPTIMIZE SYSTEM${NC}"
        echo -e "${CYAN}  [11]${NC} ${YELLOW}• BACKUP/RESTORE${NC}       ${CYAN}[00]${NC} ${RED}• EXIT${NC}"
        echo ""
        echo -e "${YELLOW}───────────────────────────────────────────────────────────────${NC}"
        read -p "$(echo -e "${WHITE}${BOLD}Select an option [00-11]: ${NC}")" choice

        case $choice in
            01|1) ssh_menu ;;
            02|2) vmess_menu ;;
            03|3) vless_menu ;;
            04|4) trojan_menu ;;
            05|5) socks_menu ;;
            06|6) squid_menu ;;
            07|7) slowdns_menu ;;
            08|8) multi_slowdns_menu ;;
            09|9) system_status ;;
            10) optimize_system ;;
            11) backup_restore ;;
            00|0) exit 0 ;;
            *) echo -e "${RED}Invalid option!${NC}"; sleep 1 ;;
        esac
    done
}

ssh_menu() {
    while true; do
        show_banner
        echo -e "${WHITE}${BOLD}                      SSH/WEBSOCKET MENU${NC}"
        echo -e "${YELLOW}───────────────────────────────────────────────────────────────${NC}"
        echo ""
        echo -e "${CYAN}  [01]${NC} ${GREEN}• Create SSH Account${NC}"
        echo -e "${CYAN}  [02]${NC} ${GREEN}• Delete SSH Account${NC}"
        echo -e "${CYAN}  [03]${NC} ${GREEN}• Renew SSH Account${NC}"
        echo -e "${CYAN}  [04]${NC} ${GREEN}• Check SSH Users${NC}"
        echo -e "${CYAN}  [05]${NC} ${MAGENTA}• Enable SlowDNS + SSH${NC}"
        echo -e "${CYAN}  [06]${NC} ${MAGENTA}• Disable SlowDNS + SSH${NC}"
        echo -e "${CYAN}  [07]${NC} ${YELLOW}• Change SSH Port${NC}"
        echo -e "${CYAN}  [00]${NC} ${RED}• Back to Main Menu${NC}"
        echo ""
        read -p "$(echo -e "${WHITE}${BOLD}Select option [00-07]: ${NC}")" choice

        case $choice in
            01|1) create_ssh_account ;;
            02|2) delete_ssh_account ;;
            03|3) renew_ssh_account ;;
            04|4) check_ssh_users ;;
            05|5) enable_slowdns "ssh" ;;
            06|6) disable_slowdns "ssh" ;;
            07|7) change_ssh_port ;;
            00|0) break ;;
            *) echo -e "${RED}Invalid!${NC}"; sleep 1 ;;
        esac
    done
}

vmess_menu() {
    while true; do
        show_banner
        echo -e "${WHITE}${BOLD}                        VMESS MENU${NC}"
        echo -e "${YELLOW}───────────────────────────────────────────────────────────────${NC}"
        echo ""
        echo -e "${CYAN}  [01]${NC} ${GREEN}• Create VMESS Account${NC}"
        echo -e "${CYAN}  [02]${NC} ${GREEN}• Check VMESS Users${NC}"
        echo -e "${CYAN}  [03]${NC} ${GREEN}• Show VMESS Links${NC}"
        echo -e "${CYAN}  [04]${NC} ${MAGENTA}• Enable SlowDNS + VMESS${NC}"
        echo -e "${CYAN}  [05]${NC} ${MAGENTA}• Disable SlowDNS + VMESS${NC}"
        echo -e "${CYAN}  [00]${NC} ${RED}• Back to Main Menu${NC}"
        echo ""
        read -p "$(echo -e "${WHITE}${BOLD}Select option [00-05]: ${NC}")" choice

        case $choice in
            01|1) create_vmess_account ;;
            02|2) check_vmess_users ;;
            03|3) show_vmess_links ;;
            04|4) enable_slowdns "vmess" ;;
            05|5) disable_slowdns "vmess" ;;
            00|0) break ;;
            *) echo -e "${RED}Invalid!${NC}"; sleep 1 ;;
        esac
    done
}

vless_menu() {
    while true; do
        show_banner
        echo -e "${WHITE}${BOLD}                        VLESS MENU${NC}"
        echo -e "${YELLOW}───────────────────────────────────────────────────────────────${NC}"
        echo ""
        echo -e "${CYAN}  [01]${NC} ${GREEN}• Create VLESS Account${NC}"
        echo -e "${CYAN}  [02]${NC} ${GREEN}• Check VLESS Users${NC}"
        echo -e "${CYAN}  [03]${NC} ${GREEN}• Show VLESS Links${NC}"
        echo -e "${CYAN}  [04]${NC} ${MAGENTA}• Enable SlowDNS + VLESS${NC}"
        echo -e "${CYAN}  [05]${NC} ${MAGENTA}• Disable SlowDNS + VLESS${NC}"
        echo -e "${CYAN}  [00]${NC} ${RED}• Back to Main Menu${NC}"
        echo ""
        read -p "$(echo -e "${WHITE}${BOLD}Select option [00-05]: ${NC}")" choice

        case $choice in
            01|1) create_vless_account ;;
            02|2) check_vless_users ;;
            03|3) show_vless_links ;;
            04|4) enable_slowdns "vless" ;;
            05|5) disable_slowdns "vless" ;;
            00|0) break ;;
            *) echo -e "${RED}Invalid!${NC}"; sleep 1 ;;
        esac
    done
}

trojan_menu() {
    while true; do
        show_banner
        echo -e "${WHITE}${BOLD}                       TROJAN MENU${NC}"
        echo -e "${YELLOW}───────────────────────────────────────────────────────────────${NC}"
        echo ""
        echo -e "${CYAN}  [01]${NC} ${GREEN}• Create TROJAN Account${NC}"
        echo -e "${CYAN}  [02]${NC} ${GREEN}• Check TROJAN Users${NC}"
        echo -e "${CYAN}  [03]${NC} ${GREEN}• Show TROJAN Links${NC}"
        echo -e "${CYAN}  [00]${NC} ${RED}• Back to Main Menu${NC}"
        echo ""
        read -p "$(echo -e "${WHITE}${BOLD}Select option [00-03]: ${NC}")" choice

        case $choice in
            01|1) create_trojan_account ;;
            02|2) check_trojan_users ;;
            03|3) show_trojan_links ;;
            00|0) break ;;
            *) echo -e "${RED}Invalid!${NC}"; sleep 1 ;;
        esac
    done
}

socks_menu() {
    while true; do
        show_banner
        echo -e "${WHITE}${BOLD}                        SOCKS MENU${NC}"
        echo -e "${YELLOW}───────────────────────────────────────────────────────────────${NC}"
        echo ""
        echo -e "${CYAN}  [01]${NC} ${GREEN}• Install SOCKS5${NC}"
        echo -e "${CYAN}  [02]${NC} ${GREEN}• Show SOCKS Status${NC}"
        echo -e "${CYAN}  [00]${NC} ${RED}• Back to Main Menu${NC}"
        echo ""
        read -p "$(echo -e "${WHITE}${BOLD}Select option [00-02]: ${NC}")" choice

        case $choice in
            01|1) install_socks ;;
            02|2) show_socks_status ;;
            00|0) break ;;
            *) echo -e "${RED}Invalid!${NC}"; sleep 1 ;;
        esac
    done
}

squid_menu() {
    while true; do
        show_banner
        echo -e "${WHITE}${BOLD}                      SQUID PROXY MENU${NC}"
        echo -e "${YELLOW}───────────────────────────────────────────────────────────────${NC}"
        echo ""
        echo -e "${CYAN}  [01]${NC} ${GREEN}• Install Squid Proxy${NC}"
        echo -e "${CYAN}  [02]${NC} ${GREEN}• Change Squid Port${NC}"
        echo -e "${CYAN}  [03]${NC} ${GREEN}• Add Squid User${NC}"
        echo -e "${CYAN}  [04]${NC} ${GREEN}• Show Squid Status${NC}"
        echo -e "${CYAN}  [00]${NC} ${RED}• Back to Main Menu${NC}"
        echo ""
        read -p "$(echo -e "${WHITE}${BOLD}Select option [00-04]: ${NC}")" choice

        case $choice in
            01|1) install_squid ;;
            02|2) change_squid_port ;;
            03|3) add_squid_user ;;
            04|4) show_squid_status ;;
            00|0) break ;;
            *) echo -e "${RED}Invalid!${NC}"; sleep 1 ;;
        esac
    done
}

slowdns_menu() {
    while true; do
        show_banner
        echo -e "${WHITE}${BOLD}                      SLOWDNS MANAGER${NC}"
        echo -e "${YELLOW}───────────────────────────────────────────────────────────────${NC}"
        echo ""
        echo -e "${CYAN}  [01]${NC} ${GREEN}• Install SlowDNS${NC}"
        echo -e "${CYAN}  [02]${NC} ${GREEN}• Show Public Key${NC}"
        echo -e "${CYAN}  [03]${NC} ${YELLOW}• Show SlowDNS Status${NC}"
        echo -e "${CYAN}  [00]${NC} ${RED}• Back to Main Menu${NC}"
        echo ""
        read -p "$(echo -e "${WHITE}${BOLD}Select option [00-03]: ${NC}")" choice

        case $choice in
            01|1) install_slowdns ;;
            02|2) show_slowdns_pubkey ;;
            03|3) show_slowdns_status ;;
            00|0) break ;;
            *) echo -e "${RED}Invalid!${NC}"; sleep 1 ;;
        esac
    done
}

multi_slowdns_menu() {
    while true; do
        show_banner
        echo -e "${WHITE}${BOLD}              MULTI-SLOWDNS ACCELERATOR${NC}"
        echo -e "${YELLOW}───────────────────────────────────────────────────────────────${NC}"
        echo ""
        echo -e "${CYAN}  [01]${NC} ${GREEN}• Install Multi-SlowDNS${NC}"
        echo -e "${CYAN}  [02]${NC} ${GREEN}• Show Status${NC}"
        echo -e "${CYAN}  [03]${NC} ${YELLOW}• Optimize Performance${NC}"
        echo -e "${CYAN}  [00]${NC} ${RED}• Back to Main Menu${NC}"
        echo ""
        read -p "$(echo -e "${WHITE}${BOLD}Select option [00-03]: ${NC}")" choice

        case $choice in
            01|1) install_multi_slowdns ;;
            02|2) show_multi_slowdns_status ;;
            03|3) optimize_slowdns_performance ;;
            00|0) break ;;
            *) echo -e "${RED}Invalid!${NC}"; sleep 1 ;;
        esac
    done
}

create_ssh_account() {
    show_banner
    echo -e "${WHITE}${BOLD}                    CREATE SSH ACCOUNT${NC}"
    echo -e "${YELLOW}───────────────────────────────────────────────────────────────${NC}"
    echo ""
    read -p "$(echo -e "${CYAN}Username: ${NC}")" username
    read -s -p "$(echo -e "${CYAN}Password: ${NC}")" password
    echo ""
    read -p "$(echo -e "${CYAN}Expiry Days: ${NC}")" days

    useradd -m -s /bin/false "$username" 2>/dev/null || usermod -s /bin/false "$username"
    echo "$username:$password" | chpasswd

    expiry=$(date -d "+$days days" +"%Y-%m-%d")
    chage -E "$expiry" "$username"

    echo "$username:$password:$expiry:SSH" >> $CONFIG_DIR/ssh_users.db

    echo ""
    echo -e "${GREEN}✓ SSH Account Created Successfully!${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${WHITE}Username:${NC} $username"
    echo -e "${WHITE}Password:${NC} $password"
    echo -e "${WHITE}Expires:${NC} $expiry"
    echo -e "${WHITE}Host:${NC} $(curl -s ifconfig.me 2>/dev/null || echo 'YOUR-SERVER-IP')"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    read -p "Press Enter to continue..."
}

create_vmess_account() {
    show_banner
    echo -e "${WHITE}${BOLD}                   CREATE VMESS ACCOUNT${NC}"
    echo -e "${YELLOW}───────────────────────────────────────────────────────────────${NC}"
    echo ""
    read -p "$(echo -e "${CYAN}Username: ${NC}")" username
    read -p "$(echo -e "${CYAN}Expiry Days: ${NC}")" days

    uuid=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || openssl rand -hex 16 | sed 's/\(..\{8\}\)\(..\{4\}\)\(..\{4\}\)\(..\{4\}\)\(..\{12\}\)/\1-\2-\3-\4-\5/')

    expiry=$(date -d "+$days days" +"%Y-%m-%d")
    echo "$username:$uuid:$expiry:VMESS" >> $CONFIG_DIR/vmess_users.db

    domain=$(hostname -f 2>/dev/null || curl -s ifconfig.me)

    vmess_json="{\"v\":\"2\",\"ps\":\"$username\",\"add\":\"$domain\",\"port\":\"443\",\"id\":\"$uuid\",\"aid\":\"0\",\"scy\":\"auto\",\"net\":\"ws\",\"type\":\"none\",\"host\":\"$domain\",\"path\":\"/vmess\",\"tls\":\"tls\"}"
    vmess_link=$(echo -n "$vmess_json" | base64 -w 0)

    echo ""
    echo -e "${GREEN}✓ VMESS Account Created Successfully!${NC}"
    echo -e "${CYAN}Username:${NC} $username"
    echo -e "${CYAN}UUID:${NC} $uuid"
    echo -e "${CYAN}VMESS Link:${NC} ${GREEN}vmess://$vmess_link${NC}"
    echo ""
    read -p "Press Enter to continue..."
}

create_vless_account() {
    show_banner
    echo -e "${WHITE}${BOLD}                   CREATE VLESS ACCOUNT${NC}"
    echo -e "${YELLOW}───────────────────────────────────────────────────────────────${NC}"
    echo ""
    read -p "$(echo -e "${CYAN}Username: ${NC}")" username
    read -p "$(echo -e "${CYAN}Expiry Days: ${NC}")" days

    uuid=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || openssl rand -hex 16 | sed 's/\(..\{8\}\)\(..\{4\}\)\(..\{4\}\)\(..\{4\}\)\(..\{12\}\)/\1-\2-\3-\4-\5/')

    expiry=$(date -d "+$days days" +"%Y-%m-%d")
    echo "$username:$uuid:$expiry:VLESS" >> $CONFIG_DIR/vless_users.db

    domain=$(hostname -f 2>/dev/null || curl -s ifconfig.me)

    vless_ws="vless://$uuid@$domain:443?security=tls&encryption=none&host=$domain&type=ws&path=%2Fvless&sni=$domain#$username"

    echo ""
    echo -e "${GREEN}✓ VLESS Account Created Successfully!${NC}"
    echo -e "${CYAN}Username:${NC} $username"
    echo -e "${CYAN}UUID:${NC} $uuid"
    echo -e "${CYAN}VLESS Link:${NC} ${GREEN}$vless_ws${NC}"
    echo ""
    read -p "Press Enter to continue..."
}

create_trojan_account() {
    show_banner
    echo -e "${WHITE}${BOLD}                  CREATE TROJAN ACCOUNT${NC}"
    echo -e "${YELLOW}───────────────────────────────────────────────────────────────${NC}"
    echo ""
    read -p "$(echo -e "${CYAN}Username: ${NC}")" username
    read -p "$(echo -e "${CYAN}Password (leave blank for auto): ${NC}")" password
    [ -z "$password" ] && password=$(openssl rand -base64 12)
    read -p "$(echo -e "${CYAN}Expiry Days: ${NC}")" days

    expiry=$(date -d "+$days days" +"%Y-%m-%d")
    echo "$username:$password:$expiry:TROJAN" >> $CONFIG_DIR/trojan_users.db

    domain=$(hostname -f 2>/dev/null || curl -s ifconfig.me)

    trojan_link="trojan://$password@$domain:443?security=tls&host=$domain&type=ws&path=%2Ftrojan&sni=$domain#$username"

    echo ""
    echo -e "${GREEN}✓ TROJAN Account Created Successfully!${NC}"
    echo -e "${CYAN}Username:${NC} $username"
    echo -e "${CYAN}Password:${NC} $password"
    echo -e "${CYAN}Trojan Link:${NC} ${GREEN}$trojan_link${NC}"
    echo ""
    read -p "Press Enter to continue..."
}

install_squid() {
    show_banner
    echo -e "${CYAN}Select Port:${NC}"
    echo -e "${WHITE}  [1]${NC} Port 3128 (Default)"
    echo -e "${WHITE}  [2]${NC} Port 80 (HTTP)"
    echo -e "${WHITE}  [3]${NC} Port 8080"
    echo -e "${WHITE}  [4]${NC} Custom Port"
    echo ""
    read -p "Choice [1-4]: " port_choice

    case $port_choice in
        1) squid_port=3128 ;;
        2) squid_port=80 ;;
        3) squid_port=8080 ;;
        4) read -p "Enter custom port: " squid_port ;;
        *) squid_port=3128 ;;
    esac

    echo -e "${YELLOW}Installing Squid on port $squid_port...${NC}"
    apt-get update >/dev/null 2>&1
    apt-get install -y squid apache2-utils >/dev/null 2>&1

    cat > /etc/squid/squid.conf << EOF
http_port $squid_port
visible_hostname NeXTGenProxy
auth_param basic program /usr/lib/squid/basic_ncsa_auth /etc/squid/passwd
auth_param basic realm NeXTGen Proxy
acl authenticated proxy_auth REQUIRED
http_access allow authenticated
http_access deny all
forwarded_for delete
via off
EOF

    touch /etc/squid/passwd
    chown proxy:proxy /etc/squid/passwd 2>/dev/null

    echo "SQUID_PORT=$squid_port" > $CONFIG_DIR/squid.conf

    systemctl restart squid 2>/dev/null
    systemctl enable squid 2>/dev/null
    ufw allow $squid_port/tcp 2>/dev/null || iptables -I INPUT -p tcp --dport $squid_port -j ACCEPT 2>/dev/null

    echo -e "${GREEN}✓ Squid Installed on port $squid_port!${NC}"
    sleep 2
}

change_squid_port() {
    current_port=$(grep "^http_port" /etc/squid/squid.conf 2>/dev/null | awk '{print $2}')
    echo -e "Current Port: $current_port"
    read -p "Enter new port: " new_port

    sed -i "s/^http_port .*/http_port $new_port/" /etc/squid/squid.conf
    systemctl restart squid 2>/dev/null
    echo "SQUID_PORT=$new_port" > $CONFIG_DIR/squid.conf

    echo -e "${GREEN}✓ Port changed to $new_port${NC}"
    sleep 2
}

add_squid_user() {
    read -p "Username: " username
    htpasswd /etc/squid/passwd "$username"
    systemctl reload squid 2>/dev/null
    echo -e "${GREEN}✓ User added!${NC}"
    sleep 2
}

show_squid_status() {
    systemctl is-active --quiet squid 2>/dev/null && echo -e "${GREEN}Squid: Running${NC}" || echo -e "${RED}Squid: Stopped${NC}"
    port=$(grep "^http_port" /etc/squid/squid.conf 2>/dev/null | awk '{print $2}')
    echo "Port: $port"
    [ -f /etc/squid/passwd ] && echo "Users:" && cut -d: -f1 /etc/squid/passwd | while read u; do echo "  - $u"; done
    sleep 3
}

install_slowdns() {
    echo -e "${YELLOW}Installing SlowDNS...${NC}"
    apt-get update >/dev/null 2>&1
    apt-get install -y dnsutils net-tools >/dev/null 2>&1

    cd $SLOWDNS_DIR
    wget -q https://github.com/slackjeff/slowdns/raw/main/dns-server -O dns-server 2>/dev/null ||     curl -sL https://github.com/slackjeff/slowdns/raw/main/dns-server -o dns-server

    chmod +x dns-server
    ./dns-server -gen-key -privkey-file server.key -pubkey-file server.pub

    echo -e "${GREEN}✓ SlowDNS Installed!${NC}"
    cat server.pub
    sleep 3
}

show_slowdns_pubkey() {
    [ -f $SLOWDNS_DIR/server.pub ] && cat $SLOWDNS_DIR/server.pub || echo "No keys found"
    sleep 3
}

show_slowdns_status() {
    for svc in slowdns-ssh slowdns-vmess slowdns-vless; do
        status=$(systemctl is-active $svc 2>/dev/null || echo "inactive")
        [ "$status" = "active" ] && echo -e "${GREEN}●${NC} $svc: Running" || echo -e "${RED}●${NC} $svc: Stopped"
    done
    sleep 3
}

enable_slowdns() {
    local proto=$1
    show_banner
    echo -e "${WHITE}${BOLD}              ENABLE SLOWDNS + ${proto^^}${NC}"
    echo ""
    read -p "NS Domain (e.g., ns.yourdomain.com): " ns_domain
    read -p "SlowDNS Port (default 5300): " slowdns_port
    slowdns_port=${slowdns_port:-5300}

    case $proto in
        ssh) target_port=22 ;;
        vmess|vless|trojan) 
            read -p "Xray Port (default 443): " target_port
            target_port=${target_port:-443}
            ;;
    esac

    cat > /etc/systemd/system/slowdns-${proto}.service << EOF
[Unit]
Description=SlowDNS ${proto^^} Tunnel
After=network.target
[Service]
Type=simple
ExecStart=$SLOWDNS_DIR/dns-server -udp :$slowdns_port -privkey-file $SLOWDNS_DIR/server.key $ns_domain 127.0.0.1:$target_port
Restart=always
[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable slowdns-${proto}
    systemctl start slowdns-${proto}

    echo -e "${GREEN}✓ SlowDNS + ${proto^^} Enabled!${NC}"
    sleep 2
}

disable_slowdns() {
    local proto=$1
    systemctl stop slowdns-$proto 2>/dev/null
    systemctl disable slowdns-$proto 2>/dev/null
    echo -e "${GREEN}✓ SlowDNS $proto stopped${NC}"
    sleep 2
}

install_multi_slowdns() {
    show_banner
    if [ ! -f "$SLOWDNS_DIR/dns-server" ]; then
        echo -e "${RED}Install base SlowDNS first!${NC}"
        sleep 2
        return
    fi

    read -p "NS Domain: " ns_domain
    read -p "Target Port (22/443): " target_port
    read -p "Number of instances (4-8, default 4): " instances
    instances=${instances:-4}

    [ "$instances" -lt 1 ] || [ "$instances" -gt 8 ] && instances=4

    if [ ! -f "$SLOWDNS_DIR/server.key" ]; then
        cd $SLOWDNS_DIR
        ./dns-server -gen-key -privkey-file server.key -pubkey-file server.pub
    fi

    echo "NS_DOMAIN=$ns_domain" > $CONFIG_DIR/multislowdns.conf
    echo "TARGET_PORT=$target_port" >> $CONFIG_DIR/multislowdns.conf
    echo "INSTANCES=$instances" >> $CONFIG_DIR/multislowdns.conf

    # Create Python Load Balancer
    cat > /usr/local/bin/slowdns-lb << 'PYEOF'
#!/usr/bin/env python3
import socket, threading, sys
config = {}
with open('/etc/nextgen/config/multislowdns.conf', 'r') as f:
    for line in f:
        if '=' in line:
            k, v = line.strip().split('=', 1)
            config[k] = v
INSTANCES = int(config.get('INSTANCES', 4))
PORTS = [(5300 + i) for i in range(1, INSTANCES + 1)]
idx = 0
sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.bind(("0.0.0.0", 53))
print(f"[LB] Started with {INSTANCES} instances on port 53")
while True:
    data, addr = sock.recvfrom(4096)
    target = ("127.0.0.1", PORTS[idx % len(PORTS)])
    idx += 1
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.settimeout(5)
        s.sendto(data, target)
        resp, _ = s.recvfrom(4096)
        sock.sendto(resp, addr)
        s.close()
    except: pass
PYEOF
    chmod +x /usr/local/bin/slowdns-lb

    # Create instances
    for i in $(seq 1 $instances); do
        dns_port=$((5300 + i))
        cat > /etc/systemd/system/slowdns-multi@${i}.service << EOF
[Unit]
Description=SlowDNS Instance $i
[Service]
ExecStart=$SLOWDNS_DIR/dns-server -udp :${dns_port} -privkey-file $SLOWDNS_DIR/server.key $ns_domain 127.0.0.1:$target_port
Restart=always
[Install]
WantedBy=multi-user.target
EOF
        systemctl enable slowdns-multi@${i}
        systemctl start slowdns-multi@${i}
    done

    # Load Balancer service
    cat > /etc/systemd/system/slowdns-lb.service << EOF
[Unit]
Description=SlowDNS Load Balancer
[Service]
ExecStart=/usr/local/bin/slowdns-lb
Restart=always
[Install]
WantedBy=multi-user.target
EOF
    systemctl enable slowdns-lb
    systemctl start slowdns-lb

    # Optimize
    echo "net.core.rmem_max = 134217728" >> /etc/sysctl.conf
    echo "net.core.wmem_max = 134217728" >> /etc/sysctl.conf
    sysctl -p >/dev/null 2>&1

    echo -e "${GREEN}✓ Multi-SlowDNS Installed!${NC}"
    echo -e "Instances: $instances (ports 5301-$((5300 + instances)))"
    echo -e "Load Balancer: Port 53"
    sleep 3
}

show_multi_slowdns_status() {
    systemctl is-active --quiet slowdns-lb 2>/dev/null && echo -e "${GREEN}● Load Balancer: Running${NC}" || echo -e "${RED}● Load Balancer: Stopped${NC}"
    for i in $(seq 1 8); do
        if systemctl is-active --quiet slowdns-multi@${i} 2>/dev/null; then
            echo -e "${GREEN}●${NC} Instance $i: Running (Port $((5300 + i)))"
        fi
    done
    sleep 3
}

optimize_slowdns_performance() {
    echo "net.core.rmem_max = 134217728" >> /etc/sysctl.conf
    echo "net.core.wmem_max = 134217728" >> /etc/sysctl.conf
    echo "net.ipv4.udp_mem = 8388608 12582912 16777216" >> /etc/sysctl.conf
    sysctl -p >/dev/null 2>&1
    echo "* soft nofile 65535" >> /etc/security/limits.conf
    echo "* hard nofile 65535" >> /etc/security/limits.conf
    echo -e "${GREEN}✓ Optimized!${NC}"
    sleep 2
}

system_status() {
    show_banner
    echo -e "${WHITE}${BOLD}                    SYSTEM STATUS${NC}"
    echo -e "${YELLOW}───────────────────────────────────────────────────────────────${NC}"
    echo ""
    echo -e "${CYAN}Services:${NC}"
    for svc in ssh squid xray slowdns-ssh slowdns-vmess slowdns-vless slowdns-lb; do
        status=$(systemctl is-active $svc 2>/dev/null || echo "inactive")
        [ "$status" = "active" ] && echo -e "  ${GREEN}●${NC} $svc: Running" || echo -e "  ${RED}●${NC} $svc: Stopped"
    done
    echo ""
    echo -e "${CYAN}System Info:${NC}"
    echo -e "  IP: $(curl -s ifconfig.me 2>/dev/null || echo 'N/A')"
    echo -e "  Uptime: $(uptime -p 2>/dev/null)"
    echo -e "  Memory: $(free -h 2>/dev/null | grep Mem | awk '{print $3"/"$2}')"
    echo ""
    read -p "Press Enter..."
}

optimize_system() {
    cat >> /etc/sysctl.conf << EOF
net.ipv4.tcp_fast_open = 3
net.ipv4.tcp_tw_reuse = 1
net.core.somaxconn = 65535
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF
    sysctl -p >/dev/null 2>&1
    echo -e "${GREEN}✓ System optimized with BBR!${NC}"
    sleep 2
}

delete_ssh_account() {
    read -p "Username to delete: " username
    userdel -r "$username" 2>/dev/null && echo -e "${GREEN}✓ Deleted${NC}" || echo -e "${RED}✗ Not found${NC}"
    sed -i "/^$username:/d" $CONFIG_DIR/ssh_users.db 2>/dev/null
    sleep 2
}

renew_ssh_account() {
    read -p "Username: " username
    read -p "Additional days: " days
    chage -E $(date -d "+$days days" +"%Y-%m-%d") "$username" 2>/dev/null && echo -e "${GREEN}✓ Renewed${NC}" || echo -e "${RED}✗ Failed${NC}"
    sleep 2
}

check_ssh_users() {
    [ -f $CONFIG_DIR/ssh_users.db ] && cut -d: -f1,3 $CONFIG_DIR/ssh_users.db | column -t -s: || echo "No users"
    sleep 3
}

change_ssh_port() {
    read -p "New SSH port: " port
    sed -i "s/^#Port 22/Port $port/" /etc/ssh/sshd_config
    sed -i "s/^Port [0-9]*/Port $port/" /etc/ssh/sshd_config
    systemctl restart sshd
    echo -e "${GREEN}✓ SSH port changed to $port${NC}"
    sleep 2
}

check_vmess_users() { 
    [ -f $CONFIG_DIR/vmess_users.db ] && cat $CONFIG_DIR/vmess_users.db | column -t -s: || echo "No users"
    sleep 3
}
show_vmess_links() { 
    [ -f $CONFIG_DIR/vmess_users.db ] && while IFS=: read -r u id exp p; do echo "User: $u | UUID: $id"; done < $CONFIG_DIR/vmess_users.db
    sleep 3
}

check_vless_users() { 
    [ -f $CONFIG_DIR/vless_users.db ] && cat $CONFIG_DIR/vless_users.db | column -t -s: || echo "No users"
    sleep 3
}
show_vless_links() { 
    [ -f $CONFIG_DIR/vless_users.db ] && while IFS=: read -r u id exp p; do echo "User: $u | UUID: $id"; done < $CONFIG_DIR/vless_users.db
    sleep 3
}

check_trojan_users() { 
    [ -f $CONFIG_DIR/trojan_users.db ] && cat $CONFIG_DIR/trojan_users.db | column -t -s: || echo "No users"
    sleep 3
}
show_trojan_links() { 
    [ -f $CONFIG_DIR/trojan_users.db ] && while IFS=: read -r u pass exp p; do echo "User: $u | Pass: $pass"; done < $CONFIG_DIR/trojan_users.db
    sleep 3
}

install_socks() {
    apt-get install -y dante-server
    echo -e "${GREEN}✓ SOCKS5 installed${NC}"
    sleep 2
}

show_socks_status() { 
    systemctl status danted --no-pager 2>/dev/null || echo "Not installed"
    sleep 3
}

backup_restore() {
    show_banner
    echo -e "${CYAN}  [1]${NC} Backup"
    echo -e "${CYAN}  [2]${NC} Restore"
    echo -e "${CYAN}  [0]${NC} Back"
    read -p "Choice: " choice
    case $choice in
        1)
            bf="/root/nextgen-backup-$(date +%Y%m%d-%H%M%S).tar.gz"
            tar -czf "$bf" $SCRIPT_DIR /etc/squid 2>/dev/null
            echo -e "${GREEN}✓ Backup: $bf${NC}"
            ;;
        2)
            read -p "Backup file: " bf
            [ -f "$bf" ] && tar -xzf "$bf" -C / && echo -e "${GREEN}✓ Restored${NC}" || echo -e "${RED}✗ Not found${NC}"
            ;;
    esac
    sleep 2
}

# Check root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Please run as root (sudo)${NC}"
    exit 1
fi

# Start
main_menu
