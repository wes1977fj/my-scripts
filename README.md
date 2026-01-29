#The script will install it in a docker container using docker compose.  I've only tested it on an OrangePi running Dietpi OS.  Use at your own risk!!!  It creates /media/ytdl folder then makes a docker-compose.yml file and then builds and starts you container verify other stuff on the way.  It is somewhat customizable.  I haven't tested it alot and I know there is some Docker Network issues.  Right now no matter which selection you pick for network it puts it in metube_default network.  Not really an issue for most people cause the port is mapped to the host. 
curl -s https://raw.githubusercontent.com/wes1977fj/my-scripts/refs/heads/main/build_metubeV2.sh | bash




#I also made a script to remove it.
curl -s https://raw.githubusercontent.com/wes1977fj/my-scripts/refs/heads/main/delete_metube.sh | bash

#Do an update if needed
cd /docker/metube && docker compose up -d --pull always


















#test stuff

sudo apt-get update && sudo apt-get install -y dos2unix samba && curl -sL https://raw.githubusercontent.com/wes1977fj/my-scripts/main/build_metubeV2_1.sh | dos2unix | sudo bash


#just the install

curl -sL https://raw.githubusercontent.com/wes1977fj/my-scripts/main/build_metube.sh | dos2unix | sudo bash
