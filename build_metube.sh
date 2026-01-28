#!/bin/bash

# --- Configuration ---
CONTAINER_NAME="metube"
BASE_DIR="/docker/$CONTAINER_NAME"
PORT="5009"

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo "Starting deployment for $CONTAINER_NAME..."

# 1. Dependency Check (Supports V1 and V2)
check_dependencies() {
    DOCKER_CMD=""
    if ! command -v docker &> /dev/null; then
        echo "Docker not found. Installing via DietPi-Software..."
        sudo dietpi-software install 162 134
    fi

    if command -v docker-compose &> /dev/null; then
        DOCKER_CMD="docker-compose"
    else
        DOCKER_CMD="docker compose"
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
    read -p "Is this connected to default Docker network? (y/n): " net_choice
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
      - UID=1000
      - GID=1000
      - UMASK=022
      - DOWNLOAD_DIR=/downloads
      - OUTPUT_TEMPLATE=%(title)s.%(ext)s

networks:
  app_net:
    external: true
    name: $SELECTED_NET
EOF
}

# 5. Smart Samba Share Function (Location-Based)
setup_samba_share() {
    if command -v smbd &> /dev/null; then
        echo "Samba detected. Checking existing shares..."
        read -p "Would you like to ensure the /media folder is shared via Samba? (y/n): " samba_choice
        if [[ $samba_choice == [yY] ]]; then
            # This regex looks for an exact 'path = /media' line regardless of the title
            if grep -E "^[[:space:]]*path[[:space:]]*=[[:space:]]*/media[[:space:]]*$" /etc/samba/smb.conf > /dev/null; then
                echo -e "${GREEN}The location /media is already shared in your Samba config. Skipping duplicate entry.${NC}"
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
   force user = dietpi
EOF
                sudo systemctl restart smbd
                echo -e "${GREEN}Samba share [Media] added and service restarted.${NC}"
            fi
        fi
    else
        echo "Samba is not installed. Skipping Samba setup."
    fi
}

# --- Execution Sequence ---
check_dependencies
setup_folders
setup_network
create_compose

echo "Building container..."
cd "$BASE_DIR" || exit
if sudo $DOCKER_CMD up -d; then
    IP_ADDR=$(hostname -I | awk '{print $1}')
    echo -e "${GREEN}success${NC}"
    echo "Done! Access MeTube at http://$IP_ADDR:$PORT"

    # Run the Samba check
    setup_samba_share
else
    echo -e "${RED}failed${NC}"
    exit 1
fi

