#!/usr/bin/env bash
# Proxy command for SSH config. Creates pod on-demand and connects.
# Usage: connect.sh [gpu_type]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"

GPU="${1:-$DEFAULT_GPU}"

RESULT=$(get_or_create_pod "$GPU")
if [ $? -ne 0 ]; then
    exit 1
fi

IP=$(echo "$RESULT" | awk '{print $1}')
PORT=$(echo "$RESULT" | awk '{print $2}')

# Proxy the SSH connection via netcat
exec nc -w 10 "$IP" "$PORT"
