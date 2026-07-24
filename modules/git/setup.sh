#!/usr/bin/env bash

setup_gitconfig () {
  local local_git_config=modules/git/gitconfig.local
  if ! [ -f $local_git_config ]
  then
    # git_credential='cache'
    if platform::is_osx
    then
      git_credential='osxkeychain'
    fi

    prompt::author

    sed -e "s/AUTHORNAME/$GIT_AUTHOR_NAME/g" \
      -e "s/AUTHOREMAIL/$GIT_AUTHOR_EMAIL/g" \
      $local_git_config.tmpl > $local_git_config

    # Only record a credential helper when one was actually chosen. An empty
    # `helper =` line would reset git's accumulated helper list (gitconfig.local
    # is included last), wiping e.g. gh's helper on Linux where git_credential
    # is unset.
    if [ -n "${git_credential:-}" ]
    then
      git config --file "$local_git_config" credential.helper "$git_credential"
    fi

    log::success "generated $local_git_config"
  else
    log::success 'skipped gitconfig generation as present'
  fi
}


. "$DOTFILES/scripts/core/main.sh"
. "$DOTFILES/modules/git/setup.prompt.sh"
. "$DOTFILES/modules/git/setup.github.sh"
setup_gitconfig

install::package "Git LFS" "git-lfs"
install::release_binary "sops" "sops" "getsops/sops" \
  "https://github.com/getsops/sops/releases/download/@TAG@/sops-@TAG@.linux.@ARCH_DEB@"
# Glassine (sops-backed git encryption, replaces transcrypt): a single script
# with no release artifacts — install straight from the repo's main branch.
if platform::command_exists glassine; then
  log::success "Glassine"
else
  mkdir -p "$HOME/.local/bin"
  log::execute "curl -fsSL https://raw.githubusercontent.com/DJRHails/glassine/main/glassine -o \$HOME/.local/bin/glassine && chmod +x \$HOME/.local/bin/glassine" "Glassine"
fi
github::install_cli

# Hook enforcement: point init.templateDir at ~/.git-template and populate it
# with prek's pre-commit shim, so every future clone/init gets hooks — the
# shim no-ops in repos without a pre-commit config. Then install hooks for
# this repo itself, which already has one. templateDir goes in gitconfig.local
# as an absolute path: git would tilde-expand `~/.git-template`, but prek's
# init-template-dir check reads the configured value literally.
if platform::command_exists prek; then
  git config --file "$DOTFILES/modules/git/gitconfig.local" \
    init.templateDir "$HOME/.git-template"
  prek init-template-dir "$HOME/.git-template" > /dev/null 2>&1
  log::result $? "prek template dir (~/.git-template)"
  (cd "$DOTFILES" && prek install > /dev/null 2>&1)
  log::result $? "prek install (.files)"
else
  log::warning "prek not on PATH (rust module installs it); skipping git hook setup"
fi

if [ "$skipQuestions" != true ]; then
  feedback::ask_for_confirmation "Do you want to setup github?"
  if feedback::answer_is_yes
  then
    install::package "GPG" "gpg"
    github::setup
  fi
fi