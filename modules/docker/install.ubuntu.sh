# Setup repo, depends on os: https://docs.docker.com/engine/install
# Install Docker engine: `docker-ce docker-ce-cli containerd.io`
# sudo systemctl start docker
# sudo usermod -aG docker `whoami`

platform::sudo apt-get install \
    ca-certificates \
    curl \
    gnupg \
    lsb-release

curl -fsSL https://download.docker.com/linux/ubuntu/gpg | platform::sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

 echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | platform::sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

platform::sudo apt-get update

platform::sudo apt-get install docker-ce docker-ce-cli containerd.io

platform::sudo groupadd docker
platform::sudo usermod -aG docker $USER
newgrp docker