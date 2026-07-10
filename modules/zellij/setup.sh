# shellcheck shell=bash
# shellcheck source=/dev/null
. "$DOTFILES/scripts/core/main.sh"

# Per-host zellij theme: config.kdl selects `theme "host"`, and this links
# ~/.config/zellij/themes/host.kdl to the host-named theme file (falling back
# to default.kdl for hosts without one). ln -sfn makes it idempotent.
themes_src="$DOTFILES/modules/zellij/config/zellij/themes"
host_theme="$themes_src/$(hostname -s | tr '[:upper:]' '[:lower:]').kdl"
[ -f "$host_theme" ] || host_theme="$themes_src/default.kdl"

mkdir -p "$HOME/.config/zellij/themes"
ln -sfn "$host_theme" "$HOME/.config/zellij/themes/host.kdl"
log::result $? "linked zellij host theme (${host_theme##*/})"
