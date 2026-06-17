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
  # init-templatedir only populates the directory — git must also be pointed at
  # it via init.templateDir, or new clones silently get no hooks. That setting
  # is machine-local, so it lives in gitconfig.local (see modules/git/gitconfig),
  # which the git module generates before this script runs.
  if [ -f "$HOME/.gitconfig.local" ]; then
    # Write the EXPANDED absolute path, not a literal '~/.git-hooks'. git expands ~
    # in init.templateDir, but prek (the pre-commit drop-in our repos run) does NOT
    # — a literal tilde makes `prek init-templatedir` die `os error 2` seeding the
    # bogus path. .gitconfig.local is machine-local (regenerated per host here), so
    # an absolute path is correct and keeps both git and prek happy.
    git config --file "$HOME/.gitconfig.local" init.templateDir "$HOME/.git-hooks"
    log::success "pre-commit templatedir initialised at $HOME/.git-hooks"
  else
    # shellcheck disable=SC2088 # ~ is display text in a log message, not a path to expand
    log::warning "~/.gitconfig.local missing — run the git module, then set init.templateDir=~/.git-hooks"
  fi
fi
