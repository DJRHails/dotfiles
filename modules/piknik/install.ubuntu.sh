. "$DOTFILES/scripts/core/main.sh"

wget https://github.com/jedisct1/piknik/releases/download/0.10.1/piknik-linux_x86_64-0.10.1.tar.gz
tar -xvf piknik-linux_x86_64-0.10.1.tar.gz
platform::sudo mv linux-x86_64/piknik /usr/local/bin
rm -rf piknik-linux_x86_64-0.10.1.tar.gz linux-x86_64
rm -rf linux-x86_64