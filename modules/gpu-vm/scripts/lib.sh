#!/usr/bin/env bash
# Core functions for GPU VM management

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"

# Ensure state directory exists
mkdir -p "$STATE_DIR"

# REST API base URL
RUNPOD_API_URL="https://rest.runpod.io/v1"

# Check if API key is set
check_api_key() {
    if [ -z "$RUNPOD_API_KEY" ]; then
        echo "[gpu-vm] Error: RUNPOD_API_KEY not set" >&2
        echo "[gpu-vm] Set it in your environment or config.sh" >&2
        return 1
    fi
}

# Execute a REST API call
runpod_api() {
    local method="$1"
    local endpoint="$2"
    local data="$3"
    check_api_key || return 1

    if [ -n "$data" ]; then
        curl -s -X "$method" "${RUNPOD_API_URL}${endpoint}" \
            -H "Authorization: Bearer ${RUNPOD_API_KEY}" \
            -H "Content-Type: application/json" \
            -d "$data"
    else
        curl -s -X "$method" "${RUNPOD_API_URL}${endpoint}" \
            -H "Authorization: Bearer ${RUNPOD_API_KEY}"
    fi
}

# Get pod status and connection info
get_pod_status() {
    local pod_id="$1"
    runpod_api GET "/pods/${pod_id}"
}

# Get SSH connection details (ip:port)
get_pod_ssh() {
    local pod_id="$1"
    get_pod_status "$pod_id" | jq -r '
        if .publicIp and .portMappings["22"] then
            "\(.publicIp):\(.portMappings["22"])"
        else
            empty
        end
    ' 2>/dev/null
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

    # Create pod with SSH support using REST API
    # Note: Network volume locks to US-TX-3 which is often congested, so we skip it
    local pub_key
    pub_key=$(cat ~/.ssh/id_ed25519_runpod.pub 2>/dev/null || echo '')

    local result
    result=$(runpod_api POST "/pods" "{
        \"name\": \"${name}\",
        \"imageName\": \"runpod/pytorch:2.2.0-py3.10-cuda12.1.1-devel-ubuntu22.04\",
        \"gpuTypeIds\": [\"${gpu_type}\"],
        \"containerDiskInGb\": 50,
        \"volumeInGb\": 50,
        \"gpuCount\": 1,
        \"supportPublicIp\": true,
        \"ports\": [\"22/tcp\"],
        \"env\": {
            \"PUBLIC_KEY\": \"${pub_key}\"
        }
    }")

    local pod_id
    pod_id=$(echo "$result" | jq -r '.id // empty')

    if [ -z "$pod_id" ]; then
        local error_msg
        error_msg=$(echo "$result" | jq -r '.error // "Unknown error"')
        echo "[gpu-vm] Failed to create pod: ${error_msg}" >&2
        return 1
    fi

    echo "$pod_id"
}

# Terminate a pod
terminate_pod() {
    local pod_id="$1"
    runpod_api DELETE "/pods/${pod_id}"
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
            # Verify SSH banner is valid (not proxy/init noise)
            if ssh-keyscan -p "$port" -T 3 "$ip" 2>/dev/null | grep -q ssh; then
                echo "[gpu-vm] Pod ready in ${elapsed}s" >&2
                echo "$ip $port"
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
