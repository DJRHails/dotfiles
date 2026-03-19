#!/usr/bin/env bash
# Auto-shutdown watchdog - runs on the GPU pod
# Monitors SSH connections and GPU usage, terminates pod when idle
# Install: Copy to /workspace/scripts/ on the pod, add to cron

IDLE_TIMEOUT="${IDLE_TIMEOUT:-1800}"  # 30 minutes default
CHECK_INTERVAL="${CHECK_INTERVAL:-60}"  # Check every minute
STATE_FILE="/tmp/gpu-vm-last-active"
LOG_FILE="/var/log/auto-shutdown.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
}

# Check if there are active SSH sessions (excluding our own)
has_ssh_sessions() {
    local count
    count=$(who | grep -c pts)
    [ "$count" -gt 0 ]
}

# Check if GPU is being used (any process using CUDA)
has_gpu_activity() {
    if command -v nvidia-smi &> /dev/null; then
        local gpu_util
        gpu_util=$(nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits 2>/dev/null | head -1)
        [ -n "$gpu_util" ] && [ "$gpu_util" -gt 5 ]
    else
        return 1
    fi
}

# Check for any running training jobs or common ML processes
has_ml_processes() {
    pgrep -f "python.*train" > /dev/null 2>&1 || \
    pgrep -f "torchrun" > /dev/null 2>&1 || \
    pgrep -f "accelerate" > /dev/null 2>&1
}

# Update last active timestamp
touch_active() {
    date +%s > "$STATE_FILE"
    log "Activity detected, resetting timer"
}

# Get seconds since last activity
seconds_idle() {
    if [ -f "$STATE_FILE" ]; then
        local last_active now
        last_active=$(cat "$STATE_FILE")
        now=$(date +%s)
        echo $((now - last_active))
    else
        echo 0
    fi
}

# Self-terminate the pod
terminate_self() {
    log "Idle timeout reached (${IDLE_TIMEOUT}s). Terminating pod..."

    # Try to get pod ID from RunPod environment
    local pod_id="${RUNPOD_POD_ID:-}"

    if [ -z "$pod_id" ]; then
        log "Warning: RUNPOD_POD_ID not set, attempting shutdown"
        shutdown -h now
        return
    fi

    # Use RunPod API to terminate (requires API key in environment)
    if [ -n "$RUNPOD_API_KEY" ]; then
        curl -s -X POST "https://api.runpod.io/graphql" \
            -H "Content-Type: application/json" \
            -H "Authorization: Bearer ${RUNPOD_API_KEY}" \
            -d "{\"query\": \"mutation { podTerminate(input: {podId: \\\"${pod_id}\\\"}) }\"}"
        log "Terminate request sent"
    else
        log "Warning: RUNPOD_API_KEY not set, using shutdown"
        shutdown -h now
    fi
}

# Main watchdog loop
main() {
    log "Auto-shutdown watchdog started (timeout: ${IDLE_TIMEOUT}s)"
    touch_active

    while true; do
        if has_ssh_sessions || has_gpu_activity || has_ml_processes; then
            touch_active
        else
            local idle
            idle=$(seconds_idle)
            log "Idle for ${idle}s / ${IDLE_TIMEOUT}s"

            if [ "$idle" -ge "$IDLE_TIMEOUT" ]; then
                terminate_self
                exit 0
            fi
        fi

        sleep "$CHECK_INTERVAL"
    done
}

# Run as daemon if not sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
