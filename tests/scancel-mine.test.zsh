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
#
# No `set -e`: most checks below run the script expecting it to FAIL and then inspect
# `$?`, which `set -e` would turn into an abort.
# Self-contained: `zsh -f tests/scancel-mine.test.zsh`. Exits non-zero on failure.
set -u
set -o pipefail

script_dir="${0:A:h}"
mine="$script_dir/../bin/scancel-mine"

work="$(mktemp -d)"
trap 'rm -rf -- "$work"' EXIT
stub="$work/bin"
mkdir -p "$stub"

# scancel-mine is `#!/usr/bin/env bash` and uses `mapfile`, a bash 4 builtin. Pinning the
# path to /usr/bin:/bin alone finds macOS's bash 3.2, where every run exits 127 and the
# whole suite fails for a reason that has nothing to do with the code under test. Locate a
# bash that actually has mapfile and put its directory on the pinned path. The pin itself
# stays — the stubs must shadow real squeue/scancel — so this adds exactly one directory.
bash_dir=""
for candidate in $(whence -ap bash) /opt/homebrew/bin/bash /usr/local/bin/bash; do
  if [[ -x $candidate ]] && "$candidate" -c 'mapfile -t _ < <(:)' 2>/dev/null; then
    bash_dir="${candidate:A:h}"
    break
  fi
done
if [[ -z $bash_dir ]]; then
  print -u2 "scancel-mine tests: no bash with mapfile (bash 4+) found; install one (brew install bash)"
  exit 2
fi

path=("$stub" "$bash_dir" /usr/bin /bin)
# slurm-job-prefix reads both: $SLURM_JOB_PREFIX first, then $GANTRY_THREAD_KEY
# (set in every gantry worker container, where these tests run as a prek hook) —
# the no-prefix cases need a genuinely prefix-free environment.
unset SLURM_JOB_PREFIX
unset GANTRY_THREAD_KEY

fails=0
check() {
  if [[ $2 == "$3" ]]; then
    print "ok   $1"
  else
    print "FAIL $1: expected [$2] got [$3]"
    (( fails++ ))
  fi
}

# yes/no helper, so an assertion reads as the claim it is making
said() { [[ $1 == *$2* ]] && print yes || print no }

install_whoami() {
  cat >"$stub/whoami" <<EOF
#!/usr/bin/env bash
$1
EOF
  chmod +x "$stub/whoami"
}

# Parses like the real squeue: -o takes ONE value, a stray operand is an error. The rows
# it emits cover the prefix-boundary cases: an exact match, a peer whose prefix EXTENDS
# ours (worker10), an unrelated worker, and the bare prefix with no suffix.
install_squeue() {
  cat >"$stub/squeue" <<EOF
#!/usr/bin/env bash
fmt=""
while [[ \$# -gt 0 ]]; do
  case "\$1" in
    -o) fmt="\$2"; shift ;;
    -u) shift ;;
    -h|--jobs=*|-*) ;;
    *) echo "squeue: error: Unrecognized option: \$1" >&2; exit 1 ;;
  esac
  shift
done
[[ "\$fmt" == *'%j'* ]] || { echo "squeue: error: no job-name column requested" >&2; exit 1; }
$1
EOF
  chmod +x "$stub/squeue"
}

FOUR_ROWS='echo "111 worker1-train"
echo "222 worker10-serve"
echo "333 other-worker-serve"
echo "444 worker1"'

install_whoami 'echo djrhails'
install_squeue "$FOUR_ROWS"

# Records its argv so a test can assert scancel was given explicit ids and no filter.
cat >"$stub/scancel" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$SCANCEL_LOG"
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
check no-prefix-explains yes "$(said "$out" 'no job-name prefix')"

# --dry-run lists but must not cancel. An empty cancel log alone is NOT enough: it is also
# what you get when --dry-run is unimplemented and the run dies in the arg parser, which
# left this check passing against a script that had no --dry-run at all. Pin rc and output.
: >"$SCANCEL_LOG"
out="$(bash "$mine" --prefix worker1 --dry-run 2>&1)"; rc=$?
check dry-run-cancels-nothing "" "$(<"$SCANCEL_LOG")"
check dry-run-succeeds 0 $rc
check dry-run-says-so yes "$(said "$out" '--dry-run, cancelling nothing')"
check dry-run-lists-the-ids yes "$(said "$out" '2 job(s) with name prefix')"

# a real run passes EXPLICIT ids and never a user filter, and excludes the
# superstring-prefixed peer (worker10) while keeping the bare-prefix job (444)
: >"$SCANCEL_LOG"
bash "$mine" --prefix worker1 >/dev/null 2>&1
logged="$(<"$SCANCEL_LOG")"
check cancels-explicit-ids "111 444" "$logged"
check never-user-filter no "$([[ $logged == *-u* || $logged == *--me* ]] && print yes || print no)"

# $SLURM_JOB_PREFIX is the production input — every real invocation sets it rather than
# passing --prefix, so the env-var path needs pinning too
: >"$SCANCEL_LOG"
SLURM_JOB_PREFIX=worker1 bash "$mine" >/dev/null 2>&1
check env-prefix-honoured "111 444" "$(<"$SCANCEL_LOG")"

# --prefix is sanitised to [A-Za-z0-9_-] before the awk match, so whitespace in it cannot
# break the single-`%j`-field assumption the prefix comparison depends on
: >"$SCANCEL_LOG"
install_squeue 'echo "555 worker-1-eval"'
bash "$mine" --prefix 'worker 1' >/dev/null 2>&1
check prefix-sanitised "555" "$(<"$SCANCEL_LOG")"
install_squeue "$FOUR_ROWS"

# a failed query is a failure, not "no jobs"
: >"$SCANCEL_LOG"
install_squeue 'echo "squeue: error: Unable to contact slurm controller" >&2; exit 1'
out="$(bash "$mine" --prefix worker1 2>&1)"; rc=$?
check query-failure-exits-nonzero 1 $rc
check query-failure-says-so yes "$(said "$out" 'squeue failed')"
check query-failure-not-no-jobs no "$(said "$out" 'no jobs with name prefix')"
check query-failure-cancels-nothing "" "$(<"$SCANCEL_LOG")"
install_squeue "$FOUR_ROWS"

# resolving the cluster user must fail loudly, whether whoami errors OR returns nothing:
# an empty result would otherwise become `squeue -u ""`, a filter of unverified breadth
: >"$SCANCEL_LOG"
install_whoami 'exit 1'
out="$(bash "$mine" --prefix worker1 2>&1)"; rc=$?
check whoami-failure-exits-1 1 $rc
check whoami-failure-cancels-nothing "" "$(<"$SCANCEL_LOG")"

: >"$SCANCEL_LOG"
install_whoami 'exit 0'   # succeeds, prints nothing
out="$(bash "$mine" --prefix worker1 2>&1)"; rc=$?
check whoami-empty-exits-1 1 $rc
check whoami-empty-says-so yes "$(said "$out" 'could not resolve the cluster user')"
check whoami-empty-cancels-nothing "" "$(<"$SCANCEL_LOG")"
install_whoami 'echo djrhails'

# no squeue on PATH and no --via: refuse and point at --via, rather than failing obscurely
# later. This is the first thing a worker container hits.
: >"$SCANCEL_LOG"
mv "$stub/squeue" "$work/squeue.hidden"
out="$(bash "$mine" --prefix worker1 2>&1)"; rc=$?
check no-squeue-exits-2 2 $rc
check no-squeue-suggests-via yes "$(said "$out" 'pass --via')"
check no-squeue-cancels-nothing "" "$(<"$SCANCEL_LOG")"
mv "$work/squeue.hidden" "$stub/squeue"

# --via must survive ssh's argv flattening: the '%i %j' format has to arrive intact,
# which is what makes the job-name column (and so the prefix match) work at all
: >"$SCANCEL_LOG"
install_squeue 'echo "111 worker1-train"'
out="$(bash "$mine" --prefix worker1 --via ant-cluster 2>&1)"; rc=$?
check via-succeeds 0 $rc
check via-cancels-explicit-ids "111" "$(<"$SCANCEL_LOG")"
install_squeue "$FOUR_ROWS"

# a prefix matching nothing is a clean no-op, not an empty-filter sweep
: >"$SCANCEL_LOG"
out="$(bash "$mine" --prefix nobody-here 2>&1)"; rc=$?
check no-match-exits-0 0 $rc
check no-match-cancels-nothing "" "$(<"$SCANCEL_LOG")"
check no-match-says-so yes "$(said "$out" 'no jobs with name prefix')"

# a flag-shaped option value must be rejected, not silently taken as the prefix
: >"$SCANCEL_LOG"
out="$(bash "$mine" --prefix --dry-run 2>&1)"; rc=$?
check flag-shaped-value-rejected 2 $rc
check flag-shaped-value-explains yes "$(said "$out" 'needs a value')"
check flag-shaped-value-cancels-nothing "" "$(<"$SCANCEL_LOG")"

# unknown argument
out="$(bash "$mine" --nope 2>&1)"; rc=$?
check unknown-arg-exits-2 2 $rc
check unknown-arg-explains yes "$(said "$out" "unknown argument '--nope'")"

# --help documents every flag the parser accepts, including itself
out="$(bash "$mine" --help 2>&1)"; rc=$?
check help-exits-0 0 $rc
for flag in --dry-run --prefix --via --help; do
  check "help-documents-$flag" yes "$(said "$out" "$flag")"
done

(( fails == 0 )) || exit 1
print "\nall scancel-mine checks passed"
