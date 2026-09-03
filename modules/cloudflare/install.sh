# shellcheck shell=bash
. "$DOTFILES/scripts/core/main.sh"

# Cloudflare's unified `cf` CLI (DNS records, zones, R2, accounts, tokens — the
# whole API surface, JSON out). Same npm-prefix logic as modules/pi: a
# user-writable prefix needs no sudo; a system-owned one (bare NodeSource
# install) does, and mixing the two leaves divergent copies shadowed by PATH.
npm_prefix="$(npm config get prefix 2>/dev/null)"
if [[ -w "$npm_prefix" ]]; then
  sudo_npm="npm"
else
  sudo_npm="$(platform::sudo_prefix)npm"
fi

if platform::command_exists "cf"; then
  log::success "cf"
else
  log::execute "$sudo_npm install -g cf" "cf (Cloudflare CLI)"
fi

# Auth is a long-lived user API token in this module's gitignored .env, which
# the `cf` wrapper in aliases.zsh scopes to each invocation. Absent, `cf` falls
# back to its OAuth profiles (`cf auth login`), which expire.
module_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$module_dir/.env" ]]; then
  log::success "cf token (modules/cloudflare/.env)"
else
  log::warning "no modules/cloudflare/.env — write CLOUDFLARE_API_TOKEN=<token> there (mode 600) for token auth"
fi
