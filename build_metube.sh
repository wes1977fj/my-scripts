#!/bin/bash
# The definitive, fully interactive installer script.

# Exit immediately if a command exits with a non-zero status.
set -e

# --- Bash Version Check ---
if ((BASH_VERSINFO[0] < 4)); then
    echo -e "\033[0;31mError: This script requires Bash version 4.0 or higher.\033[0m" >&2; exit 1
fi

# --- Container-Specific Configuration ---
CONTAINER_NAME="metube"; DOCKER_IMAGE="ghcr.io/alexta69/metube:latest"; DEFAULT_PORT="5009"
declare -A VOLUME_MAPPINGS; VOLUME_MAPPINGS["/media/ytdl"]="/downloads"

# --- Dynamic Variables ---
DEFAULT_NETWORK="bridge"

# --- Colors for output ---
GREEN='\033[0;32m'; RED='\033[0;31m'; NC='\033[0m'

# --- Pre-flight Checks (Compacted for Brevity) ---
if [[ $EUID -ne 0 ]]; then echo -e "${RED}Run as root.${NC}"; exit 1; fi
if ! [ -t 0 ] && ! [ -r /dev/tty ]; then echo -e "${RED}No terminal.${NC}" >&2; exit 1; fi
if [[ -n "$SUDO_USER" ]]; then RUN_USER="$SUDO_USER"; else RUN_USER=$(id -un 1000 2>/dev/null || echo "user"); fi
RUN_UID=$(id -u "$RUN_USER" 2>/dev/null || echo "1000"); RUN_GID=$(id -g "$RUN_USER" 2>/dev/null || echo "1000")
echo "Running installer for user: $RUN_USER (UID: $RUN_UID, GID: $RUN_GID)"

# --- Core Functions ---
check_dependencies() { echo "Checking dependencies..."; if ! command -v docker &> /dev/null; then if command -v dietpi-software &> /dev/null; then dietpi-software install 162 134; else curl -fsSL https://get.docker.com | sh; usermod -aG docker "$RUN_USER"; fi; fi; if docker compose version &> /dev/null; then DOCKER_CMD="docker compose"; elif command -v docker-compose &> /dev/null; then DOCKER_CMD="docker-compose"; else echo -e "${RED}Docker Compose not found.${NC}"; exit 1; fi; }
setup_folders() { echo "Creating directories..."; mkdir -p "/docker/$CONTAINER_NAME"; for host_path in "${!VOLUME_MAPPINGS[@]}"; do mkdir -p "$host_path"; done; chown -R "$RUN_USER":"$RUN_USER" "/docker/$CONTAINER_NAME" "${!VOLUME_MAPPINGS[@]}"; }

# --- NEW Menu-Driven setup_network function ---
setup_network() {
    echo # Blank line for readability
    echo "Please select the Docker network for the container."
    mapfile -t nets < <(docker network ls --format "{{.Name}}")
    local i=1; local -A net_options
    for net in "${nets[@]}"; do
        # Don't list the default network in the numbered options
        if [[ "$net" != "$DEFAULT_NETWORK" ]]; then
            echo "  $i) $net"; net_options[$i]="$net"; ((i++))
        fi
    done
    echo "  c) Create a new network"
    echo "  d) Done (use default: '$DEFAULT_NETWORK')"

    local sel; read -p "Select an option: " sel < /dev/tty

    case "$sel" in
        [dD])
            SELECTED_NET="$DEFAULT_NETWORK"
            ;;
        [cC])
            read -p "  Enter new network name: " new_net < /dev/tty
            if [[ -z "$new_net" ]]; then
                echo -e "${RED}Network name cannot be empty. Using default.${NC}"
                SELECTED_NET="$DEFAULT_NETWORK"
            elif docker network inspect "$new_net" &>/dev/null; then
                echo "Network '$new_net' already exists."
                SELECTED_NET="$new_net"
            else
                echo "Creating network '$new_net'..."
                docker network create "$new_net"
                SELECTED_NET="$new_net"
            fi
            ;;
        *)
            if [[ -n "${net_options[$sel]}" ]]; then
                SELECTED_NET="${net_options[$sel]}"
            else
                echo -e "${RED}Invalid selection. Using default network '$DEFAULT_NETWORK'.${NC}"
                SELECTED_NET="$DEFAULT_NETWORK"
            fi
            ;;
    esac
    echo -e "Using network: ${GREEN}$SELECTED_NET${NC}"
}

create_compose() {
    echo "Writing docker-compose.yml...";
    local net_cfg="" svc_net_cfg="" vol_blk=""
    if [[ "$SELECTED_NET" != "bridge" ]]; then net_cfg=$(printf "\nnetworks:\n  app_net:\n    external: true\n    name: $SELECTED_NET"); svc_net_cfg=$(printf "\n    networks:\n      - app_net"); fi
    for host_path in "${!VOLUME_MAPPINGS[@]}"; do vol_blk+=$(printf "\n      - %s:%s" "$host_path" "${VOLUME_MAPPINGS[$host_path]}"); done
    tee "/docker/$CONTAINER_NAME/docker-compose.yml" > /dev/null <<EOF
services:
  $CONTAINER_NAME:
    image: $DOCKER_IMAGE
    container_name: $CONTAINER_NAME
    restart: unless-stopped
    ports:
      - "$DEFAULT_PORT:8081"
    volumes:${vol_blk}
${svc_net_cfg}
    environment:
      - UID=$RUN_UID
      - GID=$RUN_GID
      - UMASK=022
      - DOWNLOAD_DIR=/downloads
      - OUTPUT_TEMPLATE=%(title)s.%(ext)s
${net_cfg}
EOF
    chown "$RUN_USER":"$RUN_USER" "/docker/$CONTAINER_NAME/docker-compose.yml"
}

setup_samba_share() {
    if ! command -v smbd &> /dev/null; then echo "Samba not installed. Skipping."; return; fi
    local samba_choice; read -p "Configure Samba shares? (y/n): " samba_choice < /dev/tty; if [[ $samba_choice != [yY] ]]; then return; fi
    local -a SHARES_TO_CREATE=(); while true; do
        echo; local prompt="Which directory would you like to share?"; local exit_prompt="n) None / Done"; if [ ${#SHARES_TO_CREATE[@]} -gt 0 ]; then prompt="Share another directory?"; exit_prompt="n) Done"; fi
        local -A unique_paths; unique_paths["/docker"]=1; for host_path in "${!VOLUME_MAPPINGS[@]}"; do unique_paths["$host_path"]=1; local parent_path; parent_path=$(dirname "$host_path"); if [[ "$parent_path" != "/" ]]; then unique_paths["$parent_path"]=1; fi; done
        local -a SHARE_CANDIDATES; mapfile -t SHARE_CANDIDATES < <(for path in "${!unique_paths[@]}"; do echo "$path"; done | sort -u);
        echo "$prompt"; local i=1; local -A share_options; for path in "${SHARE_CANDIDATES[@]}"; do echo "  $i) $path"; share_options[$i]="$path"; ((i++)); done
        echo "  c) Custom path"; echo "  $exit_prompt"; local selection; read -p "Select an option: " selection < /dev/tty
        local SELECTED_PATH=""; if [[ $selection == [nN] ]]; then break; elif [[ $selection == [cC] ]]; then read -p "  Enter absolute path: " CUSTOM_PATH < /dev/tty; if [[ -z "$CUSTOM_PATH" || "$CUSTOM_PATH" != /* ]]; then echo -e "${RED}Invalid path. Try again.${NC}"; continue; fi; SELECTED_PATH="$CUSTOM_PATH"; elif [[ -n "${share_options[$selection]}" ]]; then SELECTED_PATH="${share_options[$selection]}"; else echo -e "${RED}Invalid selection. Try again.${NC}"; continue; fi
        if [[ " ${SHARES_TO_CREATE[*]} " =~ " ${SELECTED_PATH} " ]]; then echo -e "${GREEN}Path '$SELECTED_PATH' is already in the list.${NC}"; else SHARES_TO_CREATE+=("$SELECTED_PATH"); echo -e "${GREEN}Added '$SELECTED_PATH' to the list.${NC}"; fi
    done; while true; do
        if [ ${#SHARES_TO_CREATE[@]} -eq 0 ]; then echo -e "${GREEN}No new shares selected.${NC}"; return; fi
        echo -e "\n--- Confirmation ---"; echo "The following shares are ready:"; local i=1; for path in "${SHARES_TO_CREATE[@]}"; do echo "  $i) $path"; ((i++)); done
        read -p "Action: (p)roceed, (r)emove, (c)ancel: " action < /dev/tty
        case "$action" in [pP]) echo "Proceeding with installation..."; break;; [rR]) read -p "Enter # to remove: " num < /dev/tty; if ! [[ "$num" =~ ^[0-9]+$ ]] || (( num < 1 || num > ${#SHARES_TO_CREATE[@]} )); then echo -e "${RED}Invalid number.${NC}"; else local idx=$((num - 1)); local item="${SHARES_TO_CREATE[$idx]}"; unset "SHARES_TO_CREATE[$idx]"; SHARES_TO_CREATE=("${SHARES_TO_CREATE[@]}"); echo -e "${GREEN}Removed '$item'.${NC}"; fi;; [cC]) echo -e "${RED}Samba installation cancelled.${NC}"; return;; *) echo -e "${RED}Invalid action. Please choose 'p', 'r', or 'c'.${NC}";; esac
    done; local configs_added=0; for path in "${SHARES_TO_CREATE[@]}"; do
        if grep -qE "^\s*path\s*=\s*$path\s*$" /etc/samba/smb.conf; then echo -e "${GREEN}'$path' is already configured. Skipping.${NC}"; else
            local SHARE_NAME="$(basename "$path")"; echo "Adding share '[$SHARE_NAME]'..."; tee -a /etc/samba/smb.conf > /dev/null <<EOF

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
            ((configs_added++)); fi
    done; if [ "$configs_added" -gt 0 ]; then echo "Attempting to restart Samba service..."; systemctl restart smbd || true; echo -e "${GREEN}Samba configuration complete.${NC}"; else echo -e "${GREEN}No new changes were applied to Samba.${NC}"; fi
}

# --- Execution Sequence ---
echo "Starting $CONTAINER_NAME interactive deployment..."; check_dependencies; setup_folders; setup_network; create_compose
echo "Building container from /docker/$CONTAINER_NAME..."
if $DOCKER_CMD -f "/docker/$CONTAINER_NAME/docker-compose.yml" up -d; then
    IP_ADDR=$(hostname -I | awk '{print $1}')
    setup_samba_share
    echo -e "\n${GREEN}--------------------${NC}"
    echo -e "${GREEN}Installation Complete!${NC}"
    echo -e "\n${GREEN}Deployment successful!${NC}"
    echo -e "${GREEN}Access MeTube at http://$IP_ADDR:$DEFAULT_PORT${NC}"
    echo -e "${GREEN}--------------------${NC}"
else
    echo -e "${RED}Docker Compose deployment failed.${NC}"; exit 1
fi
