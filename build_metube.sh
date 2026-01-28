#!/bin/bash

# --- Configuration ---
CONTAINER_NAME="metube"
BASE_DIR="/docker/$CONTAINER_NAME"
PORT="5009"
SAMBA_USER=$(id -un 1000 2>/dev/null || echo "$USER")

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo "Starting deployment for $CONTAINER_NAME..."

# 1. Dependency Check
check_dependencies() {
    if ! command -v docker &> /dev/null; then
        if command -v dietpi-software &> /dev/null; then
            echo "DietPi detected. Installing Docker via dietpi-software..."
            sudo dietpi-software install 162 134
        else
            echo "Installing Docker via official script..."
            curl -fsSL https://get.docker.com | sh
            sudo usermod -aG docker "$USER"
        fi
    fi

    if docker compose version &> /dev/null; then
        DOCKER_CMD="docker compose"
    elif command -v docker-compose &> /dev/null; then
        DOCKER_CMD="docker-compose"
    else
        echo -e "${RED}Docker Compose not found. Please install it first.${NC}"
        exit 1
    fi
}

# 2. Setup Folders
setup_folders() {
    echo "Creating directories..."
    sudo mkdir -p "$BASE_DIR"
    sudo mkdir -p /media/ytdl
    sudo chmod -R 755 "$BASE_DIR"
    sudo chmod 755 /media
}

# 3. Network Selection
setup_network() {
    if [ -t 0 ]; then
        read -p "Is this connected to default Docker network? (y/n): " net_choice
    else
        net_choice="y"
    fi

    if [[ $net_choice == [nN] ]]; then
        echo "Available networks:"
        mapfile -t networks < <(docker network ls --format "{{.Name}}")
        for i in "${!networks[@]}"; do
            echo "$i) ${networks[$i]}"
        done
        echo "c) Create a new network"

        read -p "Select a number or 'c': " selection
        if [[ $selection == "c" ]]; then
            read -p "Enter new network name: " new_net
            docker network create "$new_net"
            SELECTED_NET="$new_net"
        else
            SELECTED_NET="${networks[$selection]}"
        fi
    else
        SELECTED_NET="bridge"
    fi
}

# 4. Create Docker Compose File
create_compose() {
    echo "Writing docker-compose.yml..."
    # If using default bridge, we must NOT define networks: or app_net:
    if [ "$SELECTED_NET" == "bridge" ]; then
        cat <<EOF | sudo tee "$BASE_DIR/docker-compose.yml" > /dev/null
services:
  $CONTAINER_NAME:
    image: ghcr.io/alexta69/metube:latest
    container_name: $CONTAINER_NAME
    restart: unless-stopped
    ports:
      - "$PORT:8081"
    volumes:
      - /media/ytdl:/downloads
    environment:
      - UID=$(id -u)
      - GID=$(id -g)
      - UMASK=022
      - DOWNLOAD_DIR=/downloads
      - OUTPUT_TEMPLATE=%(title)s.%(ext)s
EOF
    else
        cat <<EOF | sudo tee "$BASE_DIR/docker-compose.yml" > /dev/null
services:
  $CONTAINER_NAME:
    image: ghcr.io/alexta69/metube:latest
    container_name: $CONTAINER_NAME
    restart: unless-stopped
    ports:
      - "$PORT:8081"
    volumes:
      - /media/ytdl:/downloads
    networks:
      - app_net
    environment:
      - UID=$(id -u)
      - GID=$(id -g)
      - UMASK=022
      - DOWNLOAD_DIR=/downloads
      - OUTPUT_TEMPLATE=%(title)s.%(ext)s

networks:
  app_net:
    external: true
    name: $SELECTED_NET
EOF
    fi
}

# 5. Samba Share Function
setup_samba_share() {
    if command -v smbd &> /dev/null; then
        if [ -t 0 ]; then
            read -p "Would you like to ensure /media is shared via Samba? (y/n): " samba_choice
        else
            samba_choice="n"
        fi

        if [[ $samba_choice == [yY] ]]; then
            if grep -E "^[[:space:]]*path[[:space:]]*=[[:space:]]*/media[[:space:]]*$" /etc/samba/smb.conf > /dev/null; then
                echo -e "${GREEN}The location /media is already shared.${NC}"
            else
                echo "Adding /media to Samba configuration..."
                cat <<EOF | sudo tee -a /etc/samba/smb.conf > /dev/null

[Media]
   comment = Media Folder
   path = /media
   browseable = yes
   read only = no
   guest ok = yes
   create mask = 0644
   directory mask = 0755
   force user = $SAMBA_USER
EOF
                sudo systemctl restart smbd
                echo -e "${GREEN}Samba share [Media] added.${NC}"
            fi
        fi
    fi
}

# --- Execution Sequence ---
check_dependencies
setup_folders
setup_network
create_compose

echo "Building container..."
cd "$BASE_DIR" || { echo "Directory $BASE_DIR not found"; exit 1; }

if sudo $DOCKER_CMD up -d; then
    IP_ADDR=$(hostname -I | awk '{print $1}')
    echo -e "${GREEN}success${NC}"
    echo "Done! Access MeTube at http://$IP_ADDR:$PORT"
    setup_samba_share
    
    # --- Cleanup Section ---
    echo "Cleaning up installer script..."
    rm -- "$0"
else
    echo -e "${RED}failed${NC}"
    exit 1
fi
