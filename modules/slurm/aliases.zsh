#!/bin/bash

# Queue inspection
alias sq='squeue -o "%.18i %.9P %.8j %.8u %.2t %.10M %.6D %N %.10b"'
alias sqw='watch squeue -o "%.18i %.9P %.8j %.8u %.2t %.10M %.6D %N %.10b"'
alias sqme='squeue -u $(whoami) -o "%.18i %.9P %.8j %.8u %.2t %.10M %.6D %N %.10b"'

# Job control
alias sqtop='scontrol top'
alias sqdel='scancel'

# NO alias for a user-scoped mass cancel. The clusters are shared and every worker logs
# in as the SAME unix account, so `scancel -u $(whoami)` is a fleet-wide cancel, not
# "mine": the old `sqclear` spelling of it destroyed a peer's long-queued multi-GPU serve
# and several array tasks. Cancel by explicit job id (`sqdel <jobid>`), or sweep only
# this worker's jobs by name prefix with `scancel-mine` (see bin/scancel-mine). A
# block_unscoped_scancel.py PreToolUse hook blocks the unscoped forms outright.
# (Incident details live in the runpod-ant-cluster skill, which is encrypted at rest —
# this file is public, so keep them out of it.)
#
# `squeue -n` (like `scancel --name`) is an EXACT name match with no globbing, so
# filter the prefix ourselves rather than passing it as a name.
# Same name matching as bin/scancel-mine: strip clusterkit's ck- tag, then require the
# prefix to end at a component boundary (so "brisk-owl" doesn't claim "brisk-owlet-...").
sqmine() {
  # Declare separately so the assignment's exit status is testable: `local x="$(cmd)"`
  # masks cmd's failure. Don't fall through to an empty prefix either — awk's
  # index(s, "") is 1 for every row, so the filter would silently become "list
  # everything" (or, one refactor away in scancel-mine, "cancel everything").
  local prefix
  if ! prefix="${SLURM_JOB_PREFIX:-$(slurm-job-prefix)}" || [[ -z $prefix ]]; then
    print -u2 "sqmine: nothing identifies this submitter — set SLURM_JOB_PREFIX, or use sqme to list every job under this (shared) uid"
    return 1
  fi
  squeue -u "$(whoami)" -o "%.18i %.9P %.30j %.2t %.10M %N" \
    | awk -v prefix="$prefix" 'NR == 1 { print; next }
      { name = $3; sub(/^ck-/, "", name)
        if (name == prefix || index(name, prefix "-") == 1) print }'
}

# Cluster info
alias sqnode='sinfo -Ne --Format=NodeHost,CPUsState,Gres,GresUsed'
alias sqinfo='sinfo'
alias sqhost='scontrol show nodes'

# Quick GPU jobs
alias sqtest='sbatch --gres=gpu:1 --wrap="hostname; nvidia-smi"'
alias sqlogin='srun --gres=gpu:1 --pty ${SHELL:-/bin/bash}'

# Submit with N GPUs: sqrun 4 script.sh
sqrun() {
  if [[ $# -lt 2 ]]; then
    echo "Usage: sqrun <num_gpus> <script> [sbatch args...]"
    return 1
  fi
  local ngpu="$1"; shift
  sbatch --gres=gpu:"$ngpu" "$@"
}

# Show job details
sqshow() {
  scontrol show job "$1"
}

# Tail the output of a running job
sqtail() {
  local jobid="$1"
  local logfile=$(scontrol show job "$jobid" 2>/dev/null | grep -oP 'StdOut=\K\S+')
  if [[ -n "$logfile" && -f "$logfile" ]]; then
    tail -f "$logfile"
  else
    echo "Cannot find log for job $jobid"
    return 1
  fi
}
