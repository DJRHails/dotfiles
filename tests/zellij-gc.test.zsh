#!/usr/bin/env zsh
# Throttle, flag, and EXITED-sweep behavior for zellij-gc. The throttle checks
# need no zellij binary: the script exits right after the throttle logic when
# zellij is absent, so whether the throttle stamp got (re)written proves which
# side of the throttle a run landed on. Regression test for the extended_glob
# bug that made the throttle always fire — with it, the first run below never
# writes the stamp. The sweep checks run against stub zellij/ps binaries so
# they exercise the real script without seeing (or signalling) real sessions
# on the machine running this suite.
# Self-contained: `zsh -f tests/zellij-gc.test.zsh`. Exits non-zero on failure.
set -u
zmodload zsh/datetime

script_dir="${0:A:h}"
gc="$script_dir/../modules/zellij/zellij-gc"

work="$(mktemp -d)"
trap 'rm -rf -- "$work"' EXIT
export XDG_CACHE_HOME="$work"
path=(/usr/bin /bin)  # hide zellij even if installed

logdir="$work/cmux-zellij"
stamp="$logdir/gc-last-run"

fails=0
check() {
  if [[ $2 == "$3" ]]; then
    print "ok   $1"
  else
    print "FAIL $1: expected [$2] got [$3]"
    (( fails++ ))
  fi
}

# first run ever (no stamp): must pass the throttle and write the stamp
zsh -f "$gc"
check first-run-passes-throttle "yes" "$([[ -f $stamp ]] && print yes || print no)"

# immediate second run: fresh stamp throttles, stamp content untouched
before="$(<"$stamp")"
sleep 1.1
zsh -f "$gc"
check fresh-stamp-throttles "$before" "$(<"$stamp")"

# stale stamp (7h old mtime): throttle expired, gc runs and rewrites the stamp
touch -t "$(strftime '%Y%m%d%H%M' $(( EPOCHSECONDS - 7 * 3600 )))" "$stamp"
zsh -f "$gc"
check stale-stamp-runs "yes" "$([[ "$(<"$stamp")" != "$before" ]] && print yes || print no)"

# --dry-run on a clean slate: touches neither the stamp nor gc.log
rm -rf -- "$logdir"
zsh -f "$gc" --dry-run
check dry-run-no-stamp "no" "$([[ -e $stamp ]] && print yes || print no)"
check dry-run-no-log "no" "$([[ -e $logdir/gc.log ]] && print yes || print no)"

# unknown flag: usage error
zsh -f "$gc" --bogus 2>/dev/null
check unknown-flag-exit-2 "2" "$?"

# The remaining checks need the script to get past its `command -v zellij`
# exit: stub zellij (reports one EXITED cmux session), and stub ps to print
# nothing so the reap loop can never see real servers.
stub="$work/stub-bin"
mkdir -p "$stub"
cat > "$stub/zellij" <<'EOF'
#!/bin/sh
[ "$1" = list-sessions ] && echo "cmux-gc-test-dead [Created 30days ago] (EXITED - attach to resurrect)"
exit 0
EOF
cat > "$stub/ps" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod +x "$stub/zellij" "$stub/ps"

# non-numeric stale-hours env must not error (falls back to the default).
# Needs the zellij stub — without it the script exits before the arithmetic
# that a bad value breaks, and this check can't fail. stderr only: dry-run's
# would-seed chatter on stdout is expected.
err="$(CMUX_ZELLIJ_GC_STALE_HOURS=abc PATH="$stub:$PATH" zsh -f "$gc" --dry-run 2>&1 >/dev/null)"
check bad-stale-hours-silent "" "$err"

# EXITED record first seen without a stamp: seeded now, not deleted
PATH="$stub:$PATH" zsh -f "$gc" --force
check exited-no-stamp-seeded "yes" "$([[ -f $logdir/last-cmux-gc-test-dead ]] && print yes || print no)"

# stamp aged past 7 days: record deleted and its sidecar files cleaned up
print $(( EPOCHSECONDS - 8 * 86400 )) > "$logdir/last-cmux-gc-test-dead"
print "ws-id sf-id" > "$logdir/live-cmux-gc-test-dead"
PATH="$stub:$PATH" zsh -f "$gc" --force
check exited-stale-stamp-removed "no" "$([[ -e $logdir/last-cmux-gc-test-dead ]] && print yes || print no)"
check exited-stale-live-removed "no" "$([[ -e $logdir/live-cmux-gc-test-dead ]] && print yes || print no)"

(( fails == 0 )) && { print "all passed"; exit 0 } || { print "$fails failed"; exit 1 }
