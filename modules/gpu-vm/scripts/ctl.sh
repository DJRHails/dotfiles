#!/usr/bin/env bash
# Manual control: create, terminate, status
# Usage: ctl.sh [create|terminate|status] [gpu_type|all]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"

CMD="${1:-status}"
GPU="${2:-$DEFAULT_GPU}"

case "$CMD" in
    create|start)
        if [ -z "${GPU_TYPES[$(gpu_base "$GPU")]}" ]; then
            echo "Unknown GPU type: ${GPU}. Available: ${!GPU_TYPES[*]}"
            exit 1
        fi
        echo "Creating ${GPU} pod..."
        if ! RESULT=$(get_or_create_pod "$GPU"); then
            echo "Failed to create ${GPU} pod (see errors above)." >&2
            exit 1
        fi
        IP=$(echo "$RESULT" | awk '{print $1}')
        PORT=$(echo "$RESULT" | awk '{print $2}')
        POD_ID=$(get_active_pod "$GPU")
        echo "Pod ready: ${POD_ID}"
        echo "SSH: ssh -p ${PORT} root@${IP}"
        ;;
    terminate|stop)
        if [ "$GPU" = "all" ]; then
            echo "Terminating all pods..."
            terminate_all_pods
            echo "All pods terminated."
        else
            POD_ID=$(get_active_pod "$GPU")
            if [ -z "$POD_ID" ]; then
                echo "No active ${GPU} pod found."
                exit 0
            fi
            echo "Terminating ${GPU} pod (${POD_ID})..."
            terminate_pod "$POD_ID" > /dev/null
            clear_active_pod "$GPU"
            echo "Pod terminated."
        fi
        ;;
    status)
        echo "GPU Pod Status:"
        echo "==============="
        # Iterate state files (like terminate-all/idle-check) so slot pods
        # such as 4090-a are visible, not just GPU_TYPES base names.
        found=0
        for state_file in "${STATE_DIR}"/*.pod; do
            [ -f "$state_file" ] || continue
            found=1
            gpu=$(basename "$state_file" .pod)
            pod_id=$(cat "$state_file")
            status=$(get_pod_status "$pod_id" | jq -r '.desiredStatus // "UNKNOWN"')
            ssh_info=$(get_pod_ssh "$pod_id")
            printf "  %-8s %-20s %-12s %s\n" "$gpu" "$pod_id" "$status" "${ssh_info:-N/A}"
        done
        if [ "$found" -eq 0 ]; then
            echo "  (no active pods)"
        fi
        ;;
    ssh-info)
        POD_ID=$(get_active_pod "$GPU")
        if [ -z "$POD_ID" ]; then
            echo "No active ${GPU} pod" >&2
            exit 1
        fi
        get_pod_ssh "$POD_ID"
        ;;
    *)
        echo "Usage: ctl.sh [create|terminate|status|ssh-info] [gpu_type|all]"
        echo ""
        echo "Commands:"
        echo "  create <gpu>     - Create a new GPU pod (or reuse existing)"
        echo "  terminate <gpu>  - Terminate a specific GPU pod"
        echo "  terminate all    - Terminate all active pods"
        echo "  status           - Show status of all pods"
        echo "  ssh-info <gpu>   - Get SSH connection info (ip:port)"
        echo ""
        echo "GPU types: ${!GPU_TYPES[*]}"
        ;;
esac
