# 4. Create Docker Compose File
create_compose() {
    echo "Writing docker-compose.yml..."
    
    # If the user selected 'bridge', we need a simpler compose file
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
        # If using a custom network, we keep the network logic
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
