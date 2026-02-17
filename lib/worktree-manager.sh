#!/usr/bin/env bash
# worktree-manager.sh - Git worktrees for parallel task execution
# Part of speckit-ralph

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Manage git worktrees for parallel execution
# Usage: worktree-manager.sh <project_root> <command> [args...]

PROJECT_ROOT="${1:-$(pwd)}"
COMMAND="${2:-list}"
shift 2 || true

WORKTREE_BASE="${PROJECT_ROOT}/../ralph-worktrees"

# Create worktree for a task
create_worktree() {
    local task_id="$1"
    local branch_name="ralph/$task_id"
    local worktree_path="$WORKTREE_BASE/$task_id"

    # Ensure we're in a git repo
    if ! git -C "$PROJECT_ROOT" rev-parse --git-dir > /dev/null 2>&1; then
        echo "Error: Not a git repository" >&2
        return 1
    fi

    # Create worktrees base directory
    mkdir -p "$WORKTREE_BASE"

    # Create worktree with new branch from current HEAD
    if git -C "$PROJECT_ROOT" worktree add "$worktree_path" -b "$branch_name" 2>/dev/null; then
        echo "$worktree_path"
    else
        # Branch might exist, try without -b
        if git -C "$PROJECT_ROOT" worktree add "$worktree_path" "$branch_name" 2>/dev/null; then
            echo "$worktree_path"
        else
            echo "Error: Failed to create worktree for $task_id" >&2
            return 1
        fi
    fi
}

# Remove worktree and optionally merge
remove_worktree() {
    local task_id="$1"
    local merge="${2:-false}"
    local branch_name="ralph/$task_id"
    local worktree_path="$WORKTREE_BASE/$task_id"

    if [[ ! -d "$worktree_path" ]]; then
        echo "Worktree not found: $worktree_path" >&2
        return 1
    fi

    # Get current branch in main repo
    local main_branch
    main_branch=$(git -C "$PROJECT_ROOT" rev-parse --abbrev-ref HEAD)

    # Merge if requested
    if [[ "$merge" == "true" ]]; then
        echo "Merging $branch_name into $main_branch..."
        if ! git -C "$PROJECT_ROOT" merge --no-ff "$branch_name" -m "Ralph: Merge $task_id"; then
            echo "Error: Merge failed for $task_id" >&2
            return 1
        fi
    fi

    # Remove worktree
    git -C "$PROJECT_ROOT" worktree remove "$worktree_path" --force 2>/dev/null || true

    # Delete branch
    git -C "$PROJECT_ROOT" branch -D "$branch_name" 2>/dev/null || true

    echo "Removed worktree for $task_id"
}

# List active worktrees
list_worktrees() {
    git -C "$PROJECT_ROOT" worktree list | grep "ralph-worktrees" || echo "No Ralph worktrees active"
}

# Cleanup all Ralph worktrees
cleanup_all() {
    echo "Cleaning up all Ralph worktrees..."

    # List and remove each
    git -C "$PROJECT_ROOT" worktree list --porcelain | grep "^worktree" | cut -d' ' -f2 | while read -r path; do
        if [[ "$path" == *"ralph-worktrees"* ]]; then
            git -C "$PROJECT_ROOT" worktree remove "$path" --force 2>/dev/null || true
        fi
    done

    # Remove ralph branches
    git -C "$PROJECT_ROOT" branch -l "ralph/*" 2>/dev/null | while read -r branch; do
        git -C "$PROJECT_ROOT" branch -D "$branch" 2>/dev/null || true
    done

    # Remove worktrees directory
    rm -rf "$WORKTREE_BASE"

    echo "Cleanup complete"
}

# Run task in worktree
run_in_worktree() {
    local task_id="$1"
    local worktree_path="$WORKTREE_BASE/$task_id"

    if [[ ! -d "$worktree_path" ]]; then
        echo "Error: Worktree not found for $task_id" >&2
        return 1
    fi

    echo "$worktree_path"
}

# Get worktree status
get_status() {
    local task_id="$1"
    local worktree_path="$WORKTREE_BASE/$task_id"

    if [[ ! -d "$worktree_path" ]]; then
        echo "not_found"
        return
    fi

    # Check if there are uncommitted changes
    if git -C "$worktree_path" diff --quiet && git -C "$worktree_path" diff --cached --quiet; then
        echo "clean"
    else
        echo "dirty"
    fi
}

# Main dispatch
case "$COMMAND" in
    create)
        create_worktree "${1:-}"
        ;;
    remove)
        remove_worktree "${1:-}" "${2:-false}"
        ;;
    merge)
        remove_worktree "${1:-}" "true"
        ;;
    list)
        list_worktrees
        ;;
    cleanup)
        cleanup_all
        ;;
    path)
        run_in_worktree "${1:-}"
        ;;
    status)
        get_status "${1:-}"
        ;;
    *)
        echo "Unknown command: $COMMAND" >&2
        echo "Commands: create, remove, merge, list, cleanup, path, status" >&2
        exit 1
        ;;
esac
