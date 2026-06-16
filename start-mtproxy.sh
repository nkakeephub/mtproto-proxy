#!/bin/bash

# Install Telemt proxy server (MTProxy) via Docker Distroless
# telemt-from-image.sh
# Changelog: ip4, random url, ask +,  #9)

# Check for root privileges
[ "$EUID" -ne 0 ] && { echo -e "[ERROR] Please run as root"; exit 1; }

# --- Docker images:     --------------------------------------------
IMAGE_NAME="whn0thacked/telemt-docker:latest"

# --- Default values ---
PORT="4334"
# Fetch random site or default to google.com (Из вашего репозитория nkakeephub)
SITE=$(curl -s https://githubusercontent.com | shuf -n 1)
SITE=${SITE:-"google.com"}

# --- Conf ---
OVERWRITE=true
CONFIG_FILE="telemt.toml"
COMPOSE_FILE="docker-compose.yml"
BUILD_SCRIPT_URL="https://githubusercontent.com"; SCRIPT_NAME=$(basename "$BUILD_SCRIPT_URL")        

# --- Colors ---
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# --- Functions ---

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; } 
err()   { echo -e "${RED}[ERROR]${NC} $*"; }
ask()   { echo -ne "${YELLOW}[?]${NC} $*"; }

is_running() { [ "$(docker inspect -f '{{.State.Running}}' telemt 2>/dev/null)" == "true" ]; }

get_public_ip() { curl -4 -s --max-time 5 ifconfig.me || echo "YOUR_IP"; }

print_proxy_link() {
    local p=$1 s=$2
    local ip=$(get_public_ip)
    local domain_hex=$(echo -n "$SITE" | od -A n -t x1 | tr -d ' \n')
    local full_secret="ee${s}${domain_hex}"    
    local link="tg://proxy?server=$ip&port=$p&secret=$full_secret"
    echo "$link" > "proxy_link.txt"

    echo -e "=========================================================="
    echo -e "Copy the link below to Telegram and click it to activate the proxy"
    echo -e "🔗 ${CYAN}$link${NC}"
    echo -e "=========================================================="
}

deploy_container() {
    info "Removing old containers..."
    docker compose down --remove-orphans >/dev/null 2>&1

    info "Pulling latest image..."
    docker compose pull && start_container || { err "Failed to deploy. Docker environment is not ready!"; exit 1; }
}

start_container() {
    info "Starting container..."
    docker compose up -d || { err "Start failed!"; exit 1; }
}

prepare_files() {
    echo ""; info "Cleaning up old configuration files..."
    rm -f "$CONFIG_FILE" "$COMPOSE_FILE"
}

check_and_install() {
    info "This script can check & install dependencies (Update, Docker, Compose, OpenSSL, lsof)"
    ask "Press [ENTER] to check/install or ANY OTHER KEY to skip: "
    IFS= read -n 1 -s REPLY
    echo "" 

    if [[ -n "$REPLY" ]]; then
        info "Dependency check skipped by user"
        return 0
    fi

    echo -ne "[>] Updating package lists... "
    if apt-get update -y >/dev/null 2>&1; then
        echo -e "${GREEN}Done${NC}"
    else
        echo -e "${RED}Failed${NC} (Check internet)"
    fi

    echo -ne "[>] Checking Docker... "
    if command -v docker >/dev/null 2>&1; then
        echo -e "${GREEN}Found${NC}"
    else
        echo -e "${YELLOW}Installing...${NC}"
        if curl -fsSL https://get.docker.com | sh >/dev/null 2>&1; then
            systemctl enable --now docker >/dev/null 2>&1
        else
            err "Failed to install Docker."
            exit 1 
        fi
    fi

    echo -ne "[>] Checking Docker Compose... "
    if docker compose version >/dev/null 2>&1; then
        echo -e "${GREEN}Found${NC}"
    else
        echo -e "${YELLOW}Installing...${NC}"
        if apt-get install -y docker-compose-plugin >/dev/null 2>&1; then
            echo -e "${GREEN}Done${NC}"
        else
            err "Failed to install Docker Compose plugin."
            exit 1
        fi
    fi

    echo -ne "[>] Checking OpenSSL... "
    if command -v openssl >/dev/null 2>&1; then
        echo -e "${GREEN}Found${NC}"
    else
        echo -e "${YELLOW}Installing...${NC}"
        if apt-get install -y openssl >/dev/null 2>&1; then
            echo -e "${GREEN}Done${NC}"
        else
            echo -e "${RED}Failed${NC}"
            err "Could not install OpenSSL. Check your package manager."
            exit 1
        fi
    fi

    echo -ne "[>] Checking lsof... "
    if command -v lsof >/dev/null 2>&1; then
        echo -e "${GREEN}Found${NC}"
    else
        echo -e "${YELLOW}Installing...${NC}"
        if apt-get install -y lsof >/dev/null 2>&1; then
            echo -e "${GREEN}Done${NC}"
        else
            echo -e "${RED}Failed${NC}"
            err "Could not install lsof."
            exit 1 
        fi
    fi

    echo -e "\n${GREEN}[*] Environment is ready!${NC}"
    ask "Press [ENTER] to continue... "; read -r 
}

status_detection() {
    if [ -f "proxy_link.txt" ]; then
        local raw_link=$(head -n 1 proxy_link.txt)
        EXISTING_LINK="LINK:${GREEN}$raw_link${NC}" 
    else
        EXISTING_LINK="${YELLOW}⚠️ File proxy_link.txt not found (Install first)${NC}"
    fi

    if [ -f "$COMPOSE_FILE" ] && command -v docker >/dev/null 2>&1; then
        INST_ICON="${GREEN}●${NC}"
        
        if is_running; then
            ACT_ICON="${GREEN}●${NC}"
            STATUS_MSG="(Status: ${GREEN}Active${NC})"
            TOGGLE_ACTION="Turn OFF Proxy"
        else
            ACT_ICON="${RED}○${NC}"
            STATUS_MSG="(Status: ${YELLOW}Stopped${NC})"
            TOGGLE_ACTION="Turn ON Proxy "
        fi
    else
        INST_ICON="${RED}○${NC}"
        ACT_ICON="${RED}○${NC}"
        STATUS_MSG="${RED}(Not installed)${NC}"
        TOGGLE_ACTION="Not installed "
        EXISTING_LINK="" 
    fi
    DOCKER_INFO="\nSTATUS:  Installed [${INST_ICON}]  |  Active [${ACT_ICON}]"
}

gui_top() {
    clear
    echo -e "${GREEN}"
    echo "╔════════════════════════════════════════════════════╗"
    echo "║              MTProxy (Telemt) Installer            ║"
    echo "╚════════════════════════════════════════════════════╝"
    echo -e "${NC}Build from image: $IMAGE_NAME"
}

main_menu() {
    echo -e "$DOCKER_INFO"
    [ -n "$EXISTING_LINK" ] && echo -e "$EXISTING_LINK"
    echo -e "\n\nSelect action:"
    echo -e " 1| ${CYAN}Fast Install             (Port: $PORT, Domain: $SITE)${NC}"
    echo -e " 2| Custom Install           (Custom Port, Domain...)\n"
    echo -e " 3| ${YELLOW}${TOGGLE_ACTION} ${NC}          $STATUS_MSG"
    echo -e " 4| ${RED}Full Uninstall${NC}           (Stop & Remove All)"
    echo -e " 5| ${GREEN}Update Image${NC}             (Pull latest & Restart)\n"
    echo -e ""; ask "Choose option [1-5]: "
    read -r INSTALL_MODE
}

# --- Output (start actions)---
status_detection
gui_top
main_menu

# Logic Selection
case $INSTALL_MODE in
    1) check_and_install && info "Mode: Fast Install\n" ;;
    2) check_and_install && info "Mode: Manual Install"; OVERWRITE=false ;;
    3)
        if [ -f "$COMPOSE_FILE" ]; then
            if is_running; then
                info "Stopping container..."
                docker compose stop && info "Stopped."
                exit 0 
            else
                start_container
                exit 0
            fi
        else
            err "Proxy is not installed yet"
        fi
        ;;
    4)
        warn "This will remove EVERYTHING related to Telemt"
        ask "Are you sure? Press [ENTER] to confirm or type anything to cancel: "
        IFS= read -r REPLY
        if [[ -z "$REPLY" ]]; then
            [ -f "$CONFIG_FILE" ] && { 
                OLD_PORT=$(grep "port =" "$CONFIG_FILE" | awk -F'=' '{print $2}' | tr -d '[:space:]"')
                [ -n "$OLD_PORT" ] && command -v ufw >/dev/null && ufw delete allow "$OLD_PORT"/tcp || true; }
            [ -f "$COMPOSE_FILE" ] && { info "Cleaning Docker..."; docker compose down --rmi all --volumes --remove-orphans; }
            rm -f "$CONFIG_FILE" "$COMPOSE_FILE" "proxy_link.txt"
            info "Uninstall complete. System is clean."
        fi
        exit 0 ;;
    5)
        info "Updating Telemt image..."
        if [ -f "$COMPOSE_FILE" ]; then
            docker compose pull && docker compose up -d --remove-orphans
            info "Update complete. Running latest version."
        else
            err "Configuration not found. Install proxy first."
        fi
        exit 0 ;;
    9)
        info "Fetching build script..."
        curl -sLO "$BUILD_SCRIPT_URL"
        if [ -f "./$SCRIPT_NAME" ]; then
            chmod +x "./$SCRIPT_NAME"
            exec "./$SCRIPT_NAME"
        else
            err "Failed to download script from GitHub."
            exit 1
        fi
        ;;
    *) err "Invalid option."; exit 1 ;;
esac

# --- Proxy Secret: Keep Existing or New ---
if [ -f "$CONFIG_FILE" ]; then
    OLD_SECRET=$(grep "docker =" "$CONFIG_FILE" | awk -F'=' '{print $2}' | tr -d ' "')
    echo -e "${YELLOW}[?] Config found. Use existing secret? ($OLD_SECRET)${NC}"
    echo -e "${CYAN}    (Keeping the old secret will keep your current proxy link working)${NC}"

    ask "Press [ENTER] to keep current, type anything for a NEW one: "
    IFS= read -n 1 -s REPLY
    if [[ -z "$REPLY" ]]; then
        SECRET=$OLD_SECRET
        info "Keeping existing secret."
    else
        SECRET=$(openssl rand -hex 16)
        info "New secret generated: $SECRET"
        warn "Note: Old proxy links will no longer work!"
    fi
else
    SECRET=$(openssl rand -hex 16)
    info "Generated secret: $SECRET"
fi

# --- Custom setup parameters ---
if [ "$OVERWRITE" = false ]; then
    while true; do
        ask "Enter port (default $PORT): "; read -r input_port
        PORT=${input_port:-$PORT}
    
        if [ "$PORT" -lt 1024 ]; then
            warn "Port $PORT is privileged (needs root). Cannot verify if occupied."
            echo -e "${YELLOW}⚠️  Please check manually or use port > 1024${NC}"
            continue 
        fi
        
        if lsof -i :"$PORT" -sTCP:LISTEN -t >/dev/null ; then
            warn "Port $PORT is already occupied!"
            lsof -i :"$PORT" -sTCP:LISTEN
            echo -e "${YELLOW}Please choose a different port or stop the service above.${NC}"
        else
            info "Port $PORT is available."
            break
        fi
    done
        
    ask "Enter domain (default $SITE): "; read -r input_site
    SITE=${input_site:-$SITE}    
    
    echo -e "\n${CYAN}--------------------------------${NC}"
    echo -e "IP:Port: ${GREEN}$(get_public_ip):$PORT${NC}"
    echo -e "Secret:  ${GREEN}$SECRET${NC}"
    echo -e "${CYAN}--------------------------------${NC}"
fi

if command -v ufw >/dev/null && ufw status | grep -q "active"; then
    info "Opening port $PORT..."
    ufw allow "$PORT"/tcp
fi

# --- File Generation ---
prepare_files
info "Config ready: docker-compose.yml, telemt.toml"

cat > "$CONFIG_FILE" <<EOF
show_link = ["docker"]
[general]
fast_mode = true
use_middle_proxy = true
[general.modes]
classic = false
secure = false
tls = true
[server]
port = $PORT
listen_addr_ipv4 = "0.0.0.0"
listen_addr_ipv6 = "::"
[[server.listeners]]
ip = "0.0.0.0"
[timeouts]
client_handshake = 15
tg_connect = 10
client_keepalive = 60
client_ack = 300
[censorship]
tls_domain = "$SITE"
mask = true
[access.users]
docker = "$SECRET"
EOF

cat > "$COMPOSE_FILE" <<EOF
services:
  telemt:
    image: $IMAGE_NAME
    container_name: telemt
    restart: unless-stopped
    volumes:
      - ./$CONFIG_FILE:/etc/telemt.toml:ro
    ports:
      - "$PORT:$PORT/tcp"
    cap_drop:
      - ALL
    cap_add:
      - NET_BIND_SERVICE
    read_only: true
    security_opt:
      - no-new-privileges:true
    tmpfs:
      - /run/telemt:rw,nosuid,nodev,noexec,mode=1777,size=1m
      - /tmp:rw,nosuid,nodev,noexec,size=16m
    deploy:
      resources:
        limits:
          memory: 128M
EOF

# --- Execution ---
deploy_container && { echo -e "\n🎉 Proxy is ready to use!"; }

# --- Status ---
is_running && print_proxy_link "$PORT" "$SECRET" || info "Status: Stopped. Use Option 3 later."
