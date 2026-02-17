. "$DOTFILES/scripts/core/main.sh"

if [ -d "/Applications/Docker.app" ]; then
  log::success "Docker Desktop"
else
  brew install --cask docker-desktop
  log::result $? "Docker Desktop"
fi

# Ensure Docker CLI is accessible
if ! command -v docker &>/dev/null; then
  log::info "Launching Docker.app to register CLI tools..."
  open -a Docker
  for _ in $(seq 1 15); do
    command -v docker &>/dev/null && break
    sleep 2
  done
  log::result $? "Docker CLI available"
else
  log::success "Docker CLI"
fi
