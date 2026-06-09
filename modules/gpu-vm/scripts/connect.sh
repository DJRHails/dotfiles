#!/usr/bin/env bash
# Proxy command for SSH config. Creates pod on-demand and connects.
# Usage: connect.sh [gpu_type]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"

GPU="${1:-$DEFAULT_GPU}"

# Capture stdout to temp file while stderr flows to terminal in real-time.
# Clean up even when ssh kills the ProxyCommand mid-boot (HUP/INT/TERM);
# the exec below replaces the process, by which point the file is removed.
OUTFILE=$(mktemp "${STATE_DIR}/.connect_out.XXXXXX") || exit 1
trap 'rm -f "$OUTFILE"' EXIT
trap 'exit 1' HUP INT TERM

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
exec nc "$IP" "$PORT"
