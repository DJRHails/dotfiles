#!/usr/bin/env bash

. "$DOTFILES/scripts/core/main.sh"

# Perl Style check
alias fc="git diff --name-only HEAD origin/master"

alias perl::sort="env LC_COLLATE=C sort 2>/dev/null"

perl::sort_file() {
    local filename="$1"

    # For each file, label with pod number and select functions
    funcs=$(gawk '/=head1.+METHOD|# PRIVATE/ { sec++ } match($0, /^sub (\w+)/, m) { printf("(%d) %s\n", sec, m[1]) }' $filename)
    nfuncs=$(echo "$funcs" | egrep -v 'new(_from_\w+)?$|DESTROY$')

    sorted=$(echo "$nfuncs" | perl::sort -c; echo $?)
    if [[ "$sorted" == "0" ]]; then
        log::green "[✔] $1\n"
    else
        log::red "[✖] $1\n"
        colordiff -y <(echo "$nfuncs") <(echo "$nfuncs" | perl::sort) 2>/dev/null
	echo ""
    fi
}

perl::sort_files() {
    while read filename
    do
        perl::sort_file $filename
    done
}

alias check_fat_commas="fc | xargs -I _ sh -c \"echo '=== _ ==='; grep '=>' -C 1 _\""