#!/usr/bin/env bash
# Sweeper cron job - runs on relay server (bonbon)
# Terminates pods that have been running too long without activity
# Add to cron: */15 * * * * /path/to/sweeper.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"

# Maximum runtime before force-terminate (4 hours default)
MAX_RUNTIME="${MAX_RUNTIME:-14400}"
LOG_FILE="/var/log/gpu-vm-sweeper.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
}

# Check if pod is still SSH accessible
is_ssh_accessible() {
    local pod_id="$1"
    local ssh_addr
    ssh_addr=$(get_pod_ssh "$pod_id")

    if [ -z "$ssh_addr" ] || [ "$ssh_addr" = "null" ]; then
        return 1
    fi

    local ip port
    ip=$(echo "$ssh_addr" | cut -d: -f1)
    port=$(echo "$ssh_addr" | cut -d: -f2)

    ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -o BatchMode=yes -i ~/.ssh/id_ed25519_runpod \
        -p "$port" "root@${ip}" "echo ok" 2>/dev/null | grep -q "ok"
}

# Check if pod has active SSH sessions
has_active_sessions() {
    local pod_id="$1"
    local ssh_addr
    ssh_addr=$(get_pod_ssh "$pod_id")

    if [ -z "$ssh_addr" ] || [ "$ssh_addr" = "null" ]; then
        return 1
    fi

    local ip port
    ip=$(echo "$ssh_addr" | cut -d: -f1)
    port=$(echo "$ssh_addr" | cut -d: -f2)

    local sessions
    sessions=$(ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -o BatchMode=yes -i ~/.ssh/id_ed25519_runpod \
        -p "$port" "root@${ip}" "who | grep -c pts" 2>/dev/null)

    [ -n "$sessions" ] && [ "$sessions" -gt 0 ]
}

# Sweep all active pods
sweep() {
    check_api_key || {
        log "Error: RUNPOD_API_KEY not set"
        exit 1
    }

    log "Starting sweep..."

    for state_file in "${STATE_DIR}"/*.pod; do
        [ -f "$state_file" ] || continue

        local gpu pod_id created_at
        gpu=$(basename "$state_file" .pod)
        pod_id=$(cat "$state_file")

        # Get file creation time as proxy for pod start time
        created_at=$(stat -c %Y "$state_file" 2>/dev/null || stat -f %m "$state_file" 2>/dev/null)
        local now runtime
        now=$(date +%s)
        runtime=$((now - created_at))

        log "Checking ${gpu} pod ${pod_id} (runtime: ${runtime}s)"

        # Check if pod is still running
        if ! is_pod_alive "$pod_id"; then
            log "Pod ${pod_id} no longer running, cleaning up state"
            rm -f "$state_file"
            continue
        fi

        # Force terminate if over max runtime
        if [ "$runtime" -ge "$MAX_RUNTIME" ]; then
            log "Pod ${pod_id} exceeded max runtime (${MAX_RUNTIME}s), terminating"
            terminate_pod "$pod_id" > /dev/null
            rm -f "$state_file"
            continue
        fi

        # Check for active sessions
        if ! has_active_sessions "$pod_id"; then
            log "Pod ${pod_id} has no active sessions"
            # Note: The pod's own auto-shutdown should handle this
            # We only force-terminate on max runtime
        fi
    done

    log "Sweep complete"
}

# Run sweep
sweep
