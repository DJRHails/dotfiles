#!/usr/bin/env bash
. "$DOTFILES/scripts/core/main.sh"

# Exit-node advertisement is opt-in: run bootstrap with TAILSCALE_EXIT_NODE=1
# to advertise this machine as an exit node (and accept subnet routes).

# 'tailscale status --json' exits non-zero only when the daemon is unreachable;
# plain 'tailscale status' also fails when merely logged out.
if ! tailscale_status_json="$(tailscale status --json 2>/dev/null)"; then
  log::warning "Tailscale daemon not running — start tailscaled, then re-run this module"
  return 0
fi

tailscale_backend_state="$(printf '%s\n' "$tailscale_status_json" \
  | sed -n 's/.*"BackendState":[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)"

case "$tailscale_backend_state" in
  NeedsLogin)
    log::info "Tailscale is logged out — run 'tailscale up' to authenticate"
    ;;
  Stopped)
    log::info "Tailscale is stopped — run 'tailscale up' to connect"
    ;;
  Running)
    if [ "${TAILSCALE_EXIT_NODE:-0}" = "1" ]; then
      # 'tailscale set' changes flags idempotently; re-running 'up' errors when
      # other flags already differ from the defaults.
      platform::sudo tailscale set --advertise-exit-node --accept-routes
      log::result $? "Tailscale advertising as exit node"
    else
      log::info "Tailscale running (set TAILSCALE_EXIT_NODE=1 to advertise as exit node)"
    fi
    ;;
  *)
    log::warning "Tailscale backend state '$tailscale_backend_state' — resolve manually, then re-run this module"
    ;;
esac

unset tailscale_status_json tailscale_backend_state
