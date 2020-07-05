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

platform::os() {
  local os=""
  if platform::is_osx
  then
      os="macos"
  elif platform::is_linux && \
       [ -e "/etc/os-release" ]; then
      os="$(. /etc/os-release; printf "%s" "$ID")"
  else
      os="$(uname -s)"
  fi

  printf "%s" "$os"
}

platform::os_version() {
  local version=""

  if platform::is_osx; then
      version="$(sw_vers -productVersion)"
  elif [ -e "/etc/os-release" ]; then
      version="$(. /etc/os-release; printf "%s" "$VERSION_ID")"
  fi

  printf "%s" "$version"
}

platform::is_supported_version() {
  # shellcheck disable=SC2206
  declare -a v1=(${1//./ })
  # shellcheck disable=SC2206
  declare -a v2=(${2//./ })
  local i=""

  # Fill empty positions in v1 with zeros.
  for (( i=${#v1[@]}; i<${#v2[@]}; i++ )); do
    v1[i]=0
  done

  for (( i=0; i<${#v1[@]}; i++ )); do
    # Fill empty positions in v2 with zeros.
    if [[ -z ${v2[i]} ]]; then
        v2[i]=0
    fi

    # DEBUG: Wrapped in strings as seems like invalid syntax,
    # may have broken this.
    if (( "10#${v1[i]}" < "10#${v2[i]}" )); then
      return 1
    elif (( "10#${v1[i]}" > "10#${v2[i]}" )); then
      return 0
    fi
  done
}

platform::is_supported() {
  declare -r MINIMUM_MACOS_VERSION="10.10"
  declare -r MINIMUM_UBUNTU_VERSION="18.04"

  os_name="$(platform::os)"
  os_version="$(platform::os_version)"

  # Check if the OS is `macOS` and
  # it's above the required version.
  if [ "$os_name" == "macos" ]; then
    if platform::is_supported_version "$os_version" "$MINIMUM_MACOS_VERSION"; then
      return 0
    else
      printf "Sorry, this script is intended only for macOS %s+" "$MINIMUM_MACOS_VERSION"
    fi

  # Check if the OS is `Ubuntu` and
  # it's above the required version.
  elif [ "$os_name" == "ubuntu" ]; then
    if platform::is_supported_version "$os_version" "$MINIMUM_UBUNTU_VERSION"; then
      return 0
    else
      printf "Sorry, this script is intended only for Ubuntu %s+" "$MINIMUM_UBUNTU_VERSION"
    fi

  # - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  else
    printf "Sorry, this script is intended only for macOS and Ubuntu!"
  fi

  return 1
}

platform::relink() {
  local readonly original_path="$(which $1)"
  local readonly new_path="$(dirname "$original_path")/$2"
  sudo ln -s "$original_path" "$new_path"
}

platform::main_package_manager() {
  if platform::is_osx; then
    echo "brew"
  elif platform::command_exists apt; then
    echo "apt"
  elif platform::command_exists apt-get; then
    platform::relink "apt-get" "apt"
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

platform::main_package_args() {
  if [ "$(platform::main_package_manager)" == "apt"]; then
    echo "--allow-unauthenticated -qqy"
  else
    echo ""
  fi
}
