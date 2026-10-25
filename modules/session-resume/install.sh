#!/usr/bin/env bash
set -euo pipefail

# Pin conversion semantics; upgrades must be checked against both native formats.
revision=e7f1868bb9ae1bc213307a86e16465887b78acd9
destination="${XDG_DATA_HOME:-$HOME/.local/share}/agent-session-bridge"
node -e 'const [major, minor] = process.versions.node.split(".").map(Number); if (major < 22 || (major === 22 && minor < 5)) { console.error("Session conversion requires Node.js 22.5+"); process.exit(1); }'
if [[ ! -d "$destination/.git" ]]; then
  git clone https://github.com/bakhtiersizhaev/ai-session-bridge.git "$destination"
fi
git -C "$destination" fetch origin "$revision"
git -C "$destination" checkout --detach "$revision"
(cd "$destination" && npm ci --ignore-scripts --include=dev)
echo "Installed native Claude/Codex session converter at $destination"
