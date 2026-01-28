#!/bin/bash
# A fully interactive installer, designed to work via curl.

# Exit immediately if a command exits with a non-zero status.
set -e

# --- Configuration ---
CONTAINER_NAME="metube"
BASE_DIR="/docker/$CONTAINER_NAME"
PORT="5009"
DEFAULT_NETWORK="bridge" # The default network to use if the user declines a custom one.

# --- Colors for output ---
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# --- Pre-flight Checks ---

# 1. Root Check
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}This script must be run as root. Please use sudo.${NC}"
   exit 1
fi

# 2. Terminal Check
if ! [ -t 0 ] && ! [ -r /dev/tty ]; then
    echo -e "${RED}Error: This script is interactive but has no terminal to connect to.${NC}" >&2
    exit 1
fi

# 3. User Detection
if [[ -n "$SUDO_USER" ]]; then
    RUN_USER="$SUDO_USER"
    RUN_UID=$(id -u "$SUDO_USER")
    RUN_GID=$(id -g "$SUDO_USER")
else
    RUN_USER=$(id -un 1000 2>/dev/null || echo "user")
    RUN_UID=$(id -u "$RUN_USER" 2>/dev/null || echo "1000")
    RUN_GID=$(id -g "$RUN_USER" 2>/dev/null || echo "1000")
fi
echo "Running installer on behalf of user: $RUN_USER (UID: $RUN_UID, GID: $RUN_GID)"


# --- Core Functions ---

check_dependencies() {
    echo "Checking dependencies..."
    if ! command -v docker &> /dev/null; then
        if command -v dietpi-software &> /dev/null; then
            echo "DietPi detected. Installing Docker and Docker Compose..."
            dietpi-software install 162 134
        else
            echo "Installing Docker via official script..."
            curl -fsSL https://get.docker.com | sh
            usermod -aG docker "$RUN_USER"
        fi
    fi

    if docker compose version &> /dev/null; then
        DOCKER_CMD="docker compose"
    elif command -v docker-compose &> /dev/null; then
        DOCKER_CMD="docker-compose"
    else
        echo -e "${RED}Docker Compose not found. Please install it.${NC}"
        exit 1
    fi
}

setup_folders() {
    echo "Creating directories..."
    mkdir -p "$BASE_DIR"
    mkdir -p /media/ytdl
    chown -R "$RUN_USER":"$RUN_USER" "$BASE_DIR" /media
    chmod -R 755 /media
}

setup_network() {
    # UPDATED to be more informative by using the $DEFAULT_NETWORK variable.
    read -p "The default Docker network is '$DEFAULT_NETWORK'. Would you like to use a different one? (y/n): " net_choice < /dev/tty

    if [[ $net_choice == [yY] ]]; then
        echo "Available networks:"
        mapfile -t networks < <(docker network ls --format "{{.Name}}")
        for i in "${!networks[@]}"; do
            echo "$i) ${networks[$i]}"
        done
        echo "c) Create a new network"

        read -p "Select a number or 'c': " selection < /dev/tty

        if [[ $selection == "c" ]]; then
            read -p "Enter new network name: " new_net < /dev/tty
            docker network create "$new_net"
            SELECTED_NET="$new_net"
        else
            SELECTED_NET="${networks[$selection]}"
        fi
    else
        SELECTED_NET="$DEFAULT_NETWORK"
    fi
    echo "Using network: $SELECTED_NET"
}

create_compose() {
    echo "Writing docker-compose.yml..."
    local network_config=""
    local service_network_config=""

    if [[ "$SELECTED_NET" != "bridge" ]]; then
        network_config="
networks:
  app_net:
    external: true
    name: $SELECTED_NET"
        service_network_config="
    networks:
      - app_net"
    fi

    tee "$BASE_DIR/docker-compose.yml" > /dev/null <<EOF
services:
  $CONTAINER_NAME:
    image: ghcr.io/alexta69/metube:latest
    container_name: $CONTAINER_NAME
    restart: unless-stopped
    ports:
      - "$PORT:8081"
    volumes:
      - /media/ytdl:/downloads
$service_network_config
    environment:
      - UID=$RUN_UID
      - GID=$RUN_GID
      - UMASK=022
      - DOWNLOAD_DIR=/downloads
      - OUTPUT_TEMPLATE=%(title)s.%(ext)s
$network_config
EOF
    chown "$RUN_USER":"$RUN_USER" "$BASE_DIR/docker-compose.yml"
}

setup_samba_share() {
    if ! command -v smbd &> /dev/null; then
        echo "Samba (smbd) not installed. Skipping this step."
        return
    fi

    read -p "Would you like to ensure /media is shared via Samba? (y/n): " samba_choice < /dev/tty

    if [[ $samba_choice == [yY] ]]; then
        if grep -qE "^\s*path\s*=\s*/media\s*$" /etc/samba/smb.conf; then
            echo -e "${GREEN}The location /media is already shared.${NC}"
        else
            echo "Adding /media to Samba configuration..."
            tee -a /etc/samba/smb.conf > /dev/null <<EOF

[Media]
   comment = Media Folder
   path = /media
   browseable = yes
   read only = no
   guest ok = yes
   create mask = 0644
   directory mask = 0755
   force user = $RUN_USER
EOF
            echo "Restarting Samba service..."
            systemctl restart smbd
            echo -e "${GREEN}Samba share [Media] added.${NC}"
        fi
    fi
}

# --- Execution Sequence ---
echo "Starting MeTube interactive deployment..."
check_dependencies
setup_folders
setup_network
create_compose

echo "Building container from $BASE_DIR..."
if $DOCKER_CMD -f "$BASE_DIR/docker-compose.yml" up -d; then
    IP_ADDR=$(hostname -I | awk '{print $1}')
    echo -e "${GREEN}Deployment successful!${NC}"
    echo "Access MeTube at http://$IP_ADDR:$PORT"
    setup_samba_share
    echo -e "${GREEN}Done!${NC}"
else
    echo -e "${RED}Docker Compose deployment failed.${NC}"
    exit 1
fi
