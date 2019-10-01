link() {
  declare -n links="$1"
  links+=(
    ["~/.gitconfig"]="gitconfig"
    ["~/.gitignore"]="gitignore"
    ["~/.gitconfig.local"]="gitconfig.local"
  )
}
