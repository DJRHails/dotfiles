. "$DOTFILES/scripts/core/main.sh"

pip() {
  install::with $1 $2 $3 "pip"
}
install::package "Python (3)" "python3"
install::with "setuptools (upgrade latest)" "setuptools" "--upgrade" "pip"
pip "pip (upgrade latest)" "pip" "--upgrade"

pip "Python (venv)" "virtualenv" ""
pip "Package (numpy)" "numpy" "--user"
pip "Package (scipy)" "scipy" "--user"
pip "Package (matplotlib)" "matplotlib" "--user"
pip "Package (ipython)" "ipython" "--user"
pip "Package (jupyter)" "jupyter" "--user"
pip "Package (pandas)" "pandas" "--user"
