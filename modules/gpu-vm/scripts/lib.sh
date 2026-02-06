#!/usr/bin/env bash
# Core functions for GPU VM management

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"

# Ensure state directory exists
mkdir -p "$STATE_DIR"

# Check if API key is set
check_api_key() {
    if [ -z "$RUNPOD_API_KEY" ]; then
        echo "[gpu-vm] Error: RUNPOD_API_KEY not set" >&2
        echo "[gpu-vm] Set it in your environment or config.sh" >&2
        return 1
    fi
}

# Execute a GraphQL query against the RunPod API
runpod_gql() {
    local query="$1"
    check_api_key || return 1
    curl -s -X POST "https://api.runpod.io/graphql" \
        -H "Content-Type: application/json" \
        -H "api-key: ${RUNPOD_API_KEY}" \
        -d "{\"query\": \"$query\"}"
}

# Get pod status and connection info
get_pod_status() {
    local pod_id="$1"
    runpod_gql "{ pod(input: {podId: \\\"${pod_id}\\\"}) { id desiredStatus runtime { ports { ip isIpPublic privatePort publicPort type } } } }" \
        | jq -r '.data.pod'
}

# Get SSH connection details (ip:port)
get_pod_ssh() {
    local pod_id="$1"
    get_pod_status "$pod_id" | jq -r '
        .runtime.ports[]?
        | select(.privatePort == 22 and .isIpPublic == true)
        | "\(.ip):\(.publicPort)"
    ' 2>/dev/null | head -1
}

# Create a new pod with the specified GPU type
# Returns the pod ID on success
create_pod() {
    local gpu="$1"
    local gpu_type="${GPU_TYPES[$gpu]}"

    if [ -z "$gpu_type" ]; then
        echo "[gpu-vm] Unknown GPU type: ${gpu}. Available: ${!GPU_TYPES[*]}" >&2
        return 1
    fi

    local name="gpu-${gpu}-$(date +%s)"

    # Create pod with network volume
    local result
    result=$(runpod_gql "mutation { podFindAndDeployOnDemand(input: { name: \\\"${name}\\\", templateId: \\\"${TEMPLATE_ID}\\\", gpuTypeId: \\\"${gpu_type}\\\", volumeInGb: 0, containerDiskInGb: 20, networkVolumeId: \\\"${NETWORK_VOLUME_ID}\\\", gpuCount: 1, minVcpuCount: 4, minMemoryInGb: 16 }) { id } }")

    local pod_id
    pod_id=$(echo "$result" | jq -r '.data.podFindAndDeployOnDemand.id // empty')

    if [ -z "$pod_id" ]; then
        echo "[gpu-vm] Failed to create pod: $(echo "$result" | jq -r '.errors[0].message // "Unknown error"')" >&2
        return 1
    fi

    echo "$pod_id"
}

# Terminate a pod
terminate_pod() {
    local pod_id="$1"
    runpod_gql "mutation { podTerminate(input: {podId: \\\"${pod_id}\\\"}) }"
}

# Get the active pod for a GPU type (if any)
get_active_pod() {
    local gpu="${1:-$DEFAULT_GPU}"
    local state_file="${STATE_DIR}/${gpu}.pod"

    if [ -f "$state_file" ]; then
        cat "$state_file"
    fi
}

# Save the active pod for a GPU type
save_active_pod() {
    local gpu="$1"
    local pod_id="$2"
    echo "$pod_id" > "${STATE_DIR}/${gpu}.pod"
}

# Clear the active pod for a GPU type
clear_active_pod() {
    local gpu="${1:-$DEFAULT_GPU}"
    rm -f "${STATE_DIR}/${gpu}.pod"
}

# Check if a pod is still running and SSH-accessible
is_pod_alive() {
    local pod_id="$1"
    local status
    status=$(get_pod_status "$pod_id" | jq -r '.desiredStatus // "UNKNOWN"')
    [ "$status" = "RUNNING" ]
}

# Get or create a pod, wait for SSH, return "ip port"
get_or_create_pod() {
    local gpu="${1:-$DEFAULT_GPU}"

    check_api_key || return 1

    # Check for existing active pod
    local pod_id
    pod_id=$(get_active_pod "$gpu")

    if [ -n "$pod_id" ]; then
        # Verify it's still running
        if is_pod_alive "$pod_id"; then
            local ssh_addr
            ssh_addr=$(get_pod_ssh "$pod_id")
            if [ -n "$ssh_addr" ] && [ "$ssh_addr" != "null" ]; then
                local ip port
                ip=$(echo "$ssh_addr" | cut -d: -f1)
                port=$(echo "$ssh_addr" | cut -d: -f2)
                echo "$ip $port"
                echo "[gpu-vm] Reusing existing pod ${pod_id}" >&2
                return 0
            fi
        else
            echo "[gpu-vm] Previous pod ${pod_id} is no longer running" >&2
            clear_active_pod "$gpu"
        fi
    fi

    # Create a new pod
    echo "[gpu-vm] Creating new ${gpu} pod..." >&2
    pod_id=$(create_pod "$gpu")
    if [ $? -ne 0 ] || [ -z "$pod_id" ]; then
        return 1
    fi

    save_active_pod "$gpu" "$pod_id"
    echo "[gpu-vm] Pod created: ${pod_id}" >&2

    # Wait for SSH to become available
    local elapsed=0
    while [ "$elapsed" -lt "$BOOT_TIMEOUT" ]; do
        local ssh_addr
        ssh_addr=$(get_pod_ssh "$pod_id")
        if [ -n "$ssh_addr" ] && [ "$ssh_addr" != "null" ]; then
            local ip port
            ip=$(echo "$ssh_addr" | cut -d: -f1)
            port=$(echo "$ssh_addr" | cut -d: -f2)
            # Verify SSH is actually responding
            if ssh -o ConnectTimeout=3 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
                   -i ~/.ssh/id_ed25519_runpod -p "$port" "root@${ip}" true 2>/dev/null; then
                echo "$ip $port"
                echo "[gpu-vm] Pod ready in ${elapsed}s" >&2
                return 0
            fi
        fi
        sleep 5
        elapsed=$((elapsed + 5))
        echo "[gpu-vm] Waiting for SSH... (${elapsed}s)" >&2
    done

    echo "[gpu-vm] Timed out after ${BOOT_TIMEOUT}s" >&2
    return 1
}

# Terminate all active pods
terminate_all_pods() {
    for state_file in "${STATE_DIR}"/*.pod; do
        [ -f "$state_file" ] || continue
        local gpu pod_id
        gpu=$(basename "$state_file" .pod)
        pod_id=$(cat "$state_file")
        echo "[gpu-vm] Terminating ${gpu} pod (${pod_id})..." >&2
        terminate_pod "$pod_id" > /dev/null
        rm -f "$state_file"
    done
}
