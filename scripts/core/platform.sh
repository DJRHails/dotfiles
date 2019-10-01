#!/usr/bin/env bash

platform::command_exists() {
   type "$1" &>/dev/null
}

platform::is_osx() {
   [[ $(uname -s) == "Darwin" ]]
}

platform::is_linux() {
   [[ $(uname -s) == "Linux" ]]
}

platform::main_package_manager() {
   if platform::is_osx; then
      echo "brew"
   elif platform::command_exists apt; then
      echo "apt"
   elif platform::command_exists apt-get; then
      local readonly apt_get_path="$(which apt-get)"
      local readonly apt_path="$(echo "$apt_get_path" | sed 's/-get//')"
      sudo ln -s "$apt_get_path" "$apt_path"
      echo "apt"
   elif platform::command_exists yum; then
      echo "yum"
   elif platform::command_exists dnf; then
      echo "dnf"
   elif platform::command_exists apk; then
      echo "apk"
   else
      echo "brew"
   fi
}
