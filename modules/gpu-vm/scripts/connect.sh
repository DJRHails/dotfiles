#!/usr/bin/env bash
# Proxy command for SSH config. Creates pod on-demand and connects.
# Usage: connect.sh [gpu_type]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"

GPU="${1:-$DEFAULT_GPU}"

# Capture stdout to temp file while stderr flows to terminal in real-time
OUTFILE="${STATE_DIR}/.connect_out_$$"
get_or_create_pod "$GPU" > "$OUTFILE"
STATUS=$?

RESULT=$(cat "$OUTFILE")
rm -f "$OUTFILE"

if [ $STATUS -ne 0 ]; then
    exit 1
fi

IP=$(echo "$RESULT" | awk '{print $1}')
PORT=$(echo "$RESULT" | awk '{print $2}')

if [ -z "$IP" ] || [ -z "$PORT" ]; then
    echo "[gpu-vm] Failed to get connection info" >&2
    exit 1
fi

# Proxy the SSH connection via netcat
exec nc -w 10 "$IP" "$PORT"
