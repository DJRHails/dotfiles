# echo "$(github-copilot-cli alias -- "$0")"

copilot_what-the-shell() {
    TMPFILE=$(mktemp)
    trap 'rm -f $TMPFILE' EXIT
    if /usr/bin/github-copilot-cli what-the-shell "$@" --shellout $TMPFILE; then
        if [ -e "$TMPFILE" ]; then
            FIXED_CMD=$(cat $TMPFILE)
            print -s "$FIXED_CMD"
            eval "$FIXED_CMD"
        else
            echo "Apologies! Extracting command failed"
        fi
    else
        return 1
    fi
}

alias '??'='copilot_what-the-shell'
