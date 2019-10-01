#!/usr/bin/env zsh

source $ZPLUG_HOME/init.zsh

# Bundles from oh-my-zsh
zplug 'robbyrussell/oh-my-zsh', use:'lib/*'
zplug "plugins/git", from:oh-my-zsh

# Writing
zplug zsh-users/zsh-autosuggestions
zplug zsh-users/zsh-syntax-highlighting

zplug "denysdovhan/spaceship-prompt", use:spaceship.zsh, from:github, as:theme

# Install plugins if there are plugins that have not been installed
if ! zplug check --verbose; then
   if read -q; then
       echo; zplug install
   fi
fi

# Source plugins and add commands
zplug load

# Apply theme hacks
SPACESHIP_CHAR_SYMBOL='λ '
SPACESHIP_EXIT_CODE_SHOW=true
