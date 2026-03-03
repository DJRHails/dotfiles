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

# Ensure Docker Compose plugin is available
# Docker Desktop bundles compose but only symlinks it on first launch.
# If Docker Desktop hasn't been started, the plugin is missing.
plugins_src="/Applications/Docker.app/Contents/Resources/cli-plugins"
plugins_dst="$HOME/.docker/cli-plugins"
if docker compose version &>/dev/null; then
  log::success "Docker Compose"
elif [ -f "$plugins_src/docker-compose" ]; then
  mkdir -p "$plugins_dst"
  ln -sf "$plugins_src/docker-compose" "$plugins_dst/docker-compose"
  log::result $? "Docker Compose (symlinked)"
else
  log::warn "Docker Compose plugin not found"
fi
