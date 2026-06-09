# shellcheck shell=bash
. "$DOTFILES/scripts/core/main.sh"

platform::sudo add-apt-repository -y ppa:alessandro-strada/ppa
install::package "Google Drive OcamlFuse" "google-drive-ocamlfuse"

# Auth + mount need a browser OAuth flow, so they can't run during bootstrap
DRIVE_MNT=$(echo "$PROJECTS" | cut -d ":" -f1)/drive.google.com
log::warning "Google Drive is installed but not mounted (OAuth setup is interactive)"
log::info "To finish: run 'google-drive-ocamlfuse' once to authorise in your browser,"
log::info "then mount with: mkdir -p \"$DRIVE_MNT\" && google-drive-ocamlfuse \"$DRIVE_MNT\""
