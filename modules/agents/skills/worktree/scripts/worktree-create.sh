#!/usr/bin/env bash
set -euo pipefail

# Create git worktrees under .data/worktrees/ and bootstrap them with
# copy-on-write copies of node_modules and untracked config files.
#
# Usage:
#   worktree-create.sh [-v] <branch> [<branch> ...]
#
# Multiple branches: git operations run sequentially (git lock),
# then post-checkout bootstrapping (CoW copies) runs in parallel.
#
# If a branch exists (locally or on origin) it is checked out;
# otherwise a new branch is created from HEAD.
#
# Inspired by https://notes.billmill.org/blog/2024/03/How_I_use_git_worktrees.html

RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
CLEAR="\033[0m"

worktree::die()  { printf '%b%s%b\n' "$RED"    "$1" "$CLEAR" >&2; exit 1; }
worktree::info() { printf '%b%s%b\n' "$GREEN"  "$1" "$CLEAR"; }
worktree::warn() { printf '%b%s%b\n' "$YELLOW" "$1" "$CLEAR"; }

# All CoW copy operations go through the `cpow` binary (~/.files/bin/cpow):
# macOS → clonefile(2), Linux → cp --reflink=auto, fallback → plain cp -R.
# If `cpow` isn't on PATH, provide a local shim with the same name so callers
# downstream don't need to branch.
if ! command -v cpow >/dev/null 2>&1; then
  cpow() {
    [[ -e "$2" ]] && { echo >&2 "cpow: destination already exists: $2"; return 1; }
    /bin/cp -Rc "$1" "$2" 2>/dev/null \
      || /bin/cp -R --reflink=auto "$1" "$2" 2>/dev/null \
      || /bin/cp -R "$1" "$2" 2>/dev/null \
      || { echo >&2 "cpow: unable to copy $1 to $2"; return 1; }
  }
  export -f cpow
fi

# --- Parallel checkout workers ---------------------------------------
# git >= 2.32 parallelises the "Updating files" step across N workers.
# Saturates SSDs far better than serial checkout.
CHECKOUT_WORKERS=$(sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 4)

# --- Fast path via APFS clonefile(2) ---------------------------------
# On macOS APFS, we can skip the serial ~12k-file checkout write by:
#   1. `git worktree add --no-checkout --detach <wt> <HEAD>`  (instant)
#   2. `git read-tree HEAD`                                   (populates index)
#   3. `cpow --batch-files` over every tracked path          (~3-5s for 12k files)
#   4. `update-index --refresh` w/ core.checkStat=minimal     (validates stat cache)
#   5. `git checkout <branch>` w/ core.checkStat=minimal      (tree-diff walk)
#
# End-to-end: ~7-8s vs ~180s for a 46GB repo with 12k tracked files.
# Requires main worktree to be clean (no dirty tracked files), otherwise
# we'd smuggle uncommitted content into the new worktree outside tree-diff.
worktree::fast_path_available() {
  [[ "$(uname)" == "Darwin" ]] || return 1
  command -v cpow >/dev/null 2>&1 || return 1
  git -C "$MAIN" diff --quiet HEAD 2>/dev/null || return 1
  git -C "$MAIN" diff --cached --quiet 2>/dev/null || return 1
  return 0
}

# Fast worktree creation. Populates $wt from $MAIN via clonefile(2),
# then tree-diff checkout to $branch. Returns 1 on any failure so the
# caller can fall back to plain `git worktree add`.
worktree::create_fast() {
  local branch="$1" wt="$2" main_head="$3"

  git -C "$MAIN" worktree add --no-checkout --detach "$wt" "$main_head" \
    >/dev/null 2>&1 || return 1
  git -C "$wt" read-tree HEAD >/dev/null 2>&1 || return 1

  if ! git -C "$MAIN" ls-files -z \
     | cpow --batch-files "$MAIN" "$wt" 2>/dev/null; then
    return 1
  fi

  git -C "$wt" -c core.checkStat=minimal update-index --refresh \
    >/dev/null 2>&1 || true

  if echo "$LOCAL_BRANCHES" | grep -qxF "$branch" \
     || echo "$REMOTE_BRANCHES" | grep -qxF "$branch"; then
    git -C "$wt" -c core.checkStat=minimal checkout "$branch" \
      >/dev/null 2>&1 || return 1
  else
    git -C "$wt" -c core.checkStat=minimal checkout -b "$branch" \
      >/dev/null 2>&1 || return 1
  fi
}

# --- Arg parsing ------------------------------------------------------
VERBOSE=
while [[ $# -gt 0 ]]; do
  case "$1" in
    -v|--verbose) VERBOSE=true; shift ;;
    -h|--help)
      echo "usage: worktree-create.sh [-v] <branch> [<branch> ...]"
      exit 0
      ;;
    *) break ;;
  esac
done

if [[ $# -lt 1 ]]; then
  echo >&2 "usage: worktree-create.sh [-v] <branch> [<branch> ...]"
  exit 1
fi

if [[ -n "$VERBOSE" ]]; then
  set -x
fi

BRANCHES=("$@")

# --- Resolve main worktree -------------------------------------------
MAIN=$(git worktree list | head -1 | awk '{print $1}')

# --- Pre-fetch (once for all branches) --------------------------------
# Only fetch branches that don't exist locally — skips network entirely
# when worktrees are for branches we already have (common case).
LOCAL_BRANCHES_EARLY=$(git for-each-ref --format='%(refname:lstrip=2)' refs/heads)
MISSING_REFSPECS=()
for branch in "${BRANCHES[@]}"; do
  if ! echo "$LOCAL_BRANCHES_EARLY" | grep -qxF "$branch"; then
    MISSING_REFSPECS+=("refs/heads/$branch:refs/remotes/origin/$branch")
  fi
done
if (( ${#MISSING_REFSPECS[@]} > 0 )); then
  git fetch origin "${MISSING_REFSPECS[@]}" 2>/dev/null || true
fi

# Cache local and remote branch lists once
LOCAL_BRANCHES=$(
  git for-each-ref --format='%(refname:lstrip=2)' refs/heads
)
REMOTE_BRANCHES=$(
  git for-each-ref --format='%(refname:lstrip=3)' refs/remotes/origin
)

# --- Pre-scan node_modules and config files (once) --------------------
# Pruning huge gitignored dirs (.venv, .next, .terraform, caches) is
# critical — without it, a 46GB repo takes ~60s to walk.
TMPDIR_WT=$(mktemp -d)
trap 'rm -rf "$TMPDIR_WT"' EXIT

# Shared prune expression for heavy/uninteresting trees.
PRUNE_DIRS=(
  .venv .next .terraform __pycache__ .ruff_cache .pytest_cache
  .mypy_cache .data .git .cursor dist build .turbo .cache
)
PRUNE_EXPR=()
for d in "${PRUNE_DIRS[@]}"; do
  PRUNE_EXPR+=(-name "$d" -o)
done
unset 'PRUNE_EXPR[${#PRUNE_EXPR[@]}-1]'  # drop trailing -o

NM_LIST="$TMPDIR_WT/node_modules.txt"
find "$MAIN" -maxdepth 6 \
  \( "${PRUNE_EXPR[@]}" \) -prune \
  -o -type d -name node_modules -print 2>/dev/null > "$NM_LIST"

CONFIG_LIST="$TMPDIR_WT/config_files.txt"
find "$MAIN" -maxdepth 4 \
  \( "${PRUNE_EXPR[@]}" -o -name node_modules \) -prune \
  -o -type f \( \
       -name '.env' -o -name '.env.local' -o -name '.envrc' \
    -o -name '.tool-versions' -o -name 'mise.toml' \
  \) -print 2>/dev/null > "$CONFIG_LIST"

# --- Phase 1: create worktrees sequentially (git lock) ----------------
# Prefer the clonefile(2) fast path when conditions allow; fall back to
# a parallel-checkout `git worktree add` otherwise.
FAST_PATH=
if worktree::fast_path_available; then
  FAST_PATH=1
  MAIN_HEAD=$(git -C "$MAIN" rev-parse HEAD)
  worktree::info "using APFS clonefile fast path (main clean, cpow on PATH)"
else
  worktree::info "using standard checkout path (fast path unavailable)"
fi

declare -A WORKTREE_PATHS
for branch in "${BRANCHES[@]}"; do
  dirname="${branch//\//-}"
  wt="$MAIN/.data/worktrees/$dirname"

  if [[ -d "$wt" ]]; then
    worktree::info "worktree already exists, will re-bootstrap: $wt"
    WORKTREE_PATHS["$branch"]="$wt"
    continue
  fi

  if [[ -n "$FAST_PATH" ]] && worktree::create_fast "$branch" "$wt" "$MAIN_HEAD"; then
    WORKTREE_PATHS["$branch"]="$wt"
    continue
  fi

  if [[ -n "$FAST_PATH" ]]; then
    worktree::warn "fast path failed for $branch, falling back to standard checkout"
    # Clean up any partial state the fast path may have left behind.
    [[ -d "$wt" ]] && git -C "$MAIN" worktree remove --force "$wt" 2>/dev/null || true
  fi

  if echo "$LOCAL_BRANCHES" | grep -qxF "$branch" \
     || echo "$REMOTE_BRANCHES" | grep -qxF "$branch"; then
    git -c "checkout.workers=$CHECKOUT_WORKERS" worktree add "$wt" "$branch" \
      || { worktree::warn "failed to create worktree for $branch"; continue; }
  else
    git -c "checkout.workers=$CHECKOUT_WORKERS" worktree add -b "$branch" "$wt" \
      || { worktree::warn "failed to create worktree for $branch"; continue; }
  fi

  WORKTREE_PATHS["$branch"]="$wt"
done

# --- Phase 2: bootstrap worktrees in parallel -------------------------
# Export what the bootstrap function needs
export MAIN NM_LIST CONFIG_LIST
# Only re-export cpow if it's a shell function (shim); the real binary
# at ~/.files/bin/cpow is already on PATH for subshells.
if declare -F cpow >/dev/null 2>&1; then
  export -f cpow
fi
export -f worktree::info worktree::warn

worktree::bootstrap() {
  local branch="$1"
  local wt="$2"

  # Symlink .data/ to main so sibling worktrees and shared caches
  # (anything outside .data/worktrees/) are visible without duplication.
  if [[ ! -e "$wt/.data" && -d "$MAIN/.data" ]]; then
    ln -s "$MAIN/.data" "$wt/.data"
  fi

  # Collect src\tdst pairs for node_modules that need cloning.
  # Tab separator instead of NUL — survives bash `read` and variable interp.
  local pairs=""
  local main_nm rel wt_nm parent
  while IFS= read -r main_nm; do
    [[ -z "$main_nm" ]] && continue
    rel=${main_nm#"$MAIN"/}
    wt_nm="$wt/$rel"
    parent=$(dirname "$wt_nm")
    [[ -d "$parent" ]] || continue
    [[ -e "$wt_nm" ]] && continue
    pairs+="${main_nm}"$'\t'"${wt_nm}"$'\n'
  done < "$NM_LIST"

  # Parallel directory-level clonefile(2). One syscall per directory —
  # orders of magnitude faster than `cp -Rc` which recurses per-file.
  if [[ -n "$pairs" ]]; then
    local clone_out
    if clone_out=$(printf '%s' "$pairs" | cpow --batch-dirs 2>&1); then
      echo "  [$branch] cloned $(grep -c . <<<"$pairs") node_modules tree(s)"
    else
      worktree::warn "  [$branch] parallel node_modules clone failed: $clone_out"
      while IFS=$'\t' read -r src dst; do
        [[ -z "$src" ]] && continue
        cpow "$src" "$dst"
      done <<<"$pairs"
    fi
  else
    # Fallback: sequential cpow (cpow absent — shim or plain cp chain)
    while IFS= read -r main_nm; do
      [[ -z "$main_nm" ]] && continue
      rel=${main_nm#"$MAIN"/}
      wt_nm="$wt/$rel"
      parent=$(dirname "$wt_nm")
      [[ -d "$parent" ]] || continue
      [[ -e "$wt_nm" ]] && continue
      cpow "$main_nm" "$wt_nm"
    done < "$NM_LIST"
  fi

  local f wt_f
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    rel=${f#"$MAIN"/}
    wt_f="$wt/$rel"
    [[ -e "$wt_f" ]] && continue
    cpow "$f" "$wt_f"
    echo "  [$branch] copied: $rel"
  done < "$CONFIG_LIST"

  if [[ -f "$wt/.envrc" ]]; then
    direnv allow "$wt" 2>/dev/null || true
  fi

  worktree::info "bootstrapped: $wt"
}

PIDS=()
for branch in "${!WORKTREE_PATHS[@]}"; do
  wt="${WORKTREE_PATHS[$branch]}"
  worktree::bootstrap "$branch" "$wt" &
  PIDS+=($!)
done

# Wait for all bootstrap jobs; collect failures
FAILED=0
for pid in "${PIDS[@]}"; do
  if ! wait "$pid"; then
    ((FAILED++))
  fi
done

if [[ $FAILED -gt 0 ]]; then
  worktree::warn "$FAILED bootstrap job(s) failed"
  exit 1
fi

worktree::info "done: ${#WORKTREE_PATHS[@]} worktree(s) created"
