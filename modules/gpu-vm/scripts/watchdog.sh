#!/usr/bin/env bash
# Watchdog script that runs on the pod and terminates it after idle timeout
# Deployed automatically by connect.sh

IDLE_TIMEOUT=${IDLE_TIMEOUT:-300}  # 5 minutes default
CHECK_INTERVAL=30
IDLE_TIME=0
POD_ID="$1"
API_KEY="$2"

log() {
    echo "[watchdog] $(date '+%H:%M:%S') $*"
}

has_ssh_sessions() {
    # Check for SSH connections (excluding our own watchdog check)
    local sessions
    sessions=$(ss -tn state established '( sport = :22 )' 2>/dev/null | grep -v "^State" | wc -l)
    [ "$sessions" -gt 0 ]
}

terminate_pod() {
    log "Terminating pod $POD_ID due to idle timeout"
    curl -s -X DELETE "https://rest.runpod.io/v1/pods/${POD_ID}" \
        -H "Authorization: Bearer ${API_KEY}" > /dev/null 2>&1
    exit 0
}

log "Started with ${IDLE_TIMEOUT}s timeout for pod ${POD_ID}"

while true; do
    if has_ssh_sessions; then
        if [ "$IDLE_TIME" -gt 0 ]; then
            log "SSH session detected, resetting idle timer"
        fi
        IDLE_TIME=0
    else
        IDLE_TIME=$((IDLE_TIME + CHECK_INTERVAL))
        log "No SSH sessions, idle for ${IDLE_TIME}s / ${IDLE_TIMEOUT}s"

        if [ "$IDLE_TIME" -ge "$IDLE_TIMEOUT" ]; then
            terminate_pod
        fi
    fi

    sleep "$CHECK_INTERVAL"
done
