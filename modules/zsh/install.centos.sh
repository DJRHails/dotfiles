. "$DOTFILES/scripts/core/main.sh"

# Upgrade zsh by building
install::package "Git" "git"
install::package "NCurses development" "ncurses-devel"
install::package "GCC" "gcc"
install::package "Autoconf" "autoconf"
install::package "Man" "man"
git clone https://github.com/zsh-users/zsh.git /tmp/zsh
cd /tmp/zsh
./Util/preconfig
./configure
sudo make -j 20 install

# Cargo
install::package "Cargo & Rust" "cargo"

# Build fd
git clone https://github.com/sharkdp/fd /tmp/fd
cd /tmp/fd
cargo build
cargo install