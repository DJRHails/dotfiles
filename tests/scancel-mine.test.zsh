#!/usr/bin/env zsh
# Scope and failure-reporting behavior for scancel-mine. Under the shared cluster
# account a cancel that guesses at "mine" reaps peer workers' jobs, so the contract
# worth pinning is: cancel EXPLICIT ids only, never a user filter; refuse rather than
# guess when the prefix is unknown; and report a failed query as a failure instead of
# as "you have no jobs".
#
# Runs against stub squeue/scancel/whoami/ssh binaries so it exercises the real script
# without seeing (or cancelling) real jobs on the machine running this suite. The stub
# ssh reproduces the one behaviour that broke --via: real ssh joins its argv with
# spaces and hands ONE string to the remote shell, which re-splits it.
# Self-contained: `zsh -f tests/scancel-mine.test.zsh`. Exits non-zero on failure.
set -u

script_dir="${0:A:h}"
mine="$script_dir/../bin/scancel-mine"

work="$(mktemp -d)"
trap 'rm -rf -- "$work"' EXIT
stub="$work/bin"
mkdir -p "$stub"
path=("$stub" /usr/bin /bin)
unset SLURM_JOB_PREFIX

fails=0
check() {
  if [[ $2 == "$3" ]]; then
    print "ok   $1"
  else
    print "FAIL $1: expected [$2] got [$3]"
    (( fails++ ))
  fi
}

cat >"$stub/whoami" <<'EOF'
#!/usr/bin/env bash
echo djrhails
EOF

# Records its argv so a test can assert scancel was given explicit ids and no filter.
cat >"$stub/scancel" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$SCANCEL_LOG"
EOF

# Parses like the real squeue: -o takes ONE value, a stray operand is an error.
cat >"$stub/squeue" <<'EOF'
#!/usr/bin/env bash
fmt=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o) fmt="$2"; shift ;;
    -u) shift ;;
    -h|--jobs=*|-*) ;;
    *) echo "squeue: error: Unrecognized option: $1" >&2; exit 1 ;;
  esac
  shift
done
[[ "$fmt" == *'%j'* ]] || { echo "squeue: error: no job-name column requested" >&2; exit 1; }
echo "111 worker1-train"
echo "222 worker10-serve"
echo "333 other-worker-serve"
echo "444 worker1"
EOF

cat >"$stub/ssh" <<'EOF'
#!/usr/bin/env bash
shift                      # drop the host
exec bash -c "$*"          # real ssh joins argv and lets the remote shell re-split
EOF
chmod +x "$stub"/*

export SCANCEL_LOG="$work/scancel.log"
: >"$SCANCEL_LOG"

# no prefix anywhere: refuse, exit 2, cancel nothing
out="$(bash "$mine" 2>&1)"; rc=$?
check no-prefix-refuses 2 $rc
check no-prefix-cancels-nothing "" "$(<"$SCANCEL_LOG")"
check no-prefix-explains yes "$([[ $out == *'no job-name prefix'* ]] && print yes || print no)"

# --dry-run lists but must not cancel
: >"$SCANCEL_LOG"
bash "$mine" --prefix worker1 --dry-run >/dev/null 2>&1
check dry-run-cancels-nothing "" "$(<"$SCANCEL_LOG")"

# a real run passes EXPLICIT ids and never a user filter, and excludes the
# superstring-prefixed peer (worker10) while keeping the bare-prefix job (444)
: >"$SCANCEL_LOG"
bash "$mine" --prefix worker1 >/dev/null 2>&1
logged="$(<"$SCANCEL_LOG")"
check cancels-explicit-ids "111 444" "$logged"
has_filter="$([[ $logged == *-u* || $logged == *--me* ]] && print yes || print no)"
check never-user-filter no "$has_filter"

# a failed query is a failure, not "no jobs"
: >"$SCANCEL_LOG"
cat >"$stub/squeue" <<'EOF'
#!/usr/bin/env bash
echo "squeue: error: Unable to contact slurm controller" >&2
exit 1
EOF
chmod +x "$stub/squeue"
out="$(bash "$mine" --prefix worker1 2>&1)"; rc=$?
check query-failure-exits-nonzero 1 $rc
check query-failure-says-so yes "$([[ $out == *'squeue failed'* ]] && print yes || print no)"
said_no_jobs="$([[ $out == *'no jobs with name prefix'* ]] && print yes || print no)"
check query-failure-not-no-jobs no "$said_no_jobs"
check query-failure-cancels-nothing "" "$(<"$SCANCEL_LOG")"

# --via must survive ssh's argv flattening: the '%i %j' format has to arrive intact,
# which is what makes the job-name column (and so the prefix match) work at all
: >"$SCANCEL_LOG"
cat >"$stub/squeue" <<'EOF'
#!/usr/bin/env bash
fmt=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o) fmt="$2"; shift ;;
    -u) shift ;;
    -h|--jobs=*|-*) ;;
    *) echo "squeue: error: Unrecognized option: $1" >&2; exit 1 ;;
  esac
  shift
done
[[ "$fmt" == *'%j'* ]] || { echo "squeue: error: no job-name column requested" >&2; exit 1; }
echo "111 worker1-train"
EOF
chmod +x "$stub/squeue"
out="$(bash "$mine" --prefix worker1 --via ant-cluster 2>&1)"; rc=$?
check via-succeeds 0 $rc
check via-cancels-explicit-ids "111" "$(<"$SCANCEL_LOG")"

# a flag-shaped option value must be rejected, not silently taken as the prefix
out="$(bash "$mine" --prefix --dry-run 2>&1)"; rc=$?
check flag-shaped-value-rejected 2 $rc

# unknown argument
out="$(bash "$mine" --nope 2>&1)"; rc=$?
check unknown-arg-exits-2 2 $rc

(( fails == 0 )) || exit 1
print "\nall scancel-mine checks passed"
