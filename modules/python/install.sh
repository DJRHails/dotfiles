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

# Hook enforcement belongs to the git module, which seeds prek's template dir at
# ~/.git-template. This module used to ALSO run `pre-commit init-templatedir
# ~/.git-hooks` and point init.templateDir there — it runs after the git module,
# so it won the last write and every new clone got legacy pre-commit hooks
# instead of prek's. Worse, the ~/.git-hooks setup came with a global
# core.hooksPath, which makes `prek install` refuse outright. prek is a drop-in
# replacement for the `pre-commit` binary, so there is nothing to keep here.
