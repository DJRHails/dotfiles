#!/usr/bin/env zsh
# Behaviour suite for the per-worker Slurm job scoping: bin/slurm-job-prefix and the name
# matching in bin/scancel-mine.
#
# Self-contained: `zsh -f tests/slurm-job-scoping.test.zsh`. Exits non-zero on failure.
#
# What this is really guarding: clusterkit names every job it submits `ck-<prefix>-<slug>`,
# slugifying the prefix with its OWN rules, while scancel-mine matches on the prefix printed
# by slurm-job-prefix. Those two derivations have to agree character-for-character. If they
# drift, scancel-mine matches NOTHING, an operator falls back to `scancel -u $USER`, and that
# reaps every peer worker's queued compute — the exact incident this path exists to prevent.
# So the suite pins the slug rules against clusterkit's and the ck- tag handling against the
# name format clusterkit actually emits.
set -u

script_dir="${0:A:h}"
prefix_bin="$script_dir/../bin/slurm-job-prefix"
scancel_bin="$script_dir/../bin/scancel-mine"

fails=0
check() {
  if [[ $2 == "$3" ]]; then
    print "ok   $1"
  else
    print "FAIL $1: expected [$2] got [$3]"
    ((fails++))
  fi
}

# --- slurm-job-prefix -------------------------------------------------------------------
# The gantry thread slug, minus its thrd_ tag, is the prefix.
check thread-key "steady-bold-ocean" \
  "$(env -u SLURM_JOB_PREFIX GANTRY_THREAD_KEY=thrd_steady-bold-ocean "$prefix_bin")"
# An explicit override wins over the thread key.
check explicit-override "my-run" \
  "$(env SLURM_JOB_PREFIX=my-run GANTRY_THREAD_KEY=thrd_steady-bold-ocean "$prefix_bin")"
# With nothing identifying a submitter there must be NO invented prefix: clusterkit only
# prefixes a name when it can identify one, so a made-up prefix (the hostname, say) would
# name no real job and turn scancel-mine's refusal into a misleading "no jobs found".
check no-invented-prefix "" \
  "$(env -u SLURM_JOB_PREFIX -u GANTRY_THREAD_KEY "$prefix_bin" 2>/dev/null)"
env -u SLURM_JOB_PREFIX -u GANTRY_THREAD_KEY "$prefix_bin" >/dev/null 2>&1
check no-invented-prefix-exits-nonzero "1" "$?"

# Slug rules must match clusterkit.script.slugify: lower-case, collapse anything outside
# [a-z0-9-] to ONE dash, strip the ends. Underscores and case are the drift-prone parts.
check slug-lowercases "odd-key" "$(env SLURM_JOB_PREFIX="Odd-Key" "$prefix_bin")"
check slug-collapses-underscore "thrd-odd-key" "$(env SLURM_JOB_PREFIX="thrd_Odd_Key" "$prefix_bin")"
check slug-collapses-runs "a-b" "$(env SLURM_JOB_PREFIX="a!!!b" "$prefix_bin")"
check slug-strips-ends "abc" "$(env SLURM_JOB_PREFIX="__abc__" "$prefix_bin")"
check slug-strips-spaces "odd-key" "$(env SLURM_JOB_PREFIX=" Odd Key " "$prefix_bin")"

# --- scancel-mine name matching ---------------------------------------------------------
# Drive the real script with a fake squeue/scancel on PATH, so the awk matching is exercised
# exactly as it runs on a login node. --dry-run keeps it side-effect free.
work="$(mktemp -d)"
trap 'rm -rf -- "$work"' EXIT
mkdir -p "$work/bin"
path=("$work/bin" "$script_dir/../bin" $path)

# The queue a worker with prefix "brisk-owl" would see: two of its own jobs (one carrying
# clusterkit's ck- tag), a look-alike peer prefix, and two unrelated peers.
# Honours --jobs=<list> like the real squeue, so the script's second (display) call shows
# only the selected jobs rather than the whole queue.
cat >"$work/bin/squeue" <<'EOF'
#!/bin/sh
rows='101 ck-brisk-owl-vllm-serve-glm
102 brisk-owl-mmlu-pro-cap
103 ck-brisk-owlet-vllm-serve-glm
104 ck-tranquil-fox-mmlu-pro-cap
105 mmlu-pro-cap'
want=""
for arg in "$@"; do
  case "$arg" in --jobs=*) want="${arg#--jobs=}" ;; esac
done
if [ -z "$want" ]; then
  echo "$rows"
  exit 0
fi
echo "$rows" | while IFS= read -r row; do
  case ",$want," in *",${row%% *},"*) echo "$row" ;; esac
done
EOF
cat >"$work/bin/whoami" <<'EOF'
#!/bin/sh
echo djrhails
EOF
chmod +x "$work/bin/squeue" "$work/bin/whoami"

listed="$(env SLURM_JOB_PREFIX=brisk-owl "$scancel_bin" --dry-run 2>&1 | grep -oE '^scancel-mine: [0-9]+ job')"
check dry-run-counts-own-jobs "scancel-mine: 2 job" "$listed"

# The ids it would cancel: its own two, tagged or not — and NOT the brisk-owlet look-alike.
ids="$(env SLURM_JOB_PREFIX=brisk-owl "$scancel_bin" --dry-run 2>&1 | grep -oE '\b10[0-9]\b' | sort -u | tr '\n' ' ')"
check dry-run-ids "101 102 " "$ids"

# A prefix matching nothing must exit 0 having cancelled nothing, not fall back to a sweep.
none="$(env SLURM_JOB_PREFIX=absent-worker "$scancel_bin" --dry-run 2>&1)"
check no-match-message "scancel-mine: no jobs with name prefix 'absent-worker'" "$none"

# Refuse rather than guess when there is no prefix at all.
env -u SLURM_JOB_PREFIX -u GANTRY_THREAD_KEY "$scancel_bin" >/dev/null 2>&1
check refuses-without-prefix "2" "$?"

# --dry-run must never invoke scancel. A scancel on PATH that fails loudly proves it.
cat >"$work/bin/scancel" <<'EOF'
#!/bin/sh
echo "REAL SCANCEL CALLED: $*" >&2
exit 99
EOF
chmod +x "$work/bin/scancel"
env SLURM_JOB_PREFIX=brisk-owl "$scancel_bin" --dry-run >/dev/null 2>"$work/err"
check dry-run-cancels-nothing "" "$(grep -c 'REAL SCANCEL CALLED' "$work/err" | tr -d ' ' | sed 's/^0$//')"

# Without --dry-run it cancels by EXPLICIT ids — never a user filter.
env SLURM_JOB_PREFIX=brisk-owl "$scancel_bin" >/dev/null 2>"$work/err2"
check cancels-explicit-ids "REAL SCANCEL CALLED: 101 102" "$(grep -o 'REAL SCANCEL CALLED: .*' "$work/err2")"

((fails == 0)) || exit 1
print "ok"
