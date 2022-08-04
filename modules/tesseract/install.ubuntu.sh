. "$DOTFILES/scripts/core/main.sh"


sudo add-apt-repository ppa:alex-p/tesseract-ocr-devel
sudo apt update

install::package "Tesseract" "tesseract-ocr"
install::package "Gnome Screenshot (screenshot cli)" "gnome-screenshot"


