#!/bin/bash

# Queue inspection
alias sq='squeue -o "%.18i %.9P %.8j %.8u %.2t %.10M %.6D %N %.10b"'
alias sqw='watch squeue -o "%.18i %.9P %.8j %.8u %.2t %.10M %.6D %N %.10b"'
alias sqme='squeue -u $(whoami) -o "%.18i %.9P %.8j %.8u %.2t %.10M %.6D %N %.10b"'

# Job control
alias sqtop='scontrol top'
alias sqdel='scancel'
alias sqclear='scancel -u $(whoami)'

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
