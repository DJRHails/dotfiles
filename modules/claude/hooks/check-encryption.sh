#!/bin/bash
# Hook: Detect when encrypted content escapes its encryption boundary
# Catches: moved/copied files, renamed folders, content pasted elsewhere

set -e

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Only check on git commit/add commands
if [[ ! "$COMMAND" =~ ^git[[:space:]]+(commit|add) ]]; then
    exit 0
fi

CWD=$(echo "$INPUT" | jq -r '.cwd')
cd "$CWD"

# Check if this repo uses transcrypt
if ! git config --get filter.crypt.clean &>/dev/null; then
    exit 0
fi

# Get encryption patterns from .gitattributes
declare -a CRYPT_PATTERNS
if [[ -f .gitattributes ]]; then
    while IFS= read -r line; do
        [[ -z "$line" || "$line" =~ ^# ]] && continue
        if [[ "$line" =~ filter=crypt ]]; then
            pattern=$(echo "$line" | awk '{print $1}')
            CRYPT_PATTERNS+=("$pattern")
        fi
    done < .gitattributes
fi

[[ ${#CRYPT_PATTERNS[@]} -eq 0 ]] && exit 0

# Get list of currently encrypted files (decrypted in worktree)
ENCRYPTED_FILES=$(git ls-crypt 2>/dev/null || true)

# Signature of a file's content (first 500 chars, whitespace-stripped, first
# 100 chars), hashed per-platform: md5 on darwin, md5sum elsewhere.
content_signature() {
    local normalized
    # LC_ALL=C: macOS tr aborts on bytes that are invalid UTF-8, which made
    # every binary file hash to the empty string and collide with each other.
    # \0 stripped explicitly: bash command substitution warns on (and drops)
    # null bytes, which encrypted binary content is full of
    normalized=$(head -c 500 "$1" 2>/dev/null | LC_ALL=C tr -d '[:space:]\0' | head -c 100)
    if [[ "$(uname)" == "Darwin" ]]; then
        printf '%s' "$normalized" | md5 -q
    else
        printf '%s' "$normalized" | md5sum | cut -d' ' -f1
    fi
}

# Build content signatures of encrypted files
declare -A ENCRYPTED_SIGNATURES
while IFS= read -r file; do
    [[ -z "$file" || ! -f "$file" ]] && continue
    sig=$(content_signature "$file")
    ENCRYPTED_SIGNATURES["$sig"]="$file"
done <<< "$ENCRYPTED_FILES"

# Function to check if path matches any crypt pattern
matches_crypt_pattern() {
    local filepath="$1"
    local regex
    for pattern in "${CRYPT_PATTERNS[@]}"; do
        # Convert glob to regex; placeholder keeps the second sed from
        # rewriting the '*' inside the '.*' that '**' just produced
        regex=$(echo "$pattern" | sed -e 's/\*\*/__GLOBSTAR__/g' -e 's/\*/[^\/]*/g' -e 's/__GLOBSTAR__/.*/g')
        if [[ "$filepath" =~ ^$regex$ ]]; then
            return 0
        fi
    done
    return 1
}

ERRORS=()

# Check staged files that are NOT in encrypted paths
STAGED_FILES=$(git diff --cached --name-only 2>/dev/null || true)

while IFS= read -r file; do
    [[ -z "$file" || ! -f "$file" ]] && continue

    # Skip if file IS in an encrypted path (it's fine)
    if matches_crypt_pattern "$file"; then
        continue
    fi

    # Check if this file's content matches any encrypted file
    sig=$(content_signature "$file")

    if [[ -n "${ENCRYPTED_SIGNATURES[$sig]:-}" ]]; then
        original="${ENCRYPTED_SIGNATURES[$sig]}"
        # A file matching itself is inside the boundary by definition
        # (git ls-crypt only lists files the crypt attribute covers)
        [[ "$original" == "$file" ]] && continue
        ERRORS+=("'$file' appears to contain content from encrypted file '$original' but is not in an encrypted path")
    fi
done <<< "$STAGED_FILES"

# Report errors
if [[ ${#ERRORS[@]} -gt 0 ]]; then
    jq -n \
        --arg reason "$(printf '• %s\n' "${ERRORS[@]}")" \
        '{
            decision: "block",
            reason: ("Encrypted content may have escaped encryption boundary:\n\n" + $reason + "\n\nEither:\n1. Move the file back to an encrypted path\n2. Add the new path to .gitattributes with filter=crypt\n3. Remove sensitive content from the file")
        }'
    exit 0
fi

exit 0
