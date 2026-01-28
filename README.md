#all in one
sudo apt-get update && sudo apt-get install -y dos2unix samba && curl -sL https://raw.githubusercontent.com/wes1977fj/my-scripts/main/build_metube.sh | dos2unix | sudo bash

#just the install
curl -sL https://raw.githubusercontent.com/wes1977fj/my-scripts/main/build_metube.sh | dos2unix | sudo bash
