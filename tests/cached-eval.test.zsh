#!/usr/bin/env zsh
# Behavior suite for _cached_eval (modules/zsh/zshenv).
# Self-contained: `zsh -f tests/cached-eval.test.zsh`. Exits non-zero on failure.
set -u

script_dir="${0:A:h}"
zshenv="$script_dir/../modules/zsh/zshenv"

work="$(mktemp -d)"
trap 'rm -rf -- "$work"' EXIT
export XDG_CACHE_HOME="$work/cache"
mkdir -p "$work/bin"
path=("$work/bin" $path)

# Fake tool: emits its invocation count, so a cache hit (tool NOT re-run) is
# distinguishable from a regeneration (count advances).
export FAKETOOL_COUNT_FILE="$work/count"
cat > "$work/bin/faketool" <<'EOF'
#!/bin/sh
count=$(cat "$FAKETOOL_COUNT_FILE" 2>/dev/null || echo 0)
echo "export FAKE_COUNT=$count"
echo $((count + 1)) > "$FAKETOOL_COUNT_FILE"
EOF
chmod +x "$work/bin/faketool"
echo 0 > "$FAKETOOL_COUNT_FILE"

fails=0
check() {
  if [[ $2 == "$3" ]]; then
    print "ok   $1"
  else
    print "FAIL $1: expected [$2] got [$3]"
    (( fails++ ))
  fi
}

# Run a snippet in a fresh non-rc shell with only _cached_eval defined, so the
# suite exercises the function exactly as a cold shell would see it.
fn="$(sed -n '/^_cached_eval() {/,/^}/p' "$zshenv")"
run() { zsh -f -c "$fn"$'\n'"$1" }

cache_file="$XDG_CACHE_HOME/zsh-eval-cache/faketool.zsh"

# cold start: tool runs once, output is evaluated
check cold "0" "$(run '_cached_eval faketool && print $FAKE_COUNT')"
# warm start: cache hit, tool must NOT run again
check warm "0" "$(run '_cached_eval faketool && print $FAKE_COUNT')"
check warm-no-subprocess "1" "$(<"$FAKETOOL_COUNT_FILE")"

# binary upgrade (mtime change) regenerates
sleep 1.1; touch "$work/bin/faketool"
check binary-upgrade "1" "$(run '_cached_eval faketool && print $FAKE_COUNT')"

# -d dep file: older dep leaves the cache fresh, newer dep invalidates
dep="$work/plugins.toml"
touch -r "$zshenv" "$dep"  # mtime well before the cache's
check dep-old-fresh "1" "$(run "_cached_eval -d ${(q)dep} faketool && print \$FAKE_COUNT")"
sleep 1.1; touch "$dep"
check dep-invalidates "2" "$(run "_cached_eval -d ${(q)dep} faketool && print \$FAKE_COUNT")"

# corrupt cache (bad header) regenerates instead of sourcing garbage
print 'utter garbage (((' > "$cache_file"
check corrupt-recovery "3" "$(run '_cached_eval faketool && print $FAKE_COUNT' 2>/dev/null)"

# unwritable cache dir: regeneration impossible -> live-eval fallback, no error
sleep 1.1; touch "$work/bin/faketool"
chmod a-w "$XDG_CACHE_HOME/zsh-eval-cache"
check readonly-fallback "4" "$(run '_cached_eval faketool && print $FAKE_COUNT')"
chmod u+w "$XDG_CACHE_HOME/zsh-eval-cache"

# missing binary returns 1
check missing-binary "1" "$(run '_cached_eval no-such-tool-xyz; print $?')"

# setopt in the tool's output must land in the caller's shell, not get
# localized away (starship emits `setopt promptsubst`)
cat > "$work/bin/setopttool" <<'EOF'
#!/bin/sh
echo "setopt promptsubst"
EOF
chmod +x "$work/bin/setopttool"
check setopt-escapes "on" \
  "$(run '_cached_eval setopttool; [[ -o promptsubst ]] && print on || print off')"

# 6-way concurrent cold start: atomic writes mean no shell ever sources a
# torn cache, and the surviving cache file is valid
rm -f "$cache_file"
concurrent_out="$work/concurrent"
for i in 1 2 3 4 5 6; do
  run '_cached_eval faketool && print $FAKE_COUNT' >> "$concurrent_out" &
done
wait
check concurrent-all-succeed "6" "$(wc -l < "$concurrent_out" | tr -d ' ')"
first_line="$(head -1 "$cache_file")"
check concurrent-cache-valid "yes" \
  "$([[ $first_line == '# _cached_eval: faketool -> '* ]] && print yes || print no)"

(( fails == 0 )) && { print "all passed"; exit 0 } || { print "$fails failed"; exit 1 }
