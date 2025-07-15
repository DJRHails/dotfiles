alias g="git"

alias gs='git status -sb' # upgrade your git if -sb breaks for you. it's fun.
alias gl='git pull --prune'
alias glog="git log --graph --pretty=format:'%Cred%h%Creset %an: %s - %Creset %C(yellow)%d%Creset %Cgreen(%cr)%Creset' --abbrev-commit --date=relative"
alias gp='git push origin HEAD'

# Remove `+` and `-` from start of diff lines; just rely upon color.
alias gd='git diff --color | sed "s/^\([^-+ ]*\)[-+ ]/\\1/" | less -r'

# Fuzzy search to checkout branches
alias fb='git checkout `git branch | fzf | sed s:remotes/origin/::g`'

ghopen() {
  open "https://github.com/$1"
}

genignore() {
  local language=$1

  # fetch the gitignore file from gitignore.io
  curl -L -s "https://www.gitignore.io/api/$language" | grep -v toptal >> .gitignore
}

# Specifies the clipboard output format is html
# commonly used with cbh | 2md
alias cbh='cb -t html'

# Generic function to find a directory in the path hierarchy
find_in_path() {
    local target_dir=$1
    local start_dir=${2:-$(pwd)}
    
    local dir="$start_dir"
    while [[ "$dir" != "/" ]]; do
        if [[ -d "$dir/$target_dir" ]]; then
            echo "$dir/$target_dir"
            return 0
        fi
        dir=$(dirname "$dir")
    done
    
    return 1
}

# Extract GitHub org/repo from URL
parse_github_url() {
    local url=$1
    # Use sed for better compatibility across shells
    local org_repo=$(echo "$url" | sed -E 's/.*github\.com[:/]([^/]+\/[^/]+)(\.git)?$/\1/')
    
    # Verify we got a valid result
    if [[ -n "$org_repo" && "$org_repo" != "$url" ]]; then
        echo "$org_repo"
        return 0
    fi
    return 1
}


# Clone a github repo and add a worktree for the specified branch
gwtclone() {
    local repo_url=$1
    local branch=${2:-}
    
    # Extract org/repo from GitHub URL
    local org_repo=$(parse_github_url "$repo_url")
    if [[ -z "$org_repo" ]]; then
        echo "Error: Not a GitHub repository"
        return 1
    fi
    
    # Find or create github.com directory
    local github_root=$(find_in_path "github.com") || {
      echo "Error: Could not find github.com directory structure"
      github_root="$(pwd)/github.com"
      mkdir -p "$github_root"
    }
    
    local clone_path="$github_root/$org_repo/main"
    echo "Cloning $repo_url to $clone_path"
    
    # Clone to structured directory
    mkdir -p "$(dirname "$clone_path")"
    git clone "$repo_url" "$clone_path"
    
    # Add branch worktree if specified
    if [[ -n "$branch" ]]; then
        cd "$clone_path"
        git fetch origin "$branch" && git worktree add "../$branch" "origin/$branch"
        cd - > /dev/null
    fi
}

# Add worktree for branch in existing repo
gwta() {
    local branch=$1
    
    if [[ -z "$branch" ]]; then
        echo "Usage: gwt <branch-name>"
        return 1
    fi
    
    # Get the repo root and remote URL
    local repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || {
        echo "Error: Not in a git repository"
        return 1
    }
    
    local remote_url=$(git remote get-url origin 2>/dev/null) || {
        echo "Error: No origin remote found"
        return 1
    }
    
    # Extract org/repo from GitHub URL
    local org_repo=$(parse_github_url "$remote_url")
    if [[ -z "$org_repo" ]]; then
        echo "Error: Not a GitHub repository"
        return 1
    fi
    
    # Find github.com directory starting from repo root
    local github_root=$(find_in_path "github.com" "$repo_root")
    if [[ -z "$github_root" ]]; then
        echo "Error: Could not find github.com directory structure"
        return 1
    fi
    
    # Create worktree
    local worktree_path="$github_root/$org_repo/$branch"
    echo "Creating worktree at $worktree_path"
    
    # Check if branch exists locally first
    if git show-ref --verify --quiet "refs/heads/$branch"; then
        # Local branch exists, use it directly
        git worktree add "$worktree_path" "$branch"
    else
        # Try to fetch from remote
        git fetch origin "$branch" 2>/dev/null && git worktree add "$worktree_path" "origin/$branch"
    fi

    cd "$worktree_path"
}


# Create new branch and worktree (equivalent to git checkout -b)
gwtb() {
    local branch=$1
    local base_branch=${2:-$(git rev-parse --abbrev-ref HEAD)}
    
    if [[ -z "$branch" ]]; then
        echo "Usage: gwtb <new-branch-name> [base-branch]"
        echo "  Creates a new branch and worktree"
        echo "  If base-branch is not specified, uses current branch"
        return 1
    fi
    
    # Get the repo root
    local repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || {
        echo "Error: Not in a git repository"
        return 1
    }
    
    # Check for uncommitted changes and stash them
    local stashed=0
    if ! git diff --quiet || ! git diff --cached --quiet; then
        echo "Stashing uncommitted changes..."
        git stash push -u -m "gwtb: auto-stash for $branch"
        stashed=1
    fi
    
    # Create the new branch
    echo "Creating branch '$branch' from '$base_branch'..."
    git fetch origin "$base_branch" 2>/dev/null || true
    git branch "$branch" "$base_branch" || {
        # Restore stash if branch creation failed
        if [[ $stashed -eq 1 ]]; then
            echo "Restoring stashed changes..."
            git stash pop
        fi
        return 1
    }
    
    # Use gwt to create the worktree for the new branch
    gwta "$branch" || {
        # Clean up on failure
        git branch -d "$branch" 2>/dev/null
        if [[ $stashed -eq 1 ]]; then
            echo "Restoring stashed changes..."
            git stash pop
        fi
        return 1
    }
    
    # If we stashed changes, apply them in the new worktree
    if [[ $stashed -eq 1 ]]; then
        # Get the worktree path from gwt's output
        local remote_url=$(git remote get-url origin)
        local org_repo=$(parse_github_url "$remote_url")
        local github_root=$(find_in_path "github.com" "$repo_root")
        local worktree_path="$github_root/$org_repo/$branch"
        
        echo "Applying stashed changes in new worktree..."
        cd "$worktree_path" && git stash pop
        cd - > /dev/null
    fi

    # End in the new worktree
    cd "$worktree_path"
}
