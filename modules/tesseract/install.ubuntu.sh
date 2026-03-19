. "$DOTFILES/scripts/core/main.sh"


platform::sudo add-apt-repository ppa:alex-p/tesseract-ocr-devel
platform::sudo apt update

install::package "Tesseract" "tesseract-ocr"
install::package "Gnome Screenshot (screenshot cli)" "gnome-screenshot"


