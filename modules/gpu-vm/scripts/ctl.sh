#!/usr/bin/env bash
# Manual control: create, terminate, status
# Usage: ctl.sh [create|terminate|status] [gpu_type|all]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"

CMD="${1:-status}"
GPU="${2:-$DEFAULT_GPU}"

case "$CMD" in
    create|start)
        if [ -z "${GPU_TYPES[$GPU]}" ]; then
            echo "Unknown GPU type: ${GPU}. Available: ${!GPU_TYPES[*]}"
            exit 1
        fi
        echo "Creating ${GPU} pod..."
        RESULT=$(get_or_create_pod "$GPU")
        if [ $? -eq 0 ]; then
            IP=$(echo "$RESULT" | awk '{print $1}')
            PORT=$(echo "$RESULT" | awk '{print $2}')
            POD_ID=$(get_active_pod "$GPU")
            echo "Pod ready: ${POD_ID}"
            echo "SSH: ssh -p ${PORT} root@${IP}"
        fi
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
        for gpu in "${!GPU_TYPES[@]}"; do
            pod_id=$(get_active_pod "$gpu")
            if [ -n "$pod_id" ]; then
                status=$(get_pod_status "$pod_id" | jq -r '.desiredStatus // "UNKNOWN"')
                ssh_info=$(get_pod_ssh "$pod_id")
                printf "  %-8s %-20s %-12s %s\n" "$gpu" "$pod_id" "$status" "${ssh_info:-N/A}"
            else
                printf "  %-8s %-20s %-12s\n" "$gpu" "-" "NOT_CREATED"
            fi
        done
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
