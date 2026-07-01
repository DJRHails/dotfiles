#!/usr/bin/env bash

##? Setup .files and install asked for modules
##?
##? USAGE:
##?    ./bootstrap.sh [FLAGS] [<modules>...]
##? 
##? FLAGS:
##?     -y, --yes   Skip any interactive questions asked during setup (will not add all modules)
##?     -A, --all   Run all modules found in $DOTFILES/modules.
##?     -c, --cli   Install only cli modules, perfect for servers.
##?     -h, --help  Show this help
##?
##? ARGS:
##?     <modules>...  the modules to install (optional)

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Move to the correct directory for duration of this script
cd "$(dirname "${BASH_SOURCE[0]}")" \
  || exit 1
DOTFILES=$(pwd -P)
readonly DOTFILES

# Vendored-skill submodules (e.g. graph-design → DJRHails/graphs): a clone
# without --recurse-submodules leaves them empty, so the skills' symlinked
# SKILL.md/examples dangle. Initialise each missing one independently and
# tolerate failures — some submodules (modules/askllm) are private/dead and
# must not abort the others or the bootstrap (e.g. inside image builds).
if command -v git >/dev/null 2>&1 && [ -e .git ] \
  && git submodule status 2>/dev/null | grep -q '^-'; then
  echo "Initialising vendored submodules…"
  # for-loop over a pre-collected list (not `| while read`): a failing clone
  # inside the loop body would otherwise consume the remaining piped stdin
  # and silently skip the later submodules.
  sm_paths=$(git config --file .gitmodules --get-regexp 'submodule\..*\.path' \
    | awk '{print $2}')
  for sm_path in $sm_paths; do
    git submodule status -- "$sm_path" 2>/dev/null | grep -q '^-' || continue
    git submodule update --init --depth 1 -- "$sm_path" </dev/null \
      || echo "warning: submodule $sm_path failed to initialise; skipping" >&2
  done
fi

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

parse_args() {
     while [[ $# -gt 0 ]]
     do
        case $1 in
          -y|--yes)
            skipQuestions=true
          ;;
          -A|--all)
            allModules=true
          ;;
          -c|--cli)
            scanned_valid_modules+=("$DOTFILES/modules/zsh" "$DOTFILES/modules/ssh" "$DOTFILES/modules/git" "$DOTFILES/modules/python" "$DOTFILES/modules/node" "$DOTFILES/modules/piknik" "$DOTFILES/modules/tailscale" "$DOTFILES/modules/cloudflared" "$DOTFILES/modules/claude" "$DOTFILES/modules/dotfiles-autoupdate")
          ;;
          *)
            if [ -d "$DOTFILES/modules/$1" ]; then
              scanned_valid_modules+=("$DOTFILES/modules/$1")
            else
              echo "[bootstrap] Warning: module '$1' not found in $DOTFILES/modules/" >&2
            fi
          ;;
        esac
        shift
    done
}

cmd_exists() {
    command -v "$1" &> /dev/null
}

run() {
  local module_dir=$1
  local script_name=$2
  local src="$1/$2"
  if [ -f "$src" ]; then
    log::subheader "Executing ${script_name%.*} for '${module_dir##*/}'"
    # Subshell: isolate the installer's set -e/-u/pipefail, exit, cd and
    # traps from this shell, while $DOTFILES and the log::/install::
    # helpers stay visible. Do not flatten to `. "$src"` — one leaked
    # `set -u` aborts the whole --all run on the next 2-arg
    # install::package call.
    # shellcheck source=/dev/null
    ( . "$src" )
    log::result $? "${script_name%.*} completed"
  fi
}

create_links() {
  local module_dir="$1"
  local symlink_file="$module_dir/symlinks.conf"
  # Read by link::extract_and_link (scripts/link.sh) via dynamic scoping.
  # shellcheck disable=SC2034
  local overwrite_all=false backup_all=$skipQuestions skip_all=false

  if [ -f $symlink_file ]; then
    log::subheader "Creating symbolic links for '${module_dir##*/}'"
    link::extract_and_link "$symlink_file"
  fi
}

main() {
  # Load utilities
  . "scripts/core/main.sh"
  . "scripts/scan.sh"
  . "scripts/link.sh"

  # Check if we need help
  doc::maybe_help "$@"

  # Check for arguments
  scanned_valid_modules=()
  # Read by scan::find_valid_modules (scripts/scan.sh).
  # shellcheck disable=SC2034
  allModules=false
  skipQuestions=false
  parse_args "$@"

  # Splash Screen
  log::splash " Bootstrapping .files from $DOTFILES"

  # Verify OS
  log::header "Verify OS verion\n"
  # os_name/os_version are assigned by platform::is_supported.
  # shellcheck disable=SC2154
  platform::is_supported && log::success "$os_name with v$os_version is valid"


  # Cache sudo credentials early — before platform bootstrap or
  # interactive module selection can introduce delays that expire them.
  platform::ask_for_sudo

  # Platform-specific bootstrap (Homebrew, Bash upgrade, apt, etc.).
  # Sourced in THIS shell — not via run()'s subshell — because it must
  # mutate the bootstrap shell: brew shellenv PATH and the Bash 4+ re-exec.
  # BOOTSTRAP_ARGS is read by scripts/bootstrap.macos.sh on that re-exec.
  # shellcheck disable=SC2034
  BOOTSTRAP_ARGS=("$@")
  local platform_bootstrap
  platform_bootstrap="$DOTFILES/scripts/bootstrap.$(platform::os).sh"
  if [ -f "$platform_bootstrap" ]; then
    log::subheader "Executing bootstrap.$(platform::os) for 'scripts'"
    # shellcheck source=/dev/null
    . "$platform_bootstrap"
    log::result $? "bootstrap.$(platform::os) completed"
  fi

  # Verify Bash 4+ (platform bootstrap should have installed it)
  log::header "Verify Bash Version\n"
  if [ "${BASH_VERSINFO:-0}" -ge 4 ]; then
    log::success "Bash ${BASH_VERSINFO[0]} (associative arrays supported)"
  else
    log::error "Bash ${BASH_VERSINFO:-unknown} is too old (need 4+)"
    exit 1
  fi

  # Grab modules
  scan::find_valid_modules

  log::header "Installing $(log::bold "${#scanned_valid_modules[@]} modules")"

  for idx in "${!scanned_valid_modules[@]}"
  do
    local module_dir="${scanned_valid_modules[$idx]}"
    if [[ ! -z $module_dir ]]; then
      log::header "$((idx+1)). Running '${module_dir##*/}'"
      create_links "$module_dir"
      run "$module_dir" "install.sh"
      run "$module_dir" "install.$(platform::os).sh"
      run "$module_dir" "setup.sh"
      run "$module_dir" "setup.$(platform::os).sh"
      if [[ ! -f "$module_dir/install.sh" && ! -f "$module_dir/install.$(platform::os).sh" ]]; then
        log::warning "No installer found for '${module_dir##*/}' on $(platform::os)"
      fi
    fi
  done

  . "scripts/restart.sh"
}

main "$@"
