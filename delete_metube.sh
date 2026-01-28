#!/bin/bash

# This script ensures the 'metube' container and '/docker/metube' directory are removed.
# It handles cases where the directory, compose file, or container may not exist.

echo "Starting cleanup process for metube..."

# --- Step 1: Attempt graceful shutdown with Docker Compose ---
# If the docker-compose.yml file exists, use it to stop and remove containers.
if [ -f "/docker/metube/docker-compose.yml" ]; then
    echo "Found /docker/metube/docker-compose.yml. Running 'docker compose down'..."
    (cd /docker/metube && docker compose down)
    echo "Docker Compose shutdown complete."
fi

# --- Step 2: Manually stop and remove the container by name ---
# This is a fallback in case there was no compose file, or if the container
# was created manually.

# Check if a container named 'metube' is running
if [ "$(docker ps -q -f name=^metube$)" ]; then
    echo "Container 'metube' is running. Stopping it now..."
    docker stop metube
else
    echo "No running container named 'metube' found."
fi

# Check if a stopped container named 'metube' exists and remove it
if [ "$(docker ps -aq -f name=^metube$)" ]; then
    echo "Container 'metube' exists. Removing it now..."
    docker rm metube
else
    echo "No container named 'metube' found to remove."
fi

# --- Step 3: Remove the directory ---
# Finally, remove the directory if it exists.
if [ -d "/docker/metube" ]; then
    echo "Removing directory /docker/metube..."
    rm -rf /docker/metube
    echo "Successfully removed /docker/metube."
else
    echo "Directory /docker/metube does not exist."
fi

echo "Metube cleanup script finished."

