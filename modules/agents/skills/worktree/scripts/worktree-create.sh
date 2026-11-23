#!/usr/bin/env bash
set -euo pipefail

# This script needs bash >= 4.4: associative arrays (4.0), and empty arrays that expand under
# `set -u` (4.4). macOS ships 3.2 as /bin/bash, which is the `bash` a non-interactive shell
# finds first, and there the script used to die on `declare -A` half-way through. So before
# anything else runs, hand over to a new enough bash, or stop. Everything in this block must
# itself run on bash 3.2.
worktree::bash_is_new_enough() {
  "$1" -c '((BASH_VERSINFO[0] > 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 4)))' \
    2>/dev/null
}
if ! worktree::bash_is_new_enough "$BASH"; then
  while IFS= read -r candidate; do
    if worktree::bash_is_new_enough "$candidate"; then
      exec "$candidate" "${BASH_SOURCE[0]}" "$@"
    fi
  done < <(
    type -ap bash
    printf '%s\n' /opt/homebrew/bin/bash /usr/local/bin/bash
  )
  {
    echo "worktree-create.sh needs bash >= 4.4, but is running under bash $BASH_VERSION ($BASH)"
    echo "and found no newer bash on PATH, at /opt/homebrew/bin/bash or at /usr/local/bin/bash."
    echo "Install one (macOS: brew install bash) and run this command again."
  } >&2
  exit 1
fi

# Create git worktrees under .data/worktrees/ and bootstrap them with
# copy-on-write copies of node_modules and untracked config files, plus the
# submodules main has checked out (sharing main's objects).
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

worktree::die() {
  printf '%b%s%b\n' "$RED" "$1" "$CLEAR" >&2
  exit 1
}
worktree::info() { printf '%b%s%b\n' "$GREEN" "$1" "$CLEAR"; }
worktree::warn() { printf '%b%s%b\n' "$YELLOW" "$1" "$CLEAR"; }

# All CoW copy operations go through the `cpow` binary (~/.files/bin/cpow):
# macOS → clonefile(2), Linux → cp --reflink=auto, fallback → plain cp -R.
# If `cpow` isn't on PATH, provide a local shim with the same name so callers
# downstream don't need to branch.
if ! command -v cpow >/dev/null 2>&1; then
  cpow() {
    [[ -e "$2" ]] && {
      echo >&2 "cpow: destination already exists: $2"
      return 1
    }
    /bin/cp -Rc "$1" "$2" 2>/dev/null \
      || /bin/cp -R --reflink=auto "$1" "$2" 2>/dev/null \
      || /bin/cp -R "$1" "$2" 2>/dev/null \
      || {
        echo >&2 "cpow: unable to copy $1 to $2"
        return 1
      }
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
#   3. `cpow --batch-files` over every file in HEAD's tree   (~3-5s for 12k files;
#      gitlinks become empty dirs, filled by worktree::init_submodules)
#   4. `update-index --refresh` w/ core.checkStat=minimal     (validates stat cache)
#   5. `reset --hard HEAD`                                    (rewrites only dirty files)
#   6. `git checkout <branch>` w/ core.checkStat=minimal      (tree-diff walk)
#
# End-to-end: ~7-8s vs ~180s for a 46GB repo with 12k tracked files.
#
# MAIN is never modified. It is shared by live agent sessions, and the old answer to a dirty
# MAIN (stash its edits, pop them on EXIT) reverted their files mid-flight and stranded their
# work in dangling stash commits when the pop conflicted, popped someone else's stash, or never
# ran. Instead, step 3 clones whatever MAIN's working tree holds, and step 5 throws away, inside
# the new worktree only, any uncommitted content that came with it.
worktree::fast_path_available() {
  [[ "$(uname)" == "Darwin" ]] || return 1
  command -v cpow >/dev/null 2>&1 || return 1
  # This path clonefiles MAIN's *working tree*, so its ref and its files must agree — it
  # cannot base on the upstream tip the way the standard path does. When the local checkout
  # has drifted behind that base, decline, so the caller falls through to a checkout that
  # starts from current code. A "fast" worktree built on a stale base is not a saving: it
  # cost one lane 28 rebase conflicts across 7 files.
  #
  # Measured against $NEW_BRANCH_BASE, the same ref (and the same fetch) the standard path
  # bases new branches on, so a repo whose default branch is not `main` gets the guard too.
  # Fails closed: if the count can't be taken, take the correct-but-slower path.
  if [[ "$NEW_BRANCH_BASE" != HEAD ]]; then
    local behind
    behind=$(git -C "$MAIN" rev-list --count "HEAD..$NEW_BRANCH_BASE" 2>/dev/null) || return 1
    ((behind == 0)) || return 1
  fi
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

  # Gitlinks (submodules) are not cloned: MAIN's copy carries a relative `.git` gitfile that
  # resolves to nothing from inside the worktree, which makes every git command there fatal.
  # Each gets the empty directory `git worktree add` would create, and
  # worktree::init_submodules populates it during bootstrap.
  # The list comes from the commit's tree, not MAIN's index, so files MAIN has staged but not
  # committed stay out. Files MAIN has deleted are skipped here and restored by the reset below.
  local tree="$TMPDIR_WT/fast-path-tree" files="$TMPDIR_WT/fast-path-files"
  local entry path link gitlinks=()
  git -C "$MAIN" ls-tree -r -z --full-tree "$main_head" >"$tree" || return 1
  while IFS= read -r -d '' entry; do
    path="${entry#*$'\t'}"
    if [[ "$entry" == 160000\ * ]]; then
      gitlinks+=("$path")
    elif [[ -e "$MAIN/$path" || -L "$MAIN/$path" ]]; then
      printf '%s\0' "$path"
    fi
  done <"$tree" >"$files"
  cpow --batch-files "$MAIN" "$wt" <"$files" 2>/dev/null || return 1
  for link in "${gitlinks[@]}"; do
    mkdir -p "$wt/$link" || return 1
  done

  git -C "$wt" -c core.checkStat=minimal update-index --refresh \
    >/dev/null 2>&1 || true
  # The clone carried MAIN's uncommitted edits along. The refresh above has flagged each file
  # whose content differs from the commit, so this rewrites just those (and restores deleted
  # ones) inside the new worktree. Fails closed: anything left dirty falls back to the slow path.
  git -C "$wt" -c core.checkStat=minimal -c submodule.recurse=false reset --hard --quiet HEAD \
    >/dev/null 2>&1 || return 1
  git -C "$wt" -c submodule.recurse=false diff --quiet HEAD >/dev/null 2>&1 || return 1

  # submodule.recurse is off for the switch: with it on (modules/git/gitconfig sets it), a branch
  # whose gitlink differs from MAIN's makes checkout update the still-uninitialised submodule,
  # which dies with "could not reset submodule index". init_submodules checks it out afterwards.
  local checkout=(git -C "$wt" -c core.checkStat=minimal -c submodule.recurse=false checkout)
  if echo "$LOCAL_BRANCHES" | grep -qxF "$branch" \
    || echo "$REMOTE_BRANCHES" | grep -qxF "$branch"; then
    "${checkout[@]}" "$branch" >/dev/null 2>&1 || return 1
  else
    "${checkout[@]}" -b "$branch" >/dev/null 2>&1 || return 1
  fi
}

# --- Arg parsing ------------------------------------------------------
VERBOSE=
while [[ $# -gt 0 ]]; do
  case "$1" in
    -v | --verbose)
      VERBOSE=true
      shift
      ;;
    -h | --help)
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
if ((${#MISSING_REFSPECS[@]} > 0)); then
  git fetch origin "${MISSING_REFSPECS[@]}" 2>/dev/null || true
fi

# Base for a *new* branch: the upstream tip, not the local checkout's HEAD.
# `git worktree add -b X <path>` with no commit-ish uses HEAD, and a long-lived main
# checkout drifts behind origin constantly (22 commits, on the day this was written) —
# so every "fresh" worktree silently started from stale code. One agent lane built a
# whole viewer change against a 22-commit-old base and hit 28 rebase conflicts across
# 7 files for no reason but this default. Falls back to HEAD when there is no origin,
# and never touches an existing branch (that arm checks the branch out as asked).
NEW_BRANCH_BASE=HEAD
if git rev-parse --verify --quiet origin/HEAD >/dev/null 2>&1; then
  NEW_BRANCH_BASE=$(git rev-parse --abbrev-ref origin/HEAD)
elif git rev-parse --verify --quiet origin/main >/dev/null 2>&1; then
  NEW_BRANCH_BASE=origin/main
fi
if [[ "$NEW_BRANCH_BASE" != HEAD ]]; then
  git fetch --quiet origin 2>/dev/null || true
  BEHIND=$(git rev-list --count "HEAD..$NEW_BRANCH_BASE" 2>/dev/null || echo 0)
  if ((BEHIND > 0)); then
    worktree::info "new branches will base on $NEW_BRANCH_BASE (local HEAD is $BEHIND behind)"
  fi
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
unset 'PRUNE_EXPR[${#PRUNE_EXPR[@]}-1]' # drop trailing -o

NM_LIST="$TMPDIR_WT/node_modules.txt"
find "$MAIN" -maxdepth 6 \
  \( "${PRUNE_EXPR[@]}" \) -prune \
  -o -type d -name node_modules -print 2>/dev/null >"$NM_LIST"

CONFIG_LIST="$TMPDIR_WT/config_files.txt"
find "$MAIN" -maxdepth 4 \
  \( "${PRUNE_EXPR[@]}" -o -name node_modules \) -prune \
  -o -type f \( \
  -name '.env' -o -name '.env.local' -o -name '.envrc' \
  -o -name '.tool-versions' -o -name 'mise.toml' \
  \) -print 2>/dev/null >"$CONFIG_LIST"

# --- Phase 1: create worktrees sequentially (git lock) ----------------
# Prefer the clonefile(2) fast path when conditions allow; fall back to
# a parallel-checkout `git worktree add` otherwise.
FAST_PATH=
if worktree::fast_path_available; then
  FAST_PATH=1
  MAIN_HEAD=$(git -C "$MAIN" rev-parse HEAD)
  worktree::info "using APFS clonefile fast path (cpow on PATH, main not behind base)"
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
      || {
        worktree::warn "failed to create worktree for $branch"
        continue
      }
  else
    git -c "checkout.workers=$CHECKOUT_WORKERS" worktree add -b "$branch" "$wt" \
      "$NEW_BRANCH_BASE" \
      || {
        worktree::warn "failed to create worktree for $branch"
        continue
      }
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

# Initialise each submodule that MAIN has checked out, borrowing MAIN's objects through
# `--reference`, so the clone from the remote transfers only what MAIN lacks (the remote must
# still be reachable). A worktree keeps its own submodule
# repositories under .git/worktrees/<name>/modules; left to a later
# `git submodule update --init`, each is a full clone (158 MB a worktree in hails.info,
# 2026-11-21). With the reference it stores only what the branch adds. Submodules MAIN
# has not checked out are left for the caller, as before.
worktree::init_submodules() {
  local branch="$1" wt="$2" path main_gitdir
  [[ -f "$wt/.gitmodules" ]] || return 0
  while IFS= read -r path; do
    [[ -z "$path" || -e "$wt/$path/.git" || ! -e "$MAIN/$path/.git" ]] && continue
    main_gitdir=$(git -C "$MAIN/$path" rev-parse --absolute-git-dir) || continue
    if git -C "$wt" submodule update --init --reference "$main_gitdir" -- "$path" \
      >/dev/null 2>&1; then
      echo "  [$branch] submodule from local reference: $path"
    else
      local hint="run 'git submodule update --init -- $path' in the worktree"
      worktree::warn "  [$branch] submodule init failed: $path ($hint)"
    fi
  done < <(git -C "$wt" config -f .gitmodules --get-regexp '\.path$' | awk '{print $2}')
}
export -f worktree::init_submodules

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
  done <"$NM_LIST"

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
    done <"$NM_LIST"
  fi

  local f wt_f
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    rel=${f#"$MAIN"/}
    wt_f="$wt/$rel"
    [[ -e "$wt_f" ]] && continue
    cpow "$f" "$wt_f"
    echo "  [$branch] copied: $rel"
  done <"$CONFIG_LIST"

  worktree::init_submodules "$branch" "$wt"

  if [[ -f "$wt/.envrc" ]]; then
    direnv allow "$wt" 2>/dev/null || true
  fi

  # Python/uv repos: install the project venv so the worktree is runnable, not just checked out —
  # the Python analogue of the node_modules CoW clone above (a fresh worktree has no .venv, and .venv
  # lives at the repo root, not under the symlinked .data, so it is not shared). uv's global cache
  # hardlinks packages, so this is fast. Default groups only (uv includes the dev group by
  # default); extras are installed on demand.
  if [[ -f "$wt/pyproject.toml" ]] && command -v uv >/dev/null 2>&1; then
    if (cd "$wt" && uv sync >/dev/null 2>&1); then
      echo "  [$branch] uv sync"
    else
      worktree::warn "  [$branch] uv sync failed — run 'uv sync' in the worktree manually"
    fi
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
