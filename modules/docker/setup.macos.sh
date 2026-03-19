# shellcheck shell=bash
. "$DOTFILES/scripts/core/main.sh"

# Start Colima if not already running
if colima status &>/dev/null 2>&1; then
  log::success "Colima running"
else
  log::execute "colima start --arch aarch64 --vm-type vz --vz-rosetta --cpu 4 --memory 8" "Colima start"
fi

# Symlink docker socket to default path so tools find it automatically
DOCKER_SOCK="$HOME/.colima/default/docker.sock"
DEFAULT_SOCK="$HOME/.docker/run/docker.sock"

if [ -S "$DOCKER_SOCK" ]; then
  mkdir -p "$(dirname "$DEFAULT_SOCK")"
  if [ -S "$DEFAULT_SOCK" ] || [ -L "$DEFAULT_SOCK" ]; then
    rm -f "$DEFAULT_SOCK"
  fi
  ln -sf "$DOCKER_SOCK" "$DEFAULT_SOCK"
  log::success "Docker socket symlink"
else
  log::warning "Colima socket not found at $DOCKER_SOCK — start Colima first"
fi

# Set DOCKER_HOST in shell profile via env
DOCKER_HOST_LINE="export DOCKER_HOST=\"unix://$DEFAULT_SOCK\""
DOCKER_ENV="$HOME/.docker/env"
mkdir -p "$(dirname "$DOCKER_ENV")"
echo "$DOCKER_HOST_LINE" > "$DOCKER_ENV"
log::success "Docker host env ($DOCKER_ENV)"
