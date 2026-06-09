# shellcheck shell=bash
. "$DOTFILES/scripts/core/main.sh"
install::package "Python (3)" "python3"

if ! cmd_exists uv; then
  log::info "Installing uv..."
  UV_INSTALLER="$(mktemp)"
  curl -LsSf https://astral.sh/uv/install.sh -o "$UV_INSTALLER" && sh "$UV_INSTALLER"
  log::result $? "uv installed"
  rm -f "$UV_INSTALLER"
else
  log::success "uv already installed"
fi

# uv installs itself + its tools into ~/.local/bin; ensure it's on PATH so the
# tool installs below resolve `uv` during a fresh bootstrap (the curl installer
# only edits shell rc files, not the live PATH).
[[ ":$PATH:" != *":$HOME/.local/bin:"* ]] && export PATH="$HOME/.local/bin:$PATH"

# UV tools (replaces pip3 install which fails with PEP 668).
install::uv_tool "ruff" "ruff"
install::uv_tool "ty" "ty"
install::uv_tool "pip-audit" "pip-audit"
install::uv_tool "ipython" "ipython"
install::uv_tool "jupyter" "jupyter" "jupyter-core"
install::uv_tool "pre-commit" "pre-commit"

if cmd_exists pre-commit; then
  mkdir -p "$HOME/.git-hooks"
  pre-commit init-templatedir "$HOME/.git-hooks" >/dev/null
  log::success "pre-commit templatedir initialised at ~/.git-hooks"
fi
