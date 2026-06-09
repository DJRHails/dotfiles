#!/usr/bin/env bash
# Cron job to terminate idle GPU pods
# Run every minute: * * * * * ~/.files/modules/gpu-vm/scripts/idle-check.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"
source "${SCRIPT_DIR}/lib.sh"

IDLE_DIR="${STATE_DIR}/idle"
mkdir -p "$IDLE_DIR"

log() {
    echo "[idle-check] $(date '+%Y-%m-%d %H:%M:%S') $*" >> "${STATE_DIR}/idle-check.log"
}

# Check if there's an active SSH connection to a pod
has_active_connection() {
    local ip="$1"
    local port="$2"
    # Check for established TCP connections from this host to the pod
    ss -tn state established "dst ${ip}:${port}" 2>/dev/null | grep -q "${ip}:${port}"
}

# Process each active pod
for state_file in "${STATE_DIR}"/*.pod; do
    [ -f "$state_file" ] || continue

    gpu=$(basename "$state_file" .pod)
    pod_id=$(cat "$state_file")
    idle_file="${IDLE_DIR}/${pod_id}.idle"

    # Get pod connection info
    ip="" port=""
    ssh_info=$(get_pod_ssh "$pod_id" 2>/dev/null)
    if [ -n "$ssh_info" ] && [ "$ssh_info" != "null" ]; then
        ip=$(echo "$ssh_info" | cut -d: -f1)
        port=$(echo "$ssh_info" | cut -d: -f2)
    else
        # No SSH info: the pod may be booting, dead, or stuck without SSH.
        is_pod_alive "$pod_id" 2>/dev/null
        alive=$?
        if [ "$alive" -eq 2 ]; then
            log "Pod ${pod_id} (${gpu}): API unreachable, will retry next run"
            continue
        fi
        if [ "$alive" -eq 1 ]; then
            log "Pod ${pod_id} (${gpu}): not running, terminating and cleaning up state"
            terminate_pod "$pod_id" > /dev/null 2>&1
            rm -f "$state_file" "$idle_file"
            continue
        fi
        # RUNNING with no SSH: allow a boot grace period, then run the
        # idle timer below anyway so the pod still gets reaped.
        pod_age=$(( $(date +%s) - $(stat -c %Y "$state_file") ))
        if [ "$pod_age" -lt "$BOOT_TIMEOUT" ]; then
            log "Pod ${pod_id} (${gpu}): RUNNING, no SSH yet (${pod_age}s old), in boot grace"
            continue
        fi
        log "Pod ${pod_id} (${gpu}): RUNNING with no SSH after ${pod_age}s, counting as idle"
    fi

    if [ -n "$ip" ] && has_active_connection "$ip" "$port"; then
        # Active connection - reset idle timer
        rm -f "$idle_file"
        log "Pod ${pod_id} (${gpu}): active connection to ${ip}:${port}"
    else
        # No connection - increment idle time
        if [ -f "$idle_file" ]; then
            idle_since=$(cat "$idle_file")
        else
            idle_since=$(date +%s)
            echo "$idle_since" > "$idle_file"
        fi

        now=$(date +%s)
        idle_time=$((now - idle_since))

        log "Pod ${pod_id} (${gpu}): idle for ${idle_time}s / ${IDLE_TIMEOUT}s"

        if [ "$idle_time" -ge "$IDLE_TIMEOUT" ]; then
            log "Pod ${pod_id} (${gpu}): terminating due to idle timeout"
            terminate_pod "$pod_id" > /dev/null
            rm -f "$state_file" "$idle_file"
        fi
    fi
done

# Clean up idle files for pods that no longer exist. Only a definitive
# "not running" (rc 1) clears the file; an API blip (rc 2) must not
# reset a live pod's idle timer.
for idle_file in "${IDLE_DIR}"/*.idle; do
    [ -f "$idle_file" ] || continue
    pod_id=$(basename "$idle_file" .idle)
    is_pod_alive "$pod_id" 2>/dev/null
    if [ $? -eq 1 ]; then
        rm -f "$idle_file"
    fi
done
