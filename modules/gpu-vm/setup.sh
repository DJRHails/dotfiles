#!/usr/bin/env bash
# GPU VM module setup

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="${SCRIPT_DIR}/scripts"

# Create config from example if it doesn't exist
if [ ! -f "${SCRIPTS_DIR}/config.sh" ]; then
    echo "[gpu-vm] Creating config.sh from example..."
    cp "${SCRIPTS_DIR}/config.sh.example" "${SCRIPTS_DIR}/config.sh"
    echo "[gpu-vm] Please edit ${SCRIPTS_DIR}/config.sh with your RunPod credentials"
fi

# Create state directory
mkdir -p "${SCRIPTS_DIR}/.state"

# Make scripts executable
chmod +x "${SCRIPTS_DIR}"/*.sh

echo "[gpu-vm] Setup complete"
echo "[gpu-vm] Available commands:"
echo "  ssh gpu       - Connect to default GPU (4090)"
echo "  ssh gpu-a100  - Connect to specific GPU type"
