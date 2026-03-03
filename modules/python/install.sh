. "$DOTFILES/scripts/core/main.sh"
install::package "Python (3)" "python3"

if ! cmd_exists uv; then
  log::info "Installing uv..."
  curl -LsSf https://astral.sh/uv/install.sh | sh
  log::result $? "uv installed"
else
  log::success "uv already installed"
fi

# UV tools (replaces pip3 install which fails with PEP 668)
install::with "uv tool" "ruff" "ruff" ""
install::with "uv tool" "ty" "ty" ""
install::with "uv tool" "pip-audit" "pip-audit" ""
install::with "uv tool" "ipython" "ipython" ""
install::with "uv tool" "jupyter" "jupyter" ""
