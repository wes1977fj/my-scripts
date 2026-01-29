#!/bin/bash
# MeTube TUI Installer - Themed & Verified Version
set -e

# --- Custom Whiptail Theme (Blue/Cyan) ---
export NEWT_COLORS='
  root=,blue
  window=,lightgray
  border=blue,lightgray
  shadow=,black
  button=white,blue
  actbutton=white,cyan
  compactbutton=white,blue
  title=blue,lightgray
  textbox=black,lightgray
  acttextbox=lightgray,black
  entry=black,white
  disentry=gray,lightgray
  checkbox=black,lightgray
  actcheckbox=lightgray,black
  listbox=black,lightgray
  actlistbox=lightgray,black
'

# --- System Checks ---
if ((BASH_VERSINFO[0] < 4)); then
    echo -e "\033[0;31mError: Bash 4.0+ required.\033[0m" >&2; exit 1
fi

if [[ $EUID -ne 0 ]]; then
    echo -e "\033[0;31mPlease run as root.\033[0m"; exit 1
fi

# Detect actual user context
if [[ -n "$SUDO_USER" ]]; then RUN_USER="$SUDO_USER"; else RUN_USER=$(id -un 1000 2>/dev/null || echo "user"); fi
RUN_UID=$(id -u "$RUN_USER" 2>/dev/null || echo "1000")
RUN_GID=$(id -g "$RUN_USER" 2>/dev/null || echo "1000")

# --- Dependencies ---
check_deps() {
    if ! command -v whiptail &> /dev/null; then apt-get update && apt-get install -y whiptail; fi
    
    if ! command -v docker &> /dev/null; then
        if command -v dietpi-software &> /dev/null; then 
            dietpi-software install 162 134
        else 
            curl -fsSL https://get.docker.com | sh; usermod -aG docker "$RUN_USER"
        fi
    fi
    
    if docker compose version &> /dev/null; then DOCKER_CMD="docker compose";
    elif command -v docker-compose &> /dev/null; then DOCKER_CMD="docker-compose";
    else echo "Docker Compose not found."; exit 1; fi
}

# --- Interactive Configuration ---
get_config() {
    USER_PORT=$(whiptail --title "MeTube Config" --inputbox "Enter Port for MeTube Web UI:" 10 60 "5009" 3>&1 1>&2 2>&3)
    HOST_DL_PATH=$(whiptail --title "Storage Config" --inputbox "Host path for downloads:" 10 60 "/media/ytdl" 3>&1 1>&2 2>&3)
    
    # Network Choice
    mapfile -t nets < <(docker network ls --format "{{.Name}}")
    NET_OPTIONS=()
    for net in "${nets[@]}"; do NET_OPTIONS+=("$net" "Existing Network"); done
    SELECTED_NET=$(whiptail --title "Networking" --menu "Select Docker Network:" 15 60 5 "${NET_OPTIONS[@]}" 3>&1 1>&2 2>&3)
}

# --- Deployment ---
deploy_container() {
    mkdir -p "/docker/metube" "$HOST_DL_PATH"
    
    cat <<EOF > "/docker/metube/docker-compose.yml"
services:
  metube:
    image: ghcr.io/alexta69/metube:latest
    container_name: metube
    restart: unless-stopped
    ports:
      - "$USER_PORT:8081"
    volumes:
      - "$HOST_DL_PATH:/downloads"
    environment:
      - UID=$RUN_UID
      - GID=$RUN_GID
      - DOWNLOAD_DIR=/downloads
EOF

    chown -R "$RUN_USER":"$RUN_USER" "/docker/metube" "$HOST_DL_PATH"
    $DOCKER_CMD -f "/docker/metube/docker-compose.yml" up -d
}

# --- Health Check Loop ---
verify_deployment() {
    local count=0
    local max_attempts=15
    
    (
    while [ $count -lt $max_attempts ]; do
        # Check if container is running
        if [ "$(docker inspect -f '{{.State.Running}}' metube 2>/dev/null)" == "true" ]; then
            echo 100
            break
        fi
        sleep 2
        count=$((count + 1))
        echo $(( count * 100 / max_attempts ))
    done
    ) | whiptail --title "Deployment Progress" --gauge "Starting MeTube and verifying status..." 10 60 0
}

# --- Samba Integration ---
setup_samba() {
    if ! command -v smbd &> /dev/null; then return; fi

    CHOICES=$(whiptail --title "Samba Configuration" --checklist \
    "Select shares to create (Space to select):" 15 65 3 \
    "DOWNLOADS" "MeTube Downloads ($HOST_DL_PATH)" ON \
    "MEDIA" "System Media Folder (/media)" OFF \
    "DOCKER" "Docker Config Folders (/docker)" OFF 3>&1 1>&2 2>&3)

    if [ -z "$CHOICES" ]; then return; fi

    local needs_restart=0
    for CHOICE in $CHOICES; do
        case $CHOICE in
            '"DOWNLOADS"') NAME="MeTube"; PATH_VAL="$HOST_DL_PATH" ;;
            '"MEDIA"')     NAME="Media_Root"; PATH_VAL="/media" ;;
            '"DOCKER"')    NAME="Docker_Configs"; PATH_VAL="/docker" ;;
        esac

        if ! grep -q "path = $PATH_VAL" /etc/samba/smb.conf; then
            cat <<EOF >> /etc/samba/smb.conf

[$NAME]
   path = $PATH_VAL
   browseable = yes
   read only = no
   guest ok = yes
   create mask = 0644
   directory mask = 0755
   force user = dietpi
EOF
            needs_restart=1
        fi
    done

    if [ $needs_restart -eq 1 ]; then
        systemctl restart smbd || true
    fi
}

# --- Execute ---
check_deps
get_config
deploy_container
verify_deployment
setup_samba

IP_ADDR=$(hostname -I | awk '{print $1}')
whiptail --title "Installation Success" --msgbox "MeTube is ready!\n\nAccess it at: http://$IP_ADDR:$USER_PORT\nDownloads located at: $HOST_DL_PATH" 12 60
