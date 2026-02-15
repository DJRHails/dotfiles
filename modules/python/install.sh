. "$DOTFILES/scripts/core/main.sh"
install::package "Python (3)" "python3"

if ! cmd_exists uv; then
  log::info "Installing uv..."
  curl -LsSf https://astral.sh/uv/install.sh | sh
  log::result $? "uv installed"
else
  log::success "uv already installed"
fi
install::with "pip3" "setuptools (upgrade latest)" "setuptools" "--upgrade"
install::with "pip3" "pip (upgrade latest)" "pip" "--upgrade"

install::with "pip3" "Python (venv)" "virtualenv" ""
install::with "pip3" "Package (numpy)" "numpy" "--user"
install::with "pip3" "Package (scipy)" "scipy" "--user"
install::with "pip3" "Package (matplotlib)" "matplotlib" "--user"
install::with "pip3" "Package (ipython)" "ipython" "--user"
install::with "pip3" "Package (jupyter)" "jupyter" "--user"
install::with "pip3" "Package (pandas)" "pandas" "--user"

# UV tools
install::with "uv tool" "ruff" "ruff" ""
install::with "uv tool" "ty" "ty" ""
install::with "uv tool" "pip-audit" "pip-audit" ""
