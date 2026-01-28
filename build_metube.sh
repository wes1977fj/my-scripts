#!/bin/bash # [cite: 1]
# The definitive, fully interactive installer script.

# Exit immediately if a command exits with a non-zero status.
set -e # [cite: 2]

# --- Bash Version Check ---
if ((BASH_VERSINFO[0] < 4)); # [cite: 2]
then # [cite: 3]
    echo -e "\033[0;31mError: This script requires Bash version 4.0 or higher.\033[0m" >&2; # [cite: 3]
    exit 1 # [cite: 4]
fi

# --- Container-Specific Configuration ---
CONTAINER_NAME="metube"; DOCKER_IMAGE="ghcr.io/alexta69/metube:latest"; DEFAULT_PORT="5009" # [cite: 4]
declare -A VOLUME_MAPPINGS; VOLUME_MAPPINGS["/media/ytdl"]="/downloads" # [cite: 4]

# --- Dynamic Variables ---
DEFAULT_NETWORK="bridge" # [cite: 4]

# --- Colors for output ---
GREEN='\033[0;32m'; # [cite: 4]
RED='\033[0;31m'; NC='\033[0m' # [cite: 5]

# --- Pre-flight Checks ---
if [[ $EUID -ne 0 ]]; then echo -e "${RED}Run as root.${NC}"; # [cite: 5]
exit 1; fi # [cite: 6]
if ! [ -t 0 ] && ! [ -r /dev/tty ]; then echo -e "${RED}No terminal.${NC}" >&2; # [cite: 6]
exit 1; fi # [cite: 7]
if [[ -n "$SUDO_USER" ]]; then RUN_USER="$SUDO_USER"; else RUN_USER=$(id -un 1000 2>/dev/null || echo "user"); # [cite: 7]
fi # [cite: 8]
RUN_UID=$(id -u "$RUN_USER" 2>/dev/null || echo "1000"); RUN_GID=$(id -g "$RUN_USER" 2>/dev/null || echo "1000") # [cite: 8]
echo "Running installer for user: $RUN_USER (UID: $RUN_UID, GID: $RUN_GID)" # [cite: 8]

# --- Core Functions ---
check_dependencies() { echo "Checking dependencies..."; # [cite: 8]
if ! command -v docker &> /dev/null; then if command -v dietpi-software &> /dev/null; then dietpi-software install 162 134; # [cite: 9]
else curl -fsSL https://get.docker.com | sh; usermod -aG docker "$RUN_USER"; fi; fi; if docker compose version &> /dev/null; # [cite: 10]
then DOCKER_CMD="docker compose"; elif command -v docker-compose &> /dev/null; then DOCKER_CMD="docker-compose"; else echo -e "${RED}Docker Compose not found.${NC}"; exit 1; # [cite: 11]
fi; } # [cite: 12]

setup_folders() { echo "Creating directories..."; mkdir -p "/docker/$CONTAINER_NAME"; for host_path in "${!VOLUME_MAPPINGS[@]}"; do mkdir -p "$host_path"; done; # [cite: 12]
chown -R "$RUN_USER":"$RUN_USER" "/docker/$CONTAINER_NAME" "${!VOLUME_MAPPINGS[@]}"; } # [cite: 13]

setup_network() { 
    # Logic updated to make Enter default to Yes [cite: 13]
    read -p "The default Docker network is '$DEFAULT_NETWORK'. Use the default one? (y/n) [Enter for Yes]: " nc < /dev/tty; # [cite: 13]
    if [[ -z "$nc" || $nc == [yY] ]]; then # [cite: 14]
        SELECTED_NET="$DEFAULT_NETWORK"; # [cite: 17]
    elif [[ $nc == [nN] ]]; then # [cite: 14]
        echo "Available networks:"; mapfile -t nets < <(docker network ls --format "{{.Name}}"); # [cite: 14]
        for i in "${!nets[@]}"; do echo "$i) ${nets[$i]}"; done; echo "c) Create new"; # [cite: 15]
        read -p "Select a number or 'c': " sel < /dev/tty; if [[ $sel == [cC] ]]; # [cite: 16]
        then read -p "New network name: " new_net < /dev/tty; docker network create "$new_net"; SELECTED_NET="$new_net"; else SELECTED_NET="${nets[$sel]}"; fi; # [cite: 17]
    else # [cite: 17]
        SELECTED_NET="$DEFAULT_NETWORK"; # [cite: 17]
    fi; # [cite: 18]
    echo "Using network: $SELECTED_NET"; # [cite: 18]
}

create_compose() { echo "Writing docker-compose.yml..."; local net_cfg="" svc_net_cfg="" vol_blk=""; if [[ "$SELECTED_NET" != "bridge" ]]; # [cite: 18]
then net_cfg="\nnetworks:\n  app_net:\n    external: true\n    name: $SELECTED_NET"; # [cite: 19]
svc_net_cfg="\n    networks:\n      - app_net"; fi; for host_path in "${!VOLUME_MAPPINGS[@]}"; # [cite: 20]
do vol_blk+=$(printf "\n      - %s:%s" "$host_path" "${VOLUME_MAPPINGS[$host_path]}"); done; # [cite: 21]
tee "/docker/$CONTAINER_NAME/docker-compose.yml" > /dev/null <<EOF
services:
  $CONTAINER_NAME:
    image: $DOCKER_IMAGE
    container_name: $CONTAINER_NAME
    restart: unless-stopped
    ports:
      - "$DEFAULT_PORT:8081"
    volumes:${vol_blk}
$svc_net_cfg
    environment:
      - UID=$RUN_UID
      - GID=$RUN_GID
      - UMASK=022
      - DOWNLOAD_DIR=/downloads
      - OUTPUT_TEMPLATE=%(title)s.%(ext)s
$net_cfg
EOF
chown "$RUN_USER":"$RUN_USER" "/docker/$CONTAINER_NAME/docker-compose.yml"; # [cite: 22]
} # [cite: 23]

setup_samba_share() {
    if ! command -v smbd &> /dev/null; # [cite: 23]
    then echo "Samba not installed. Skipping."; return; fi # [cite: 24]
    local samba_choice;
    # Logic updated to make Enter default to No [cite: 25]
    read -p "Configure Samba shares? (y/n) [Enter for No]: " samba_choice < /dev/tty; # [cite: 25]
    if [[ -z "$samba_choice" || $samba_choice != [yY] ]]; then return; fi # [cite: 25]
    
    local -a SHARES_TO_CREATE=(); while true; do # [cite: 26]
        echo; # [cite: 26]
        local prompt="Which directory would you like to share?"; local exit_prompt="n) None / Done"; if [ ${#SHARES_TO_CREATE[@]} -gt 0 ]; # [cite: 27]
        then prompt="Share another directory?"; exit_prompt="n) Done"; fi # [cite: 28]
        local -A unique_paths; unique_paths["/docker"]=1; # [cite: 28]
        for host_path in "${!VOLUME_MAPPINGS[@]}"; do unique_paths["$host_path"]=1; local parent_path; parent_path=$(dirname "$host_path"); if [[ "$parent_path" != "/" ]]; then unique_paths["$parent_path"]=1; fi; # [cite: 29]
        done # [cite: 30]
        local -a SHARE_CANDIDATES; # [cite: 30]
        mapfile -t SHARE_CANDIDATES < <(for path in "${!unique_paths[@]}"; do echo "$path"; done | sort -u); # [cite: 31]
        echo "$prompt"; local i=1; # [cite: 31]
        local -A share_options; for path in "${SHARE_CANDIDATES[@]}"; do echo "  $i) $path"; share_options[$i]="$path"; ((i++)); # [cite: 32]
        done # [cite: 33]
        echo "  c) Custom path"; echo "  $exit_prompt"; local selection; # [cite: 33]
        read -p "Select an option: " selection < /dev/tty # [cite: 34]
        local SELECTED_PATH=""; # [cite: 34]
        if [[ $selection == [nN] ]]; then break; elif [[ $selection == [cC] ]]; # [cite: 35]
        then read -p "  Enter absolute path: " CUSTOM_PATH < /dev/tty; if [[ -z "$CUSTOM_PATH" || # [cite: 36]
        "$CUSTOM_PATH" != /* ]]; then echo -e "${RED}Invalid path. Try again.${NC}"; continue; fi; SELECTED_PATH="$CUSTOM_PATH"; elif [[ -n "${share_options[$selection]}" ]]; # [cite: 37]
        then SELECTED_PATH="${share_options[$selection]}"; else echo -e "${RED}Invalid selection. Try again.${NC}"; continue; # [cite: 38]
        fi # [cite: 39]
        if [[ " ${SHARES_TO_CREATE[*]} " =~ " ${SELECTED_PATH} " ]]; # [cite: 39]
        then echo -e "${GREEN}Path '$SELECTED_PATH' is already in the list.${NC}"; else SHARES_TO_CREATE+=("$SELECTED_PATH"); echo -e "${GREEN}Added '$SELECTED_PATH' to the list.${NC}"; # [cite: 40]
        fi # [cite: 41]
    done; while true; do # [cite: 41]
        if [ ${#SHARES_TO_CREATE[@]} -eq 0 ]; # [cite: 41]
        then echo -e "${GREEN}No new shares selected.${NC}"; return; fi # [cite: 42]
        echo -e "\n--- Confirmation ---"; # [cite: 42]
        echo "The following shares are ready:"; local i=1; for path in "${SHARES_TO_CREATE[@]}"; do echo "  $i) $path"; ((i++)); # [cite: 43]
        done # [cite: 44]
        read -p "Action: (p)roceed, (r)emove, (c)ancel: " action < /dev/tty # [cite: 44]
        case "$action" in [pP]) echo "Proceeding with installation..."; # [cite: 44]
        break;; [rR]) read -p "Enter # to remove: " num < /dev/tty; if ! [[ "$num" =~ ^[0-9]+$ ]] || # [cite: 45]
        (( num < 1 || num > ${#SHARES_TO_CREATE[@]} )); then echo -e "${RED}Invalid number.${NC}"; else local idx=$((num - 1)); # [cite: 46]
        local item="${SHARES_TO_CREATE[$idx]}"; unset "SHARES_TO_CREATE[$idx]"; SHARES_TO_CREATE=("${SHARES_TO_CREATE[@]}"); echo -e "${GREEN}Removed '$item'.${NC}"; fi;; [cC]) echo -e "${RED}Samba installation cancelled.${NC}"; return;; # [cite: 47]
        *) echo -e "${RED}Invalid action. Please choose 'p', 'r', or 'c'.${NC}";; esac # [cite: 48]
    done; local configs_added=0; # [cite: 48]
    for path in "${SHARES_TO_CREATE[@]}"; do # [cite: 49]
        if grep -qE "^\s*path\s*=\s*$path\s*$" /etc/samba/smb.conf; # [cite: 49]
        then echo -e "${GREEN}'$path' is already configured. Skipping.${NC}"; else # [cite: 50]
            local SHARE_NAME="$(basename "$path")"; # [cite: 50]
            echo "Adding share '[$SHARE_NAME]'..."; tee -a /etc/samba/smb.conf > /dev/null <<EOF

[$SHARE_NAME]
   comment = Custom Share ($path)
   path = $path
   browseable = yes
   read only = no
   guest ok = yes
   create mask = 0644
   directory mask = 0755
   force user = dietpi
EOF
            ((configs_added++)); # [cite: 51]
        fi # [cite: 52]
    done; if [ "$configs_added" -gt 0 ]; # [cite: 52]
    then # [cite: 53]
        echo "Attempting to restart Samba service..." # [cite: 53]
        systemctl restart smbd || true # [cite: 54]
        echo -e "${GREEN}Samba configuration complete.${NC}" # [cite: 54]
    else # [cite: 54]
        echo -e "${GREEN}No new changes were applied to Samba.${NC}" # [cite: 54]
    fi # [cite: 54]
}

# --- Execution Sequence ---
echo "Starting $CONTAINER_NAME interactive deployment..."; # [cite: 54]
check_dependencies; setup_folders; setup_network; create_compose # [cite: 55]
echo "Building container from /docker/$CONTAINER_NAME..." # [cite: 55]
if $DOCKER_CMD -f "/docker/$CONTAINER_NAME/docker-compose.yml" up -d; # [cite: 55]
then # [cite: 56]
    IP_ADDR=$(hostname -I | awk '{print $1}') # [cite: 56]
    setup_samba_share # [cite: 56]
    echo -e "\n${GREEN}--------------------${NC}" # [cite: 56]
    echo -e "${GREEN}Installation Complete!${NC}" # [cite: 56]
    echo -e "\n${GREEN}Deployment successful!${NC}" # [cite: 56]
    echo -e "${GREEN}Access MeTube at http://$IP_ADDR:$DEFAULT_PORT${NC}" # [cite: 56]
    echo -e "${GREEN}--------------------${NC}" # [cite: 56]
else # [cite: 56]
    echo -e "${RED}Docker Compose deployment failed.${NC}"; # [cite: 56]
    exit 1 # [cite: 57]
fi # [cite: 57]
