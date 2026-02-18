#!/bin/bash

# ═══════════════════════════════════════════════════════════════════
# NeXTGen Script v3.0 - Professional Edition
# Fixed: VMESS, VLESS, SlowDNS Integration
# ═══════════════════════════════════════════════════════════════════

# ─── Strict Mode ───
set -euo pipefail
IFS=$'\n\t'

# ─── Colors ───
declare -r RED='\033[0;31m'
declare -r GREEN='\033[0;32m'
declare -r YELLOW='\033[1;33m'
declare -r BLUE='\033[0;34m'
declare -r MAGENTA='\033[0;35m'
declare -r CYAN='\033[0;36m'
declare -r WHITE='\033[1;37m'
declare -r NC='\033[0m'
declare -r BOLD='\033[1m'

# ─── Paths ───
declare -r SCRIPT_DIR="/etc/nextgen"
declare -r CONFIG_DIR="$SCRIPT_DIR/config"
declare -r LOG_DIR="$SCRIPT_DIR/logs"
declare -r SLOWDNS_DIR="$SCRIPT_DIR/slowdns"
declare -r XRAY_DIR="/usr/local/etc/xray"
declare -r XRAY_CONFIG="$XRAY_DIR/config.json"

# ─── Logging ───
exec 1> >(tee -a "$LOG_DIR/nextgen.log") 2>&1

# ═══════════════════════════════════════════════════════════════════
# UTILITY FUNCTIONS
# ═══════════════════════════════════════════════════════════════════

log() { echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_DIR/nextgen.log"; }
error() { echo -e "${RED}[ERROR]${NC} $1" >&2; log "ERROR: $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; log "SUCCESS: $1"; }
info() { echo -e "${CYAN}[INFO]${NC} $1"; log "INFO: $1"; }

check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root"
        exit 1
    fi
}

init_directories() {
    mkdir -p "$SCRIPT_DIR" "$CONFIG_DIR" "$LOG_DIR" "$SLOWDNS_DIR" "$XRAY_DIR"
    touch "$CONFIG_DIR/ssh_users.db" "$CONFIG_DIR/vmess_users.db" \
          "$CONFIG_DIR/vless_users.db" "$CONFIG_DIR/trojan_users.db"
}

get_public_ip() {
    curl -s --max-time 5 ifconfig.me 2>/dev/null || \
    curl -s --max-time 5 icanhazip.com 2>/dev/null || \
    curl -s --max-time 5 ipinfo.io/ip 2>/dev/null || \
    hostname -I | awk '{print $1}'
}

get_domain() {
    local domain
    domain=$(hostname -f 2>/dev/null)
    [[ "$domain" == "localhost" || -z "$domain" ]] && domain=$(get_public_ip)
    echo "$domain"
}

generate_uuid() {
    if command -v uuidgen &>/dev/null; then
        uuidgen
    elif [[ -f /proc/sys/kernel/random/uuid ]]; then
        cat /proc/sys/kernel/random/uuid
    else
        openssl rand -hex 16 | sed 's/\(..\{8\}\)\(..\{4\}\)\(..\{4\}\)\(..\{4\}\)\(..\{12\}\)/\1-\2-\3-\4-\5/'
    fi
}

encode_base64() {
    echo -n "$1" | base64 -w 0 2>/dev/null || echo -n "$1" | base64
}

# ═══════════════════════════════════════════════════════════════════
# XRAY CORE MANAGEMENT (CRITICAL FIX)
# ═══════════════════════════════════════════════════════════════════

install_xray() {
    info "Installing Xray Core..."
    
    # Official Xray install
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
    
    systemctl enable xray
    
    # Create initial config
    create_xray_config
    
    success "Xray Core installed successfully"
}

create_xray_config() {
    cat > "$XRAY_CONFIG" << 'XRAYEOF'
{
  "log": {
    "access": "/var/log/xray/access.log",
    "error": "/var/log/xray/error.log",
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "port": 443,
      "protocol": "vmess",
      "settings": {
        "clients": []
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "/vmess"
        },
        "security": "tls",
        "tlsSettings": {
          "certificates": [
            {
              "certificateFile": "/etc/nextgen/cert.pem",
              "keyFile": "/etc/nextgen/key.pem"
            }
          ]
        }
      }
    },
    {
      "port": 443,
      "protocol": "vless",
      "settings": {
        "clients": [],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "/vless"
        },
        "security": "tls",
        "tlsSettings": {
          "certificates": [
            {
              "certificateFile": "/etc/nextgen/cert.pem",
              "keyFile": "/etc/nextgen/key.pem"
            }
          ]
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls"]
      }
    },
    {
      "port": 443,
      "protocol": "trojan",
      "settings": {
        "clients": []
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "/trojan"
        },
        "security": "tls",
        "tlsSettings": {
          "certificates": [
            {
              "certificateFile": "/etc/nextgen/cert.pem",
              "keyFile": "/etc/nextgen/key.pem"
            }
          ]
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {}
    },
    {
      "protocol": "blackhole",
      "settings": {},
      "tag": "blocked"
    }
  ],
  "routing": {
    "rules": [
      {
        "type": "field",
        "ip": ["geoip:private"],
        "outboundTag": "blocked"
      }
    ]
  }
}
XRAYEOF

    mkdir -p /var/log/xray
    touch /var/log/xray/access.log /var/log/xray/error.log
    
    # Generate self-signed cert if not exists
    if [[ ! -f /etc/nextgen/cert.pem ]]; then
        openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
            -keyout /etc/nextgen/key.pem \
            -out /etc/nextgen/cert.pem \
            -subj "/CN=$(get_domain)" 2>/dev/null
    fi
    
    systemctl restart xray
}

update_xray_config() {
    local protocol=$1
    local username=$2
    local id=$3
    
    local temp_config=$(mktemp)
    
    case $protocol in
        vmess)
            jq --arg user "$username" --arg uuid "$id" \
               '.inbounds[] | select(.protocol=="vmess") | .settings.clients += [{"id": $uuid, "alterId": 0, "email": $user}]' \
               "$XRAY_CONFIG" > "$temp_config"
            ;;
        vless)
            jq --arg user "$username" --arg uuid "$id" \
               '.inbounds[] | select(.protocol=="vless") | .settings.clients += [{"id": $uuid, "email": $user}]' \
               "$XRAY_CONFIG" > "$temp_config"
            ;;
        trojan)
            jq --arg user "$username" --arg pass "$id" \
               '.inbounds[] | select(.protocol=="trojan") | .settings.clients += [{"password": $pass, "email": $user}]' \
               "$XRAY_CONFIG" > "$temp_config"
            ;;
    esac
    
    mv "$temp_config" "$XRAY_CONFIG"
    systemctl restart xray
}

# ═══════════════════════════════════════════════════════════════════
# SLOWDNS PROPER IMPLEMENTATION (CRITICAL FIX)
# ═══════════════════════════════════════════════════════════════════

install_slowdns_core() {
    info "Installing SlowDNS Core..."
    
    apt-get update -qq
    apt-get install -y -qq git make gcc dnsutils net-tools
    
    cd /tmp
    rm -rf slowdns 2>/dev/null || true
    git clone https://github.com/slackjeff/slowdns.git 2>/dev/null || {
        error "Failed to clone SlowDNS repository"
        return 1
    }
    
    cd slowdns
    make
    
    cp dns-server "$SLOWDNS_DIR/"
    chmod +x "$SLOWDNS_DIR/dns-server"
    
    # Generate keys
    cd "$SLOWDNS_DIR"
    ./dns-server -gen-key -privkey-file server.key -pubkey-file server.pub
    
    success "SlowDNS Core installed"
    info "Public Key: $(cat server.pub)"
}

install_slowdns_binary() {
    info "Downloading pre-compiled SlowDNS..."
    
    cd "$SLOWDNS_DIR"
    
    # Try multiple sources
    local urls=(
        "https://github.com/slackjeff/slowdns/releases/latest/download/dns-server-linux-amd64"
        "https://raw.githubusercontent.com/slackjeff/slowdns/main/dns-server"
    )
    
    for url in "${urls[@]}"; do
        if wget -q -O dns-server "$url" 2>/dev/null || curl -sL -o dns-server "$url" 2>/dev/null; then
            chmod +x dns-server
            ./dns-server -gen-key -privkey-file server.key -pubkey-file server.pub 2>/dev/null && {
                success "SlowDNS installed via binary"
                return 0
            }
        fi
    done
    
    # Fallback to compile
    install_slowdns_core
}

ensure_slowdns() {
    [[ -f "$SLOWDNS_DIR/dns-server" ]] || install_slowdns_binary
    [[ -f "$SLOWDNS_DIR/server.key" ]] || {
        cd "$SLOWDNS_DIR"
        ./dns-server -gen-key -privkey-file server.key -pubkey-file server.pub
    }
}

create_slowdns_service() {
    local proto=$1
    local ns_domain=$2
    local listen_port=$3
    local target_port=$4
    
    local service_name="slowdns-${proto}"
    
    cat > "/etc/systemd/system/${service_name}.service" << EOF
[Unit]
Description=SlowDNS ${proto^^} Tunnel
Documentation=https://github.com/slackjeff/slowdns
After=network.target network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=$SLOWDNS_DIR
ExecStart=$SLOWDNS_DIR/dns-server -udp :${listen_port} -privkey-file $SLOWDNS_DIR/server.key ${ns_domain} 127.0.0.1:${target_port}
Restart=on-failure
RestartSec=5
StandardOutput=append:$LOG_DIR/slowdns-${proto}.log
StandardError=append:$LOG_DIR/slowdns-${proto}.error.log

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable "$service_name"
}

# ═══════════════════════════════════════════════════════════════════
# UI FUNCTIONS
# ═══════════════════════════════════════════════════════════════════

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
    echo -e "${MAGENTA}${BOLD}              P R O F E S S I O N A L  E D I T I O N${NC}"
    echo -e "${YELLOW}═══════════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}              Ultimate VPS & Tunneling Manager v3.0${NC}"
    echo -e "${CYAN}                    Fixed: VMESS | VLESS | SlowDNS${NC}"
    echo -e "${YELLOW}═══════════════════════════════════════════════════════════════════${NC}"
    echo ""
}

main_menu() {
    while true; do
        show_banner
        echo -e "${WHITE}${BOLD}                         MAIN MENU${NC}"
        echo -e "${YELLOW}───────────────────────────────────────────────────────────────────${NC}"
        echo ""
        echo -e "${CYAN}  [01]${NC} ${GREEN}• SSH/WS MANAGER${NC}       ${CYAN}[05]${NC} ${GREEN}• SOCKS5 PROXY${NC}"
        echo -e "${CYAN}  [02]${NC} ${GREEN}• VMESS MANAGER${NC}        ${CYAN}[06]${NC} ${GREEN}• SQUID PROXY${NC}"
        echo -e "${CYAN}  [03]${NC} ${GREEN}• VLESS MANAGER${NC}        ${CYAN}[07]${NC} ${MAGENTA}• SLOWDNS MANAGER${NC}"
        echo -e "${CYAN}  [04]${NC} ${GREEN}• TROJAN MANAGER${NC}       ${CYAN}      ${NC} ${MAGENTA}• (Fixed & Working)${NC}"
        echo ""
        echo -e "${CYAN}  [08]${NC} ${YELLOW}• SYSTEM STATUS${NC}        ${CYAN}[10]${NC} ${YELLOW}• BACKUP/RESTORE${NC}"
        echo -e "${CYAN}  [09]${NC} ${YELLOW}• OPTIMIZE SYSTEM${NC}      ${CYAN}[00]${NC} ${RED}• EXIT${NC}"
        echo ""
        echo -e "${YELLOW}───────────────────────────────────────────────────────────────────${NC}"
        read -rp "$(echo -e "${WHITE}${BOLD}Select an option [00-10]: ${NC}")" choice

        case $choice in
            01|1) ssh_menu ;;
            02|2) vmess_menu ;;
            03|3) vless_menu ;;
            04|4) trojan_menu ;;
            05|5) socks_menu ;;
            06|6) squid_menu ;;
            07|7) slowdns_menu ;;
            08|8) system_status ;;
            09|9) optimize_system ;;
            10) backup_restore ;;
            00|0) clear; exit 0 ;;
            *) error "Invalid option!"; sleep 1 ;;
        esac
    done
}

# ═══════════════════════════════════════════════════════════════════
# PROTOCOL MENUS
# ═══════════════════════════════════════════════════════════════════

vmess_menu() {
    while true; do
        show_banner
        echo -e "${WHITE}${BOLD}                      VMESS MANAGER${NC}"
        echo -e "${YELLOW}───────────────────────────────────────────────────────────────────${NC}"
        echo ""
        echo -e "${CYAN}  [01]${NC} ${GREEN}• Create VMESS Account${NC}"
        echo -e "${CYAN}  [02]${NC} ${GREEN}• Delete VMESS Account${NC}"
        echo -e "${CYAN}  [03]${NC} ${GREEN}• Renew VMESS Account${NC}"
        echo -e "${CYAN}  [04]${NC} ${GREEN}• List All Accounts${NC}"
        echo -e "${CYAN}  [05]${NC} ${GREEN}• Show VMESS Links${NC}"
        echo -e "${CYAN}  [06]${NC} ${MAGENTA}• Enable SlowDNS + VMESS${NC}"
        echo -e "${CYAN}  [07]${NC} ${MAGENTA}• Disable SlowDNS + VMESS${NC}"
        echo -e "${CYAN}  [08]${NC} ${YELLOW}• Check Xray Status${NC}"
        echo -e "${CYAN}  [00]${NC} ${RED}• Back to Main Menu${NC}"
        echo ""
        read -rp "$(echo -e "${WHITE}${BOLD}Select option [00-08]: ${NC}")" choice

        case $choice in
            01|1) create_vmess_account ;;
            02|2) delete_vmess_account ;;
            03|3) renew_vmess_account ;;
            04|4) list_vmess_accounts ;;
            05|5) show_vmess_links ;;
            06|6) enable_slowdns "vmess" 443 ;;
            07|7) disable_slowdns "vmess" ;;
            08|8) check_xray_status ;;
            00|0) break ;;
            *) error "Invalid option!"; sleep 1 ;;
        esac
    done
}

vless_menu() {
    while true; do
        show_banner
        echo -e "${WHITE}${BOLD}                      VLESS MANAGER${NC}"
        echo -e "${YELLOW}───────────────────────────────────────────────────────────────────${NC}"
        echo ""
        echo -e "${CYAN}  [01]${NC} ${GREEN}• Create VLESS Account${NC}"
        echo -e "${CYAN}  [02]${NC} ${GREEN}• Delete VLESS Account${NC}"
        echo -e "${CYAN}  [03]${NC} ${GREEN}• Renew VLESS Account${NC}"
        echo -e "${CYAN}  [04]${NC} ${GREEN}• List All Accounts${NC}"
        echo -e "${CYAN}  [05]${NC} ${GREEN}• Show VLESS Links${NC}"
        echo -e "${CYAN}  [06]${NC} ${MAGENTA}• Enable SlowDNS + VLESS${NC}"
        echo -e "${CYAN}  [07]${NC} ${MAGENTA}• Disable SlowDNS + VLESS${NC}"
        echo -e "${CYAN}  [08]${NC} ${YELLOW}• Check Xray Status${NC}"
        echo -e "${CYAN}  [00]${NC} ${RED}• Back to Main Menu${NC}"
        echo ""
        read -rp "$(echo -e "${WHITE}${BOLD}Select option [00-08]: ${NC}")" choice

        case $choice in
            01|1) create_vless_account ;;
            02|2) delete_vless_account ;;
            03|3) renew_vless_account ;;
            04|4) list_vless_accounts ;;
            05|5) show_vless_links ;;
            06|6) enable_slowdns "vless" 443 ;;
            07|7) disable_slowdns "vless" ;;
            08|8) check_xray_status ;;
            00|0) break ;;
            *) error "Invalid option!"; sleep 1 ;;
        esac
    done
}

slowdns_menu() {
    while true; do
        show_banner
        echo -e "${WHITE}${BOLD}                     SLOWDNS MANAGER${NC}"
        echo -e "${YELLOW}───────────────────────────────────────────────────────────────────${NC}"
        echo ""
        echo -e "${CYAN}  [01]${NC} ${GREEN}• Install SlowDNS Core${NC}"
        echo -e "${CYAN}  [02]${NC} ${GREEN}• Show Public Key${NC}"
        echo -e "${CYAN}  [03]${NC} ${GREEN}• Show SlowDNS Status${NC}"
        echo -e "${CYAN}  [04]${NC} ${MAGENTA}• Enable SlowDNS + SSH${NC}"
        echo -e "${CYAN}  [05]${NC} ${MAGENTA}• Disable SlowDNS + SSH${NC}"
        echo -e "${CYAN}  [06]${NC} ${YELLOW}• Restart All SlowDNS${NC}"
        echo -e "${CYAN}  [07]${NC} ${YELLOW}• View SlowDNS Logs${NC}"
        echo -e "${CYAN}  [00]${NC} ${RED}• Back to Main Menu${NC}"
        echo ""
        read -rp "$(echo -e "${WHITE}${BOLD}Select option [00-07]: ${NC}")" choice

        case $choice in
            01|1) install_slowdns_binary ;;
            02|2) show_slowdns_pubkey ;;
            03|3) show_slowdns_status ;;
            04|4) enable_slowdns "ssh" 22 ;;
            05|5) disable_slowdns "ssh" ;;
            06|6) restart_all_slowdns ;;
            07|7) view_slowdns_logs ;;
            00|0) break ;;
            *) error "Invalid option!"; sleep 1 ;;
        esac
    done
}

# ═══════════════════════════════════════════════════════════════════
# ACCOUNT MANAGEMENT (FIXED VERSIONS)
# ═══════════════════════════════════════════════════════════════════

create_vmess_account() {
    show_banner
    echo -e "${WHITE}${BOLD}                   CREATE VMESS ACCOUNT${NC}"
    echo -e "${YELLOW}───────────────────────────────────────────────────────────────────${NC}"
    echo ""
    
    # Ensure Xray is installed
    if ! command -v xray &>/dev/null; then
        info "Xray not found. Installing..."
        install_xray
    fi
    
    read -rp "$(echo -e "${CYAN}Username: ${NC}")" username
    [[ -z "$username" ]] && { error "Username cannot be empty"; sleep 2; return; }
    
    read -rp "$(echo -e "${CYAN}Expiry Days: ${NC}")" days
    [[ ! "$days" =~ ^[0-9]+$ ]] && days=30
    
    local uuid
    uuid=$(generate_uuid)
    local expiry
    expiry=$(date -d "+$days days" +"%Y-%m-%d")
    local domain
    domain=$(get_domain)
    
    # Save to database
    echo "${username}:${uuid}:${expiry}:VMESS:$(date +%s)" >> "$CONFIG_DIR/vmess_users.db"
    
    # Update Xray config
    update_xray_config "vmess" "$username" "$uuid"
    
    # Generate VMESS Link
    local vmess_json
    vmess_json=$(cat << EOF
{
  "v": "2",
  "ps": "${username}",
  "add": "${domain}",
  "port": "443",
  "id": "${uuid}",
  "aid": "0",
  "scy": "auto",
  "net": "ws",
  "type": "none",
  "host": "${domain}",
  "path": "/vmess",
  "tls": "tls",
  "sni": "${domain}"
}
EOF
)
    
    local vmess_link
    vmess_link=$(encode_base64 "$vmess_json")
    
    # Display results
    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║          ✓ VMESS ACCOUNT CREATED SUCCESSFULLY                  ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${CYAN}Username:${NC}    $username"
    echo -e "${CYAN}UUID:${NC}        $uuid"
    echo -e "${CYAN}Domain:${NC}      $domain"
    echo -e "${CYAN}Port:${NC}        443"
    echo -e "${CYAN}Path:${NC}        /vmess"
    echo -e "${CYAN}Security:${NC}    TLS"
    echo -e "${CYAN}Network:${NC}     WebSocket"
    echo -e "${CYAN}Expiry:${NC}      $expiry"
    echo ""
    echo -e "${YELLOW}VMESS Link:${NC}"
    echo -e "${GREEN}vmess://${vmess_link}${NC}"
    echo ""
    echo -e "${CYAN}QR Code:${NC}"
    echo "vmess://${vmess_link}" | qrencode -t ANSIUTF8 2>/dev/null || echo "Install qrencode for QR code"
    echo ""
    read -rp "Press Enter to continue..."
}

create_vless_account() {
    show_banner
    echo -e "${WHITE}${BOLD}                   CREATE VLESS ACCOUNT${NC}"
    echo -e "${YELLOW}───────────────────────────────────────────────────────────────────${NC}"
    echo ""
    
    if ! command -v xray &>/dev/null; then
        info "Xray not found. Installing..."
        install_xray
    fi
    
    read -rp "$(echo -e "${CYAN}Username: ${NC}")" username
    [[ -z "$username" ]] && { error "Username cannot be empty"; sleep 2; return; }
    
    read -rp "$(echo -e "${CYAN}Expiry Days: ${NC}")" days
    [[ ! "$days" =~ ^[0-9]+$ ]] && days=30
    
    local uuid
    uuid=$(generate_uuid)
    local expiry
    expiry=$(date -d "+$days days" +"%Y-%m-%d")
    local domain
    domain=$(get_domain)
    
    echo "${username}:${uuid}:${expiry}:VLESS:$(date +%s)" >> "$CONFIG_DIR/vless_users.db"
    update_xray_config "vless" "$username" "$uuid"
    
    # VLESS Links
    local vless_ws="vless://${uuid}@${domain}:443?security=tls&encryption=none&host=${domain}&type=ws&path=%2Fvless&sni=${domain}#${username}"
    local vless_tcp="vless://${uuid}@${domain}:443?security=tls&encryption=none&headerType=none&type=tcp&sni=${domain}#${username}-TCP"
    
    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║          ✓ VLESS ACCOUNT CREATED SUCCESSFULLY                  ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${CYAN}Username:${NC}    $username"
    echo -e "${CYAN}UUID:${NC}        $uuid"
    echo -e "${CYAN}Domain:${NC}      $domain"
    echo -e "${CYAN}Port:${NC}        443"
    echo -e "${CYAN}Path:${NC}        /vless"
    echo -e "${CYAN}Security:${NC}    TLS/XTLS"
    echo -e "${CYAN}Network:${NC}     WebSocket"
    echo -e "${CYAN}Expiry:${NC}      $expiry"
    echo ""
    echo -e "${YELLOW}VLESS WS Link:${NC}"
    echo -e "${GREEN}${vless_ws}${NC}"
    echo ""
    echo -e "${YELLOW}VLESS TCP Link:${NC}"
    echo -e "${GREEN}${vless_tcp}${NC}"
    echo ""
    read -rp "Press Enter to continue..."
}

# ═══════════════════════════════════════════════════════════════════
# SLOWDNS FUNCTIONS (FIXED)
# ═══════════════════════════════════════════════════════════════════

enable_slowdns() {
    local proto=$1
    local default_target_port=${2:-443}
    
    show_banner
    echo -e "${WHITE}${BOLD}              ENABLE SLOWDNS + ${proto^^}${NC}"
    echo -e "${YELLOW}───────────────────────────────────────────────────────────────────${NC}"
    echo ""
    
    ensure_slowdns
    
    read -rp "$(echo -e "${CYAN}NS Domain (e.g., ns.yourdomain.com): ${NC}")" ns_domain
    [[ -z "$ns_domain" ]] && { error "NS Domain is required"; sleep 2; return; }
    
    read -rp "$(echo -e "${CYAN}SlowDNS Listen Port [5300]: ${NC}")" listen_port
    listen_port=${listen_port:-5300}
    
    local target_port=$default_target_port
    if [[ "$proto" != "ssh" ]]; then
        read -rp "$(echo -e "${CYAN}Target Port [${default_target_port}]: ${NC}")" input_port
        target_port=${input_port:-$default_target_port}
    fi
    
    # Save config
    echo "NS_DOMAIN=${ns_domain}" > "$CONFIG_DIR/slowdns-${proto}.conf"
    echo "LISTEN_PORT=${listen_port}" >> "$CONFIG_DIR/slowdns-${proto}.conf"
    echo "TARGET_PORT=${target_port}" >> "$CONFIG_DIR/slowdns-${proto}.conf"
    
    # Create service
    create_slowdns_service "$proto" "$ns_domain" "$listen_port" "$target_port"
    
    # Start service
    systemctl restart "slowdns-${proto}"
    sleep 2
    
    # Verify
    if systemctl is-active --quiet "slowdns-${proto}"; then
        success "SlowDNS + ${proto^^} is now running!"
        echo ""
        echo -e "${CYAN}Configuration:${NC}"
        echo -e "  NS Domain:    ${GREEN}${ns_domain}${NC}"
        echo -e "  Listen Port:  ${GREEN}${listen_port}${NC}"
        echo -e "  Target:       ${GREEN}127.0.0.1:${target_port}${NC}"
        echo -e "  Public Key:   ${GREEN}$(cat $SLOWDNS_DIR/server.pub)${NC}"
    else
        error "Failed to start SlowDNS service"
        systemctl status "slowdns-${proto}" --no-pager
    fi
    
    echo ""
    read -rp "Press Enter to continue..."
}

disable_slowdns() {
    local proto=$1
    local service_name="slowdns-${proto}"
    
    if systemctl is-active --quiet "$service_name" 2>/dev/null; then
        systemctl stop "$service_name"
        systemctl disable "$service_name" 2>/dev/null || true
        success "SlowDNS ${proto^^} stopped"
    else
        info "SlowDNS ${proto^^} is not running"
    fi
    
    sleep 2
}

show_slowdns_pubkey() {
    show_banner
    echo -e "${WHITE}${BOLD}                    SLOWDNS PUBLIC KEY${NC}"
    echo -e "${YELLOW}───────────────────────────────────────────────────────────────────${NC}"
    echo ""
    
    if [[ -f "$SLOWDNS_DIR/server.pub" ]]; then
        local pubkey
        pubkey=$(cat "$SLOWDNS_DIR/server.pub")
        echo -e "${GREEN}Public Key:${NC}"
        echo -e "${CYAN}${BOLD}${pubkey}${NC}"
        echo ""
        echo -e "${YELLOW}Use this key in your SlowDNS client configuration${NC}"
    else
        error "No keys found. Install SlowDNS first."
    fi
    
    echo ""
    read -rp "Press Enter to continue..."
}

show_slowdns_status() {
    show_banner
    echo -e "${WHITE}${BOLD}                    SLOWDNS STATUS${NC}"
    echo -e "${YELLOW}───────────────────────────────────────────────────────────────────${NC}"
    echo ""
    
    local services=("slowdns-ssh" "slowdns-vmess" "slowdns-vless" "slowdns-trojan")
    local any_running=false
    
    for svc in "${services[@]}"; do
        if systemctl is-active --quiet "$svc" 2>/dev/null; then
            local status_info
            status_info=$(systemctl show "$svc" --property=ExecStart --value)
            echo -e "${GREEN}●${NC} ${BOLD}$svc${NC}: ${GREEN}Running${NC}"
            echo -e "   ${CYAN}Config:${NC} $status_info"
            any_running=true
        else
            echo -e "${RED}●${NC} ${BOLD}$svc${NC}: ${RED}Stopped${NC}"
        fi
    done
    
    if [[ "$any_running" == false ]]; then
        echo ""
        echo -e "${YELLOW}No SlowDNS services are currently running.${NC}"
        echo -e "Use 'Enable SlowDNS' options to start tunneling."
    fi
    
    echo ""
    read -rp "Press Enter to continue..."
}

restart_all_slowdns() {
    info "Restarting all SlowDNS services..."
    for svc in slowdns-ssh slowdns-vmess slowdns-vless slowdns-trojan; do
        if systemctl is-enabled "$svc" &>/dev/null; then
            systemctl restart "$svc" 2>/dev/null && success "$svc restarted" || true
        fi
    done
    sleep 2
}

view_slowdns_logs() {
    show_banner
    echo -e "${WHITE}${BOLD}                    SLOWDNS LOGS${NC}"
    echo -e "${YELLOW}───────────────────────────────────────────────────────────────────${NC}"
    echo ""
    
    local log_file="$LOG_DIR/slowdns-ssh.log"
    if [[ -f "$log_file" ]]; then
        tail -n 20 "$log_file"
    else
        echo "No logs found"
    fi
    
    echo ""
    read -rp "Press Enter to continue..."
}

# ═══════════════════════════════════════════════════════════════════
# ADDITIONAL FUNCTIONS (SSH, TROJAN, SOCKS, SQUID, SYSTEM)
# ═══════════════════════════════════════════════════════════════════

ssh_menu() {
    while true; do
        show_banner
        echo -e "${WHITE}${BOLD}                      SSH/WEBSOCKET MANAGER${NC}"
        echo -e "${YELLOW}───────────────────────────────────────────────────────────────────${NC}"
        echo ""
        echo -e "${CYAN}  [01]${NC} ${GREEN}• Create SSH Account${NC}"
        echo -e "${CYAN}  [02]${NC} ${GREEN}• Delete SSH Account${NC}"
        echo -e "${CYAN}  [03]${NC} ${GREEN}• Renew SSH Account${NC}"
        echo -e "${CYAN}  [04]${NC} ${GREEN}• List SSH Users${NC}"
        echo -e "${CYAN}  [05]${NC} ${MAGENTA}• Enable SlowDNS + SSH${NC}"
        echo -e "${CYAN}  [06]${NC} ${MAGENTA}• Disable SlowDNS + SSH${NC}"
        echo -e "${CYAN}  [07]${NC} ${YELLOW}• Change SSH Port${NC}"
        echo -e "${CYAN}  [08]${NC} ${YELLOW}• Install WebSocket${NC}"
        echo -e "${CYAN}  [00]${NC} ${RED}• Back to Main Menu${NC}"
        echo ""
        read -rp "$(echo -e "${WHITE}${BOLD}Select option [00-08]: ${NC}")" choice

        case $choice in
            01|1) create_ssh_account ;;
            02|2) delete_ssh_account ;;
            03|3) renew_ssh_account ;;
            04|4) list_ssh_accounts ;;
            05|5) enable_slowdns "ssh" 22 ;;
            06|6) disable_slowdns "ssh" ;;
            07|7) change_ssh_port ;;
            08|8) install_websocket ;;
            00|0) break ;;
            *) error "Invalid option!"; sleep 1 ;;
        esac
    done
}

create_ssh_account() {
    show_banner
    echo -e "${WHITE}${BOLD}                    CREATE SSH ACCOUNT${NC}"
    echo -e "${YELLOW}───────────────────────────────────────────────────────────────────${NC}"
    echo ""
    
    read -rp "$(echo -e "${CYAN}Username: ${NC}")" username
    [[ -z "$username" ]] && { error "Username required"; sleep 2; return; }
    
    read -rs -p "$(echo -e "${CYAN}Password: ${NC}")" password
    echo ""
    [[ -z "$password" ]] && { error "Password required"; sleep 2; return; }
    
    read -rp "$(echo -e "${CYAN}Expiry Days [30]: ${NC}")" days
    days=${days:-30}
    
    # Create user
    if id "$username" &>/dev/null; then
        error "User already exists"
        sleep 2
        return
    fi
    
    useradd -m -s /bin/false "$username" 2>/dev/null
    echo "${username}:${password}" | chpasswd
    
    local expiry
    expiry=$(date -d "+${days} days" +"%Y-%m-%d")
    chage -E "$expiry" "$username"
    
    # Save to DB
    echo "${username}:${password}:${expiry}:SSH:$(date +%s)" >> "$CONFIG_DIR/ssh_users.db"
    
    local ip
    ip=$(get_public_ip)
    
    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║          ✓ SSH ACCOUNT CREATED SUCCESSFULLY                    ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${CYAN}Username:${NC}  $username"
    echo -e "${CYAN}Password:${NC}  $password"
    echo -e "${CYAN}Host:${NC}      $ip"
    echo -e "${CYAN}Port:${NC}      22 / 443 (WS)"
    echo -e "${CYAN}Expiry:${NC}    $expiry"
    echo ""
    read -rp "Press Enter to continue..."
}

delete_ssh_account() {
    read -rp "Username to delete: " username
    if userdel -r "$username" 2>/dev/null; then
        sed -i "/^${username}:/d" "$CONFIG_DIR/ssh_users.db"
        success "User $username deleted"
    else
        error "User not found"
    fi
    sleep 2
}

renew_ssh_account() {
    read -rp "Username: " username
    read -rp "Additional days: " days
    
    if chage -E "$(date -d "+${days} days" +"%Y-%m-%d")" "$username" 2>/dev/null; then
        success "Account renewed"
    else
        error "Failed to renew"
    fi
    sleep 2
}

list_ssh_accounts() {
    show_banner
    echo -e "${WHITE}${BOLD}                    SSH ACCOUNTS${NC}"
    echo -e "${YELLOW}───────────────────────────────────────────────────────────────────${NC}"
    echo ""
    printf "%-15s %-15s %-12s %s\n" "USERNAME" "PASSWORD" "EXPIRY" "STATUS"
    echo -e "${CYAN}─────────────────────────────────────────────────────────────────${NC}"
    
    while IFS=: read -r user pass exp proto created; do
        [[ -z "$user" ]] && continue
        local status="ACTIVE"
        [[ "$(date -d "$exp" +%s)" -lt "$(date +%s)" ]] && status="${RED}EXPIRED${NC}"
        printf "%-15s %-15s %-12s %b\n" "$user" "$pass" "$exp" "$status"
    done < "$CONFIG_DIR/ssh_users.db"
    
    echo ""
    read -rp "Press Enter to continue..."
}

change_ssh_port() {
    read -rp "New SSH port: " port
    sed -i "s/^#*Port .*/Port $port/" /etc/ssh/sshd_config
    systemctl restart sshd
    success "SSH port changed to $port"
    sleep 2
}

install_websocket() {
    info "Installing WebSocket (Python)..."
    apt-get install -y python3 python3-pip
    pip3 install websocket-server 2>/dev/null || pip3 install websocket
    
    cat > /usr/local/bin/ws-ssh << 'PYEOF'
#!/usr/bin/env python3
import asyncio, websockets, socket, threading, sys

SSH_HOST = "127.0.0.1"
SSH_PORT = 22
WS_PORT = 80

async def handle(websocket, path):
    try:
        ssh_sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        ssh_sock.connect((SSH_HOST, SSH_PORT))
        
        def forward_to_ws():
            while True:
                data = ssh_sock.recv(4096)
                if not data: break
                asyncio.run(websocket.send(data))
        
        t = threading.Thread(target=forward_to_ws)
        t.daemon = True
        t.start()
        
        async for message in websocket:
            ssh_sock.send(message)
    except: pass

start_server = websockets.serve(handle, "0.0.0.0", WS_PORT)
asyncio.get_event_loop().run_until_complete(start_server)
asyncio.get_event_loop().run_forever()
PYEOF
    
    chmod +x /usr/local/bin/ws-ssh
    
    cat > /etc/systemd/system/ws-ssh.service << EOF
[Unit]
Description=WebSocket SSH
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 /usr/local/bin/ws-ssh
Restart=always

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable ws-ssh
    systemctl start ws-ssh
    success "WebSocket installed on port 80"
    sleep 2
}

# ═══════════════════════════════════════════════════════════════════
# TROJAN FUNCTIONS
# ═══════════════════════════════════════════════════════════════════

trojan_menu() {
    while true; do
        show_banner
        echo -e "${WHITE}${BOLD}                      TROJAN MANAGER${NC}"
        echo -e "${YELLOW}───────────────────────────────────────────────────────────────────${NC}"
        echo ""
        echo -e "${CYAN}  [01]${NC} ${GREEN}• Create TROJAN Account${NC}"
        echo -e "${CYAN}  [02]${NC} ${GREEN}• Delete TROJAN Account${NC}"
        echo -e "${CYAN}  [03]${NC} ${GREEN}• List TROJAN Accounts${NC}"
        echo -e "${CYAN}  [04]${NC} ${GREEN}• Show TROJAN Links${NC}"
        echo -e "${CYAN}  [05]${NC} ${MAGENTA}• Enable SlowDNS + TROJAN${NC}"
        echo -e "${CYAN}  [06]${NC} ${MAGENTA}• Disable SlowDNS + TROJAN${NC}"
        echo -e "${CYAN}  [00]${NC} ${RED}• Back to Main Menu${NC}"
        echo ""
        read -rp "$(echo -e "${WHITE}${BOLD}Select option [00-06]: ${NC}")" choice

        case $choice in
            01|1) create_trojan_account ;;
            02|2) delete_trojan_account ;;
            03|3) list_trojan_accounts ;;
            04|4) show_trojan_links ;;
            05|5) enable_slowdns "trojan" 443 ;;
            06|6) disable_slowdns "trojan" ;;
            00|0) break ;;
            *) error "Invalid option!"; sleep 1 ;;
        esac
    done
}

create_trojan_account() {
    show_banner
    echo -e "${WHITE}${BOLD}                  CREATE TROJAN ACCOUNT${NC}"
    echo -e "${YELLOW}───────────────────────────────────────────────────────────────────${NC}"
    echo ""
    
    if ! command -v xray &>/dev/null; then
        info "Installing Xray..."
        install_xray
    fi
    
    read -rp "$(echo -e "${CYAN}Username: ${NC}")" username
    [[ -z "$username" ]] && { error "Username required"; sleep 2; return; }
    
    read -rp "$(echo -e "${CYAN}Password (auto-generate if empty): ${NC}")" password
    [[ -z "$password" ]] && password=$(openssl rand -base64 12)
    
    read -rp "$(echo -e "${CYAN}Expiry Days [30]: ${NC}")" days
    days=${days:-30}
    
    local expiry
    expiry=$(date -d "+${days} days" +"%Y-%m-%d")
    local domain
    domain=$(get_domain)
    
    echo "${username}:${password}:${expiry}:TROJAN:$(date +%s)" >> "$CONFIG_DIR/trojan_users.db"
    update_xray_config "trojan" "$username" "$password"
    
    local trojan_link="trojan://${password}@${domain}:443?security=tls&host=${domain}&type=ws&path=%2Ftrojan&sni=${domain}#${username}"
    
    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║          ✓ TROJAN ACCOUNT CREATED SUCCESSFULLY                 ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${CYAN}Username:${NC}  $username"
    echo -e "${CYAN}Password:${NC}  $password"
    echo -e "${CYAN}Host:${NC}      $domain"
    echo -e "${CYAN}Port:${NC}      443"
    echo -e "${CYAN}Path:${NC}      /trojan"
    echo -e "${CYAN}Expiry:${NC}    $expiry"
    echo ""
    echo -e "${YELLOW}Trojan Link:${NC}"
    echo -e "${GREEN}${trojan_link}${NC}"
    echo ""
    read -rp "Press Enter to continue..."
}

delete_trojan_account() {
    read -rp "Username to delete: " username
    sed -i "/^${username}:/d" "$CONFIG_DIR/trojan_users.db"
    success "Account removed from database (restart Xray to apply)"
    sleep 2
}

list_trojan_accounts() {
    show_banner
    echo -e "${WHITE}${BOLD}                    TROJAN ACCOUNTS${NC}"
    echo -e "${YELLOW}───────────────────────────────────────────────────────────────────${NC}"
    echo ""
    printf "%-15s %-20s %-12s\n" "USERNAME" "PASSWORD" "EXPIRY"
    echo -e "${CYAN}─────────────────────────────────────────────────────────────────${NC}"
    
    while IFS=: read -r user pass exp proto created; do
        [[ -z "$user" ]] && continue
        printf "%-15s %-20s %-12s\n" "$user" "$pass" "$exp"
    done < "$CONFIG_DIR/trojan_users.db"
    
    echo ""
    read -rp "Press Enter to continue..."
}

show_trojan_links() {
    show_banner
    echo -e "${WHITE}${BOLD}                    TROJAN LINKS${NC}"
    echo -e "${YELLOW}───────────────────────────────────────────────────────────────────${NC}"
    echo ""
    
    local domain
    domain=$(get_domain)
    
    while IFS=: read -r user pass exp proto created; do
        [[ -z "$user" ]] && continue
        local link="trojan://${pass}@${domain}:443?security=tls&host=${domain}&type=ws&path=%2Ftrojan&sni=${domain}#${user}"
        echo -e "${CYAN}${user}:${NC}"
        echo -e "${GREEN}${link}${NC}"
        echo ""
    done < "$CONFIG_DIR/trojan_users.db"
    
    read -rp "Press Enter to continue..."
}

# ═══════════════════════════════════════════════════════════════════
# SOCKS & SQUID FUNCTIONS
# ═══════════════════════════════════════════════════════════════════

socks_menu() {
    while true; do
        show_banner
        echo -e "${WHITE}${BOLD}                      SOCKS5 MANAGER${NC}"
        echo -e "${YELLOW}───────────────────────────────────────────────────────────────────${NC}"
        echo ""
        echo -e "${CYAN}  [01]${NC} ${GREEN}• Install SOCKS5${NC}"
        echo -e "${CYAN}  [02]${NC} ${GREEN}• Add SOCKS User${NC}"
        echo -e "${CYAN}  [03]${NC} ${GREEN}• Show Status${NC}"
        echo -e "${CYAN}  [00]${NC} ${RED}• Back to Main Menu${NC}"
        echo ""
        read -rp "$(echo -e "${WHITE}${BOLD}Select option [00-03]: ${NC}")" choice

        case $choice in
            01|1) install_socks5 ;;
            02|2) add_socks_user ;;
            03|3) show_socks_status ;;
            00|0) break ;;
            *) error "Invalid option!"; sleep 1 ;;
        esac
    done
}

install_socks5() {
    info "Installing Dante SOCKS5..."
    apt-get update -qq
    apt-get install -y -qq dante-server
    
    cat > /etc/danted.conf << EOF
logoutput: syslog
internal: 0.0.0.0 port = 1080
external: eth0
socksmethod: username
clientmethod: none
user.privileged: root
user.notprivileged: nobody
client pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    log: connect disconnect error
}
socks pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    log: connect disconnect error
}
EOF

    systemctl restart danted
    systemctl enable danted
    success "SOCKS5 installed on port 1080"
    sleep 2
}

add_socks_user() {
    read -rp "Username: " username
    useradd -M -s /sbin/nologin "$username" 2>/dev/null || true
    passwd "$username"
    success "User added"
    sleep 2
}

show_socks_status() {
    systemctl status danted --no-pager 2>/dev/null || echo "Not installed"
    sleep 3
}

squid_menu() {
    while true; do
        show_banner
        echo -e "${WHITE}${BOLD}                      SQUID PROXY MANAGER${NC}"
        echo -e "${YELLOW}───────────────────────────────────────────────────────────────────${NC}"
        echo ""
        echo -e "${CYAN}  [01]${NC} ${GREEN}• Install Squid${NC}"
        echo -e "${CYAN}  [02]${NC} ${GREEN}• Change Port${NC}"
        echo -e "${CYAN}  [03]${NC} ${GREEN}• Add User${NC}"
        echo -e "${CYAN}  [04]${NC} ${GREEN}• Show Status${NC}"
        echo -e "${CYAN}  [00]${NC} ${RED}• Back to Main Menu${NC}"
        echo ""
        read -rp "$(echo -e "${WHITE}${BOLD}Select option [00-04]: ${NC}")" choice

        case $choice in
            01|1) install_squid ;;
            02|2) change_squid_port ;;
            03|3) add_squid_user ;;
            04|4) show_squid_status ;;
            00|0) break ;;
            *) error "Invalid option!"; sleep 1 ;;
        esac
    done
}

install_squid() {
    info "Installing Squid..."
    apt-get update -qq
    apt-get install -y -qq squid apache2-utils
    
    local port=3128
    cat > /etc/squid/squid.conf << EOF
http_port $port
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
    chown proxy:proxy /etc/squid/passwd 2>/dev/null || true
    
    systemctl restart squid
    systemctl enable squid
    ufw allow $port/tcp 2>/dev/null || iptables -I INPUT -p tcp --dport $port -j ACCEPT 2>/dev/null
    
    success "Squid installed on port $port"
    sleep 2
}

change_squid_port() {
    read -rp "New port: " port
    sed -i "s/^http_port .*/http_port $port/" /etc/squid/squid.conf
    systemctl restart squid
    success "Port changed to $port"
    sleep 2
}

add_squid_user() {
    read -rp "Username: " username
    htpasswd /etc/squid/passwd "$username"
    systemctl reload squid
    success "User added"
    sleep 2
}

show_squid_status() {
    systemctl is-active --quiet squid && echo -e "${GREEN}Squid: Running${NC}" || echo -e "${RED}Squid: Stopped${NC}"
    grep "^http_port" /etc/squid/squid.conf 2>/dev/null
    sleep 3
}

# ═══════════════════════════════════════════════════════════════════
# SYSTEM FUNCTIONS
# ═══════════════════════════════════════════════════════════════════

system_status() {
    show_banner
    echo -e "${WHITE}${BOLD}                    SYSTEM STATUS${NC}"
    echo -e "${YELLOW}───────────────────────────────────────────────────────────────────${NC}"
    echo ""
    
    echo -e "${CYAN}Services Status:${NC}"
    local services=("ssh" "squid" "xray" "danted")
    for svc in "${services[@]}"; do
        if systemctl is-active --quiet "$svc" 2>/dev/null; then
            echo -e "  ${GREEN}●${NC} $svc: Running"
        else
            echo -e "  ${RED}●${NC} $svc: Stopped"
        fi
    done
    
    echo ""
    echo -e "${CYAN}SlowDNS Services:${NC}"
    for svc in slowdns-ssh slowdns-vmess slowdns-vless slowdns-trojan; do
        if systemctl is-active --quiet "$svc" 2>/dev/null; then
            echo -e "  ${GREEN}●${NC} $svc: Running"
        else
            echo -e "  ${RED}●${NC} $svc: Stopped"
        fi
    done
    
    echo ""
    echo -e "${CYAN}System Info:${NC}"
    echo -e "  Public IP: $(get_public_ip)"
    echo -e "  Hostname: $(hostname -f 2>/dev/null || hostname)"
    echo -e "  Uptime: $(uptime -p 2>/dev/null || uptime)"
    echo -e "  Memory: $(free -h 2>/dev/null | awk '/^Mem:/ {print $3 "/" $2}')"
    echo -e "  Disk: $(df -h / 2>/dev/null | awk 'NR==2 {print $3 "/" $2 " (" $5 ")"}')"
    
    echo ""
    read -rp "Press Enter to continue..."
}

optimize_system() {
    show_banner
    echo -e "${YELLOW}Optimizing system...${NC}"
    
    cat >> /etc/sysctl.conf << EOF
# NeXTGen Optimizations
net.ipv4.tcp_fast_open = 3
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_keepalive_time = 1200
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.tcp_max_tw_buckets = 5000
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 65535
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.ipv4.ip_local_port_range = 1024 65535
net.ipv4.tcp_rmem = 4096 87380 134217728
net.ipv4.tcp_wmem = 4096 65536 134217728
EOF

    sysctl -p >/dev/null 2>&1
    
    echo "* soft nofile 65535" >> /etc/security/limits.conf
    echo "* hard nofile 65535" >> /etc/security/limits.conf
    
    success "System optimized with BBR"
    sleep 2
}

backup_restore() {
    while true; do
        show_banner
        echo -e "${WHITE}${BOLD}                    BACKUP & RESTORE${NC}"
        echo -e "${YELLOW}───────────────────────────────────────────────────────────────────${NC}"
        echo ""
        echo -e "${CYAN}  [01]${NC} ${GREEN}• Create Backup${NC}"
        echo -e "${CYAN}  [02]${NC} ${GREEN}• Restore Backup${NC}"
        echo -e "${CYAN}  [00]${NC} ${RED}• Back${NC}"
        echo ""
        read -rp "$(echo -e "${WHITE}${BOLD}Select option [00-02]: ${NC}")" choice

        case $choice in
            01|1)
                local backup_file="/root/nextgen-backup-$(date +%Y%m%d-%H%M%S).tar.gz"
                tar -czf "$backup_file" "$SCRIPT_DIR" /etc/squid /usr/local/etc/xray 2>/dev/null
                success "Backup created: $backup_file"
                sleep 2
                ;;
            02|2)
                read -rp "Backup file path: " backup_file
                if [[ -f "$backup_file" ]]; then
                    tar -xzf "$backup_file" -C /
                    success "Restored successfully"
                else
                    error "File not found"
                fi
                sleep 2
                ;;
            00|0) break ;;
            *) error "Invalid option!"; sleep 1 ;;
        esac
    done
}

check_xray_status() {
    if systemctl is-active --quiet xray; then
        success "Xray is running"
        echo ""
        systemctl status xray --no-pager -l
    else
        error "Xray is not running"
        systemctl status xray --no-pager -l || true
    fi
    sleep 3
}

# ═══════════════════════════════════════════════════════════════════
# VMESS/VLESS MANAGEMENT FUNCTIONS
# ═══════════════════════════════════════════════════════════════════

delete_vmess_account() {
    read -rp "Username to delete: " username
    if sed -i "/^${username}:/d" "$CONFIG_DIR/vmess_users.db"; then
        success "VMESS account removed (restart Xray to fully apply)"
    else
        error "Account not found"
    fi
    sleep 2
}

renew_vmess_account() {
    read -rp "Username: " username
    read -rp "Additional days: " days
    
    local temp_file=$(mktemp)
    local found=false
    
    while IFS=: read -r user uuid exp proto created; do
        if [[ "$user" == "$username" ]]; then
            local new_exp=$(date -d "+${days} days" +"%Y-%m-%d")
            echo "${user}:${uuid}:${new_exp}:${proto}:${created}" >> "$temp_file"
            found=true
        else
            echo "${user}:${uuid}:${exp}:${proto}:${created}" >> "$temp_file"
        fi
    done < "$CONFIG_DIR/vmess_users.db"
    
    mv "$temp_file" "$CONFIG_DIR/vmess_users.db"
    
    if [[ "$found" == true ]]; then
        success "Account renewed"
    else
        error "Account not found"
    fi
    sleep 2
}

list_vmess_accounts() {
    show_banner
    echo -e "${WHITE}${BOLD}                    VMESS ACCOUNTS${NC}"
    echo -e "${YELLOW}───────────────────────────────────────────────────────────────────${NC}"
    echo ""
    printf "%-15s %-36s %-12s %s\n" "USERNAME" "UUID" "EXPIRY" "STATUS"
    echo -e "${CYAN}─────────────────────────────────────────────────────────────────${NC}"
    
    while IFS=: read -r user uuid exp proto created; do
        [[ -z "$user" ]] && continue
        local status="ACTIVE"
        [[ "$(date -d "$exp" +%s 2>/dev/null || echo 0)" -lt "$(date +%s)" ]] && status="${RED}EXPIRED${NC}"
        printf "%-15s %-36s %-12s %b\n" "$user" "$uuid" "$exp" "$status"
    done < "$CONFIG_DIR/vmess_users.db"
    
    echo ""
    read -rp "Press Enter to continue..."
}

show_vmess_links() {
    show_banner
    echo -e "${WHITE}${BOLD}                    VMESS LINKS${NC}"
    echo -e "${YELLOW}───────────────────────────────────────────────────────────────────${NC}"
    echo ""
    
    local domain
    domain=$(get_domain)
    
    while IFS=: read -r user uuid exp proto created; do
        [[ -z "$user" ]] && continue
        
        local vmess_json=$(cat << EOF
{"v":"2","ps":"${user}","add":"${domain}","port":"443","id":"${uuid}","aid":"0","scy":"auto","net":"ws","type":"none","host":"${domain}","path":"/vmess","tls":"tls","sni":"${domain}"}
EOF
)
        local vmess_link=$(encode_base64 "$vmess_json")
        
        echo -e "${CYAN}User: ${user}${NC}"
        echo -e "${GREEN}vmess://${vmess_link}${NC}"
        echo ""
    done < "$CONFIG_DIR/vmess_users.db"
    
    read -rp "Press Enter to continue..."
}

delete_vless_account() {
    read -rp "Username to delete: " username
    if sed -i "/^${username}:/d" "$CONFIG_DIR/vless_users.db"; then
        success "VLESS account removed (restart Xray to fully apply)"
    else
        error "Account not found"
    fi
    sleep 2
}

renew_vless_account() {
    read -rp "Username: " username
    read -rp "Additional days: " days
    
    local temp_file=$(mktemp)
    local found=false
    
    while IFS=: read -r user uuid exp proto created; do
        if [[ "$user" == "$username" ]]; then
            local new_exp=$(date -d "+${days} days" +"%Y-%m-%d")
            echo "${user}:${uuid}:${new_exp}:${proto}:${created}" >> "$temp_file"
            found=true
        else
            echo "${user}:${uuid}:${exp}:${proto}:${created}" >> "$temp_file"
        fi
    done < "$CONFIG_DIR/vless_users.db"
    
    mv "$temp_file" "$CONFIG_DIR/vless_users.db"
    
    if [[ "$found" == true ]]; then
        success "Account renewed"
    else
        error "Account not found"
    fi
    sleep 2
}

list_vless_accounts() {
    show_banner
    echo -e "${WHITE}${BOLD}                    VLESS ACCOUNTS${NC}"
    echo -e "${YELLOW}───────────────────────────────────────────────────────────────────${NC}"
    echo ""
    printf "%-15s %-36s %-12s %s\n" "USERNAME" "UUID" "EXPIRY" "STATUS"
    echo -e "${CYAN}─────────────────────────────────────────────────────────────────${NC}"
    
    while IFS=: read -r user uuid exp proto created; do
        [[ -z "$user" ]] && continue
        local status="ACTIVE"
        [[ "$(date -d "$exp" +%s 2>/dev/null || echo 0)" -lt "$(date +%s)" ]] && status="${RED}EXPIRED${NC}"
        printf "%-15s %-36s %-12s %b\n" "$user" "$uuid" "$exp" "$status"
    done < "$CONFIG_DIR/vless_users.db"
    
    echo ""
    read -rp "Press Enter to continue..."
}

show_vless_links() {
    show_banner
    echo -e "${WHITE}${BOLD}                    VLESS LINKS${NC}"
    echo -e "${YELLOW}───────────────────────────────────────────────────────────────────${NC}"
    echo ""
    
    local domain
    domain=$(get_domain)
    
    while IFS=: read -r user uuid exp proto created; do
        [[ -z "$user" ]] && continue
        
        local vless_link="vless://${uuid}@${domain}:443?security=tls&encryption=none&host=${domain}&type=ws&path=%2Fvless&sni=${domain}#${user}"
        
        echo -e "${CYAN}User: ${user}${NC}"
        echo -e "${GREEN}${vless_link}${NC}"
        echo ""
    done < "$CONFIG_DIR/vless_users.db"
    
    read -rp "Press Enter to continue..."
}

# ═══════════════════════════════════════════════════════════════════
# INITIALIZATION
# ═══════════════════════════════════════════════════════════════════

check_root
init_directories

# Check dependencies
if ! command -v jq &>/dev/null; then
    info "Installing jq..."
    apt-get update -qq && apt-get install -y -qq jq
fi

# Start main menu
main_menu
