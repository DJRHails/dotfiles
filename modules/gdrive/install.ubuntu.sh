. "$DOTFILES/scripts/core/main.sh"

sudo add-apt-repository ppa:alessandro-strada/ppa
install::package "Google Drive OcamlFuse" "google-drive-ocamlfuse"

# Setup auth token
google-drive-ocamlfuse

# Mount to known location
DRIVE_MNT=$(echo "$PROJECTS" | cut -d ":" -f1)/drive.google.com
mkdir -p $DRIVE_MNT
google-drive-ocamlfuse $DRIVE_MNT
