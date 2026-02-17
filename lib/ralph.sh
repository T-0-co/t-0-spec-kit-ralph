#!/usr/bin/env bash
# ralph.sh - Main orchestrator for Ralph Wiggum Loop
# Autonomous task execution with fresh Claude context per task
# Part of speckit-ralph

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION="0.1.0"

# Source library scripts
source "$SCRIPT_DIR/task-parser.sh" 2>/dev/null || true
source "$SCRIPT_DIR/progress-tracker.sh" 2>/dev/null || true
source "$SCRIPT_DIR/build-detector.sh" 2>/dev/null || true
source "$SCRIPT_DIR/context-builder.sh" 2>/dev/null || true

# Default configuration
MAX_RETRIES=3
PARALLEL_ENABLED=true   # Auto-detect [P] tasks by default
MAX_CONCURRENT=4
MAX_PARALLEL_TASKS=5    # Max tasks per batch
PARALLEL_TIMEOUT=14400  # 4 hours for batches (vs 2h for single)
DRY_RUN=false
RESUME=false
START_PHASE=1
BUDGET_LIMIT=0
SLACK_ENABLED=false
SLACK_CHANNEL=""
UI_ENABLED=false
VERBOSE=false
RALPH_CLAUDE_MODEL="${RALPH_CLAUDE_MODEL:-}"  # Empty = Claude CLI default/latest

# Worktree configuration
WORKTREE_ENABLED=false
WORKTREE_BASE=""  # Parent directory for worktrees
WORKTREE_PATH=""  # Explicit worktree path (overrides auto)
FEATURE_BRANCH="" # Branch to checkout in worktree

# Load config file (supports .specify/ralph/config.sh or spec-level ralph.config)
load_config() {
    local spec_dir="$1"
    local config_loaded=false

    # Check for global config in .specify/ralph/
    local global_config
    _parent_dir="$(dirname "$spec_dir")"
    if [[ "$(basename "$_parent_dir")" == "specs" ]]; then
        global_config="$(dirname "$_parent_dir")/ralph/config.sh"
        if [[ -f "$global_config" ]]; then
            source "$global_config"
            config_loaded=true
            [[ "$VERBOSE" == "true" ]] && log INFO "Loaded global config: $global_config"
        fi
    fi

    # Check for spec-level config (overrides global)
    if [[ -f "$spec_dir/ralph.config" ]]; then
        source "$spec_dir/ralph.config"
        config_loaded=true
        [[ "$VERBOSE" == "true" ]] && log INFO "Loaded spec config: $spec_dir/ralph.config"
    fi

    return 0
}

# Setup worktree for isolated development
setup_worktree() {
    local project_root="$1"
    local spec_name="$2"
    local branch="$3"

    if [[ "$WORKTREE_ENABLED" != "true" ]]; then
        return 0
    fi

    # Determine worktree path
    local worktree_path
    if [[ -n "$WORKTREE_PATH" ]]; then
        worktree_path="$WORKTREE_PATH"
    elif [[ -n "$WORKTREE_BASE" ]]; then
        worktree_path="$WORKTREE_BASE/$spec_name"
    else
        worktree_path="$(dirname "$project_root")/worktree-$spec_name"
    fi

    # Create worktree if it doesn't exist
    if [[ ! -d "$worktree_path" ]]; then
        log INFO "Creating worktree: $worktree_path"

        # Determine branch - use FEATURE_BRANCH, passed branch, or spec name
        local target_branch="${FEATURE_BRANCH:-${branch:-$spec_name}}"

        # Check if branch exists
        if git -C "$project_root" rev-parse --verify "$target_branch" &>/dev/null; then
            git -C "$project_root" worktree add "$worktree_path" "$target_branch"
        else
            # Create new branch from current HEAD
            log INFO "Creating new branch: $target_branch"
            git -C "$project_root" worktree add -b "$target_branch" "$worktree_path"
        fi

        log OK "Worktree created at: $worktree_path"
    else
        log INFO "Using existing worktree: $worktree_path"
    fi

    # Return the worktree path
    echo "$worktree_path"
}

# Get spec name from directory
get_spec_name() {
    local spec_dir="$1"
    basename "$spec_dir"
}

# Extract branch name from spec.md frontmatter
get_branch_from_spec() {
    local spec_dir="$1"

    if [[ -f "$spec_dir/spec.md" ]]; then
        # Look for "Feature Branch:" or "Branch:" in first 50 lines
        grep -m1 -E "^\*\*(Feature )?Branch\*\*:" "$spec_dir/spec.md" 2>/dev/null | \
            sed 's/.*: *`\?\([^`]*\)`\?.*/\1/' | tr -d '[:space:]'
    fi
}

# Colors for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_banner() {
    echo -e "${BLUE}"
    cat <<'EOF'
  ____       _       _
 |  _ \ __ _| |_ __ | |__
 | |_) / _` | | '_ \| '_ \
 |  _ < (_| | | |_) | | | |
 |_| \_\__,_|_| .__/|_| |_|
              |_|  Wiggum Loop
EOF
    echo -e "${NC}"
    echo "Version $VERSION - Autonomous Task Execution"
    echo ""
}

usage() {
    cat <<EOF
Usage: ralph [options] <command> <spec_dir>

Commands:
  start               Start executing tasks (default if no command)
  stop                Stop running Ralph processes
  status              Show current progress

Options:
  --dry-run           Preview tasks without executing
  --resume            Resume from last state
  --phase <n>         Start from specific phase
  --max-retries <n>   Max retry attempts per task (default: 3)
  --parallel          Enable parallel execution for [P] tasks
  --max-concurrent <n> Max parallel tasks (default: 3)
  --budget <usd>      Stop if cost exceeds budget
  --worktree          Enable worktree isolation
  --worktree-base <d> Parent directory for worktrees
  --branch <name>     Branch to use in worktree
  --slack             Enable Slack notifications
  --slack-channel <c> Slack channel for notifications
  --model <name>      Claude model override (default: CLI default/latest)
  --ui                Enable rich terminal UI
  --verbose           Verbose output
  --version           Show version
  --help              Show this help

Config Files:
  .specify/ralph/config.sh   Global config for all specs
  <spec_dir>/ralph.config    Per-spec config (overrides global)

Examples:
  ralph specs/001-feature/              # Run all tasks
  ralph start specs/001-feature/        # Explicit start command
  ralph --dry-run specs/001-feature/    # Preview only
  ralph --resume specs/001-feature/     # Resume after fix
  ralph --worktree specs/001-feature/   # Run in isolated worktree
  ralph --parallel --budget 20 specs/   # Parallel with budget
EOF
}

log() {
    local level="$1"
    local msg="$2"
    local timestamp
    timestamp=$(date +"%H:%M:%S")

    case "$level" in
        INFO)  echo -e "${BLUE}[$timestamp]${NC} $msg" ;;
        OK)    echo -e "${GREEN}[$timestamp] ✓${NC} $msg" ;;
        WARN)  echo -e "${YELLOW}[$timestamp] ⚠${NC} $msg" ;;
        ERROR) echo -e "${RED}[$timestamp] ✗${NC} $msg" ;;
        *)     echo "[$timestamp] $msg" ;;
    esac
}

# Write to session.log for dashboard (separate from tmux display)
log_session() {
    local log_file="${SESSION_LOG:-${SPEC_DIR:+$SPEC_DIR/.ralph/session.log}}"
    if [[ -n "$log_file" ]] && [[ -d "$(dirname "$log_file")" ]]; then
        local utc_ts
        utc_ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
        echo "[$utc_ts] $1" >> "$log_file" 2>/dev/null
    fi
}

build_claude_cmd() {
    local -a cmd
    cmd=("claude" "--print" "--dangerously-skip-permissions")
    if [[ -n "${RALPH_CLAUDE_MODEL:-}" ]]; then
        cmd+=("--model" "$RALPH_CLAUDE_MODEL")
    fi
    printf "%s\0" "${cmd[@]}"
}

# Parse command line arguments
COMMAND="start"  # Default command

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            start|stop|status)
                COMMAND="$1"
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --resume)
                RESUME=true
                shift
                ;;
            --phase)
                START_PHASE="$2"
                shift 2
                ;;
            --max-retries)
                MAX_RETRIES="$2"
                shift 2
                ;;
            --parallel)
                PARALLEL_ENABLED=true
                shift
                ;;
            --no-parallel)
                PARALLEL_ENABLED=false
                shift
                ;;
            --max-concurrent)
                MAX_CONCURRENT="$2"
                shift 2
                ;;
            --budget)
                BUDGET_LIMIT="$2"
                shift 2
                ;;
            --worktree)
                WORKTREE_ENABLED=true
                shift
                ;;
            --worktree-base)
                WORKTREE_BASE="$2"
                WORKTREE_ENABLED=true
                shift 2
                ;;
            --branch)
                FEATURE_BRANCH="$2"
                shift 2
                ;;
            --slack)
                SLACK_ENABLED=true
                shift
                ;;
            --slack-channel)
                SLACK_CHANNEL="$2"
                shift 2
                ;;
            --model)
                RALPH_CLAUDE_MODEL="$2"
                shift 2
                ;;
            --ui)
                UI_ENABLED=true
                shift
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --version)
                echo "ralph version $VERSION"
                exit 0
                ;;
            --help|-h)
                usage
                exit 0
                ;;
            -*)
                echo "Unknown option: $1" >&2
                usage >&2
                exit 1
                ;;
            *)
                SPEC_DIR="$1"
                shift
                ;;
        esac
    done
}

# Find tasks.md in spec directory
find_tasks_file() {
    local spec_dir="$1"

    if [[ -f "$spec_dir/tasks.md" ]]; then
        echo "$spec_dir/tasks.md"
    elif [[ -f "$spec_dir/TASKS.md" ]]; then
        echo "$spec_dir/TASKS.md"
    else
        echo ""
    fi
}

# Execute a single task with Claude
execute_task() {
    local spec_dir="$1"
    local task_json="$2"
    local attempt="$3"

    local task_id
    task_id=$(echo "$task_json" | jq -r '.id')
    local task_desc
    task_desc=$(echo "$task_json" | jq -r '.description')

    log INFO "Executing $task_id (attempt $attempt/$MAX_RETRIES)"
    log INFO "  → $task_desc"

    if [[ "$DRY_RUN" == "true" ]]; then
        log WARN "[DRY RUN] Would execute: $task_id"
        return 0
    fi

    # Build context for this task
    local context
    context=$("$SCRIPT_DIR/context-builder.sh" "$spec_dir" "$task_json")

    # Track progress
    "$SCRIPT_DIR/progress-tracker.sh" "$spec_dir" start "$task_id" "$attempt"

    # Create temp file for prompt
    local prompt_file
    prompt_file=$(mktemp)
    echo "$context" > "$prompt_file"

    # Execute Claude with fresh context
    # Using claude CLI in non-interactive mode
    local output_file
    output_file=$(mktemp)
    local exit_code=0

    # Find project root for execution
    # Structure: PROJECT_ROOT/.specify/specs/SPEC_NAME/
    local project_root="$spec_dir"
    local _pdir="$(dirname "$spec_dir")"
    if [[ "$(basename "$_pdir")" == "specs" ]]; then
        local _sdir="$(dirname "$_pdir")"
        if [[ "$(basename "$_sdir")" == ".specify" ]]; then
            project_root="$(dirname "$_sdir")"
        else
            project_root="$_sdir"
        fi
    fi

    # Run Claude Code CLI
    if command -v claude &> /dev/null; then
        log INFO "Invoking Claude Code..."
        log_session "Invoking Claude"
        cd "$project_root"

        # Execute with timeout (30 minutes per task)
        # Note: streaming with tee causes --print mode to crash, using redirect for now
        # Use stdin instead of -p argument to avoid shell argument length limits
        #
        # Run claude in background and monitor:
        # 1. Kill if output file unchanged for 60s (claude finished but process lingers)
        # 2. Kill if graceful stop file appears
        # 3. Kill if overall timeout (7200s) exceeded
        local -a claude_cmd
        IFS=$'\0' read -r -d '' -a claude_cmd < <(build_claude_cmd && printf '\0')
        if [[ -n "${RALPH_CLAUDE_MODEL:-}" ]]; then
            log INFO "Using model override: $RALPH_CLAUDE_MODEL"
        fi
        (
            cat "$prompt_file" | "${claude_cmd[@]}"
        ) > "$output_file" 2>&1 &
        local claude_pid=$!
        local start_secs=$SECONDS
        local last_size=-1
        local stale_count=0
        local STALE_LIMIT=${STALE_LIMIT:-36}  # default 36 x 10s = 360s of no output → done
        local task_timeout=${TASK_TIMEOUT:-7200}

        while kill -0 "$claude_pid" 2>/dev/null; do
            sleep 10

            # Check overall timeout
            if (( SECONDS - start_secs > task_timeout )); then
                log WARN "Task timeout (${task_timeout}s) reached, killing claude"
                log_session "Timeout — killing"
                kill -- -"$claude_pid" 2>/dev/null || kill "$claude_pid" 2>/dev/null
                wait "$claude_pid" 2>/dev/null
                exit_code=124
                break
            fi

            # Check graceful stop file
            if [[ -f "$spec_dir/.ralph/.stop" ]]; then
                log INFO "Stop file detected during task execution, waiting for claude to finish..."
                # Don't kill immediately — let current output settle, but set a shorter stale limit
                STALE_LIMIT=3  # 30s grace after stop file
            fi

            # Check if output file is still growing OR claude session file is active
            local cur_size
            cur_size=$(stat -f%z "$output_file" 2>/dev/null || echo 0)
            if [[ "$cur_size" -eq "$last_size" ]]; then
                ((stale_count++)) || true
                if (( stale_count >= STALE_LIMIT )); then
                    # Before killing, check if any project JSONL was recently modified
                    # (claude --print doesn't write stdout while working, but does write JSONL)
                    local claude_proj_dir="$HOME/.claude/projects/-$(echo "$project_root" | tr '/' '-' | sed 's/^-//')"
                    local newest_jsonl_mtime=0
                    local jf
                    for jf in "$claude_proj_dir"/*.jsonl; do
                        [[ -f "$jf" ]] || continue
                        local jm
                        jm=$(stat -f%m "$jf" 2>/dev/null || echo 0)
                        [[ $jm -gt $newest_jsonl_mtime ]] && newest_jsonl_mtime=$jm
                    done
                    local now_secs
                    now_secs=$(date +%s)
                    local jsonl_age=$(( now_secs - newest_jsonl_mtime ))
                    if [[ $jsonl_age -lt 300 ]] && [[ $newest_jsonl_mtime -gt 0 ]]; then
                        # JSONL was written in last 5 min — Claude is still working
                        # Reset stale counter but only halfway (so truly stuck processes eventually die)
                        log INFO "Output stale ${stale_count}x but JSONL active (${jsonl_age}s ago) — extending"
                        log_session "Stale extended — JSONL active ${jsonl_age}s ago"
                        stale_count=$((STALE_LIMIT / 2))
                    else
                        log INFO "Claude output idle for $((stale_count * 10))s, assuming complete"
                        kill -- -"$claude_pid" 2>/dev/null || kill "$claude_pid" 2>/dev/null
                        wait "$claude_pid" 2>/dev/null
                        # Treat as success if we got output, files changed, or JSONL indicates success
                        if [[ "$cur_size" -gt 0 ]]; then
                            exit_code=0
                        elif ! git -C "$project_root" diff --quiet HEAD 2>/dev/null; then
                            log WARN "No stdout but files changed — accepting pending build check"
                            exit_code=0
                        else
                            # Last resort: check if Claude's JSONL contains a success message
                            local newest_jsonl
                            newest_jsonl=$(ls -t "$claude_proj_dir"/*.jsonl 2>/dev/null | head -1)
                            if [[ -n "$newest_jsonl" ]]; then
                                local success_found
                                success_found=$(tail -20 "$newest_jsonl" 2>/dev/null | grep -ci "success\|all.*pass\|tests.*green\|completed" || true)
                                if [[ "$success_found" -gt 0 ]]; then
                                    log WARN "No stdout/changes but JSONL indicates success — accepting"
                                    log_session "Accepted via JSONL success signal"
                                    exit_code=0
                                else
                                    exit_code=1
                                fi
                            else
                                exit_code=1
                            fi
                        fi
                        break
                    fi
                fi
            else
                stale_count=0
                last_size=$cur_size
            fi
        done

        # If loop exited because process died naturally
        if ! kill -0 "$claude_pid" 2>/dev/null; then
            local wait_code=0
            wait "$claude_pid" 2>/dev/null
            wait_code=$?
            # Only use wait's exit code if stale kill didn't already set it
            if [[ $stale_count -lt $STALE_LIMIT ]] && [[ $wait_code -ne 0 ]]; then
                exit_code=$wait_code
            fi
        fi
    else
        log ERROR "Claude CLI not found. Install with: npm install -g @anthropic-ai/claude-code"
        exit_code=1
    fi

    # Parse output for token usage (if available)
    local input_tokens=0
    local output_tokens=0
    # TODO: Parse token usage from Claude output when available

    # Clean up
    rm -f "$prompt_file"

    if [[ $exit_code -eq 0 ]]; then
        log OK "Task $task_id completed"
        "$SCRIPT_DIR/progress-tracker.sh" "$spec_dir" complete "$task_id" "$input_tokens" "$output_tokens"

        # Update tasks.md to mark task complete
        mark_task_complete "$spec_dir" "$task_id"

        rm -f "$output_file"
        return 0
    else
        log ERROR "Task $task_id failed (exit code: $exit_code)"
        log_session "Failed exit=$exit_code"
        local error_msg
        error_msg=$(tail -20 "$output_file" 2>/dev/null || echo "Unknown error")

        if [[ $attempt -lt $MAX_RETRIES ]]; then
            log WARN "Retrying $task_id..."
            log_session "Retrying $task_id"
            rm -f "$output_file"
            return 1  # Signal retry
        else
            "$SCRIPT_DIR/progress-tracker.sh" "$spec_dir" fail "$task_id" "$error_msg"
            rm -f "$output_file"
            return 2  # Signal permanent failure
        fi
    fi
}

# Mark task as complete in tasks.md
mark_task_complete() {
    local spec_dir="$1"
    local task_id="$2"
    local tasks_file
    tasks_file=$(find_tasks_file "$spec_dir")

    if [[ -n "$tasks_file" ]]; then
        # Replace [ ] with [x] for this task (supports indented subtasks like T067a)
        sed -i.bak "s/^\([[:space:]]*- \)\[ \]\( $task_id \)/\1[x]\2/" "$tasks_file"
        rm -f "${tasks_file}.bak"
    fi
}

# Execute a batch of parallel tasks using Claude subagents
execute_parallel_batch() {
    local spec_dir="$1"
    local batch_json="$2"
    local project_root="$3"

    local batch_count
    batch_count=$(echo "$batch_json" | jq 'length')
    local task_ids
    task_ids=$(echo "$batch_json" | jq -r '[.[].id] | join(", ")')
    local first_task_id
    first_task_id=$(echo "$batch_json" | jq -r '.[0].id')
    local last_task_id
    last_task_id=$(echo "$batch_json" | jq -r '.[-1].id')

    log INFO "Executing parallel batch: $batch_count tasks ($task_ids)"

    if [[ "$DRY_RUN" == "true" ]]; then
        log WARN "[DRY RUN] Would execute batch: $task_ids"
        return 0
    fi

    # Track batch start in progress
    local task_ids_array
    task_ids_array=$(echo "$batch_json" | jq '[.[].id]')
    "$SCRIPT_DIR/progress-tracker.sh" "$spec_dir" start-batch "$task_ids_array"

    # Build batch context
    local context
    context=$("$SCRIPT_DIR/context-builder.sh" "$spec_dir" --batch "$batch_json")

    # Create temp file for prompt
    local prompt_file
    prompt_file=$(mktemp)
    echo "$context" > "$prompt_file"

    # Execute Claude with batch context
    local output_file
    output_file=$(mktemp)
    local exit_code=0

    if command -v claude &> /dev/null; then
        log INFO "Invoking Claude Code for parallel batch..."
        cd "$project_root"

        # Execute with longer timeout for batches
        # Use stdin instead of -p argument to avoid shell argument length limits
        # Same background monitoring as single task (see execute_task)
        local -a claude_cmd
        IFS=$'\0' read -r -d '' -a claude_cmd < <(build_claude_cmd && printf '\0')
        (
            cat "$prompt_file" | "${claude_cmd[@]}"
        ) > "$output_file" 2>&1 &
        local claude_pid=$!
        local start_secs=$SECONDS
        local last_size=-1
        local stale_count=0
        local STALE_LIMIT=12  # 12 x 10s = 120s for batches (longer grace period)

        while kill -0 "$claude_pid" 2>/dev/null; do
            sleep 10

            # Check overall timeout
            if (( SECONDS - start_secs > PARALLEL_TIMEOUT )); then
                log WARN "Batch timeout (${PARALLEL_TIMEOUT}s) reached, killing claude"
                kill -- -"$claude_pid" 2>/dev/null || kill "$claude_pid" 2>/dev/null
                wait "$claude_pid" 2>/dev/null
                exit_code=124
                break
            fi

            # Check graceful stop file
            if [[ -f "$spec_dir/.ralph/.stop" ]]; then
                log INFO "Stop file detected during batch execution"
                STALE_LIMIT=6  # 60s grace after stop file for batches
            fi

            # Check if output file is still growing
            local cur_size
            cur_size=$(stat -f%z "$output_file" 2>/dev/null || echo 0)
            if [[ "$cur_size" -eq "$last_size" ]]; then
                ((stale_count++)) || true
                if (( stale_count >= STALE_LIMIT )); then
                    log INFO "Claude output idle for $((stale_count * 10))s, assuming batch complete"
                    kill -- -"$claude_pid" 2>/dev/null || kill "$claude_pid" 2>/dev/null
                    wait "$claude_pid" 2>/dev/null
                    if [[ "$cur_size" -gt 0 ]]; then
                        exit_code=0
                    else
                        exit_code=1
                    fi
                    break
                fi
            else
                stale_count=0
                last_size=$cur_size
            fi
        done

        # If loop exited because process died naturally (not from our stale/timeout kill)
        if ! kill -0 "$claude_pid" 2>/dev/null; then
            local wait_code=0
            wait "$claude_pid" 2>/dev/null
            wait_code=$?
            if [[ $stale_count -lt $STALE_LIMIT ]] && [[ $wait_code -ne 0 ]]; then
                exit_code=$wait_code
            fi
        fi
    else
        log ERROR "Claude CLI not found. Install with: npm install -g @anthropic-ai/claude-code"
        exit_code=1
    fi

    # Clean up prompt file
    rm -f "$prompt_file"

    if [[ $exit_code -eq 0 ]]; then
        log OK "Batch completed: $task_ids"

        # Complete batch in progress tracker
        "$SCRIPT_DIR/progress-tracker.sh" "$spec_dir" complete-batch 0 0

        # Mark all tasks complete in tasks.md
        echo "$batch_json" | jq -r '.[].id' | while read -r task_id; do
            mark_task_complete "$spec_dir" "$task_id"
        done

        rm -f "$output_file"
        return 0
    else
        log ERROR "Batch failed (exit code: $exit_code)"
        local error_msg
        error_msg=$(tail -30 "$output_file" 2>/dev/null || echo "Unknown error")
        log ERROR "Error: $error_msg"

        # Mark as blocked
        "$SCRIPT_DIR/progress-tracker.sh" "$spec_dir" block "Batch $first_task_id-$last_task_id failed"
        rm -f "$output_file"
        return 1
    fi
}

# Run build/test verification
verify_build() {
    local project_root="$1"

    log INFO "Running build verification..."
    log_session "Verifying build"

    # Only auto-detect if not already set in config
    if [[ -z "${BUILD_CMD:-}" ]] || [[ -z "${TEST_CMD:-}" ]]; then
        local build_env
        build_env=$("$SCRIPT_DIR/build-detector.sh" "$project_root" --env)
        # Only set variables that aren't already defined
        while IFS='=' read -r key value; do
            if [[ -z "${!key:-}" ]]; then
                eval "$key=$value"
            fi
        done <<< "$build_env"
    fi

    # Run build
    if [[ -n "${BUILD_CMD:-}" ]] && [[ "$BUILD_CMD" != *"No build"* ]]; then
        log INFO "Building: $BUILD_CMD"
        if ! (cd "$project_root" && eval "$BUILD_CMD" > /dev/null 2>&1); then
            log ERROR "Build failed"
            log_session "Build failed"
            return 1
        fi
        log OK "Build passed"
        log_session "Build passed"
    fi

    # Run tests
    if [[ -n "${TEST_CMD:-}" ]] && [[ "$TEST_CMD" != *"No test"* ]]; then
        log INFO "Testing: $TEST_CMD"
        if ! (cd "$project_root" && eval "$TEST_CMD" > /dev/null 2>&1); then
            log ERROR "Tests failed"
            log_session "Tests failed"
            return 1
        fi
        log OK "Tests passed"
        log_session "Tests passed"
    fi

    return 0
}

# Check budget
check_budget() {
    local spec_dir="$1"

    if [[ "$BUDGET_LIMIT" == "0" ]]; then
        return 0  # No budget limit
    fi

    local current_cost
    current_cost=$(jq -r '.total_cost_usd' "$spec_dir/.ralph/progress.json" 2>/dev/null || echo "0")

    if (( $(echo "$current_cost >= $BUDGET_LIMIT" | bc -l) )); then
        log ERROR "Budget exceeded: \$$current_cost >= \$$BUDGET_LIMIT"
        return 1
    fi

    # Warn at 80%
    local threshold
    threshold=$(echo "$BUDGET_LIMIT * 0.8" | bc -l)
    if (( $(echo "$current_cost >= $threshold" | bc -l) )); then
        log WARN "Budget warning: \$$current_cost (80% of \$$BUDGET_LIMIT)"
    fi

    return 0
}

# Send Slack notification
notify_slack() {
    local message="$1"

    if [[ "$SLACK_ENABLED" != "true" ]]; then
        return 0
    fi

    if [[ -z "$SLACK_CHANNEL" ]]; then
        SLACK_CHANNEL="#dev-updates"
    fi

    # Use slack-notifier.sh if available
    if [[ -f "$SCRIPT_DIR/slack-notifier.sh" ]]; then
        "$SCRIPT_DIR/slack-notifier.sh" "$SLACK_CHANNEL" "$message"
    else
        log WARN "Slack notifier not available"
    fi
}

# Stop command - kill Ralph processes
cmd_stop() {
    log INFO "Stopping Ralph processes..."
    pkill -f "ralph.sh" 2>/dev/null || true
    pkill -f "timeout.*claude.*--print" 2>/dev/null || true
    log OK "Ralph processes stopped"
}

# Status command - show progress
cmd_status() {
    local spec_dir="$1"

    if [[ -f "$spec_dir/.ralph/progress.json" ]]; then
        echo "=== Ralph Progress ==="
        jq '.' "$spec_dir/.ralph/progress.json"
    else
        log WARN "No progress file found in $spec_dir"
    fi

    # Show git status
    local project_root="$spec_dir"
    local _pdir="$(dirname "$spec_dir")"
    if [[ "$(basename "$_pdir")" == "specs" ]]; then
        local _sdir="$(dirname "$_pdir")"
        if [[ "$(basename "$_sdir")" == ".specify" ]]; then
            project_root="$(dirname "$_sdir")"
        else
            project_root="$_sdir"
        fi
    fi

    echo ""
    echo "=== Recent Ralph Commits ==="
    git -C "$project_root" log --oneline -5 --grep="Ralph:" 2>/dev/null || echo "No Ralph commits found"
}

# Main loop
main() {
    parse_args "$@"

    # Handle commands that don't need spec_dir
    if [[ "$COMMAND" == "stop" ]]; then
        cmd_stop
        exit 0
    fi

    if [[ -z "${SPEC_DIR:-}" ]]; then
        echo "Error: spec_dir required" >&2
        usage >&2
        exit 1
    fi

    # Resolve to absolute path
    SPEC_DIR="$(cd "$SPEC_DIR" && pwd)"

    # Handle status command
    if [[ "$COMMAND" == "status" ]]; then
        cmd_status "$SPEC_DIR"
        exit 0
    fi

    # Load configuration
    load_config "$SPEC_DIR"

    print_banner

    # Find tasks.md
    local tasks_file
    tasks_file=$(find_tasks_file "$SPEC_DIR")

    if [[ -z "$tasks_file" ]]; then
        log ERROR "No tasks.md found in $SPEC_DIR"
        exit 1
    fi

    log INFO "Found tasks: $tasks_file"

    # Find project root
    # Structure: PROJECT_ROOT/.specify/specs/SPEC_NAME/
    # Need to go up 3 levels from spec dir to reach project root
    local project_root="$SPEC_DIR"
    local _parent_dir="$(dirname "$SPEC_DIR")"
    if [[ "$(basename "$_parent_dir")" == "specs" ]]; then
        local _specify_dir="$(dirname "$_parent_dir")"
        if [[ "$(basename "$_specify_dir")" == ".specify" ]]; then
            # Standard structure: go up 3 levels
            project_root="$(dirname "$_specify_dir")"
        else
            # Legacy structure without .specify: go up 2 levels
            project_root="$_specify_dir"
        fi
    fi

    # Setup worktree if enabled
    local spec_name
    spec_name=$(get_spec_name "$SPEC_DIR")
    local branch_from_spec
    branch_from_spec=$(get_branch_from_spec "$SPEC_DIR")

    if [[ "$WORKTREE_ENABLED" == "true" ]]; then
        local worktree_result
        worktree_result=$(setup_worktree "$project_root" "$spec_name" "$branch_from_spec")
        if [[ -n "$worktree_result" ]]; then
            project_root="$worktree_result"
            log INFO "Working in worktree: $project_root"
        fi
    fi

    log INFO "Project root: $project_root"

    # Initialize progress tracking
    "$SCRIPT_DIR/progress-tracker.sh" "$SPEC_DIR" init

    # Always resume if previously blocked (clears blocked_reason and sets status to running)
    if [[ -f "$SPEC_DIR/.ralph/progress.json" ]]; then
        local prev_status
        prev_status=$(jq -r '.status // "unknown"' "$SPEC_DIR/.ralph/progress.json" 2>/dev/null)
        if [[ "$prev_status" == "blocked" ]] || [[ "$RESUME" == "true" ]]; then
            "$SCRIPT_DIR/progress-tracker.sh" "$SPEC_DIR" resume
            log INFO "Resuming from previous state"
        fi
    fi

    # Notify start
    local total_tasks
    total_tasks=$("$SCRIPT_DIR/task-parser.sh" "$tasks_file" --json | jq '.total_tasks')
    notify_slack "🚀 Ralph Loop Started: $spec_name ($total_tasks tasks)"

    # Cleanup function for graceful shutdown
    cleanup_spawned_processes() {
        log WARN "Cleaning up spawned processes..."
        # Kill any Claude processes spawned by this Ralph instance
        pkill -P $$ 2>/dev/null || true
        pkill -f "timeout.*claude.*--print" 2>/dev/null || true
        pkill -f "playwright" 2>/dev/null || true
        pkill -f "npx.*playwright" 2>/dev/null || true
        log INFO "Cleanup complete"
    }

    # Set trap for cleanup on exit/interrupt/termination
    trap cleanup_spawned_processes EXIT INT TERM

    # Main execution loop
    local completed=0
    local failed=0

    while true; do
        # Check for graceful stop file
        if [[ -f "$SPEC_DIR/.ralph/.stop" ]]; then
            log INFO "Stop file detected, finishing gracefully..."
            log_session "Stop requested"
            rm -f "$SPEC_DIR/.ralph/.stop"
            "$SCRIPT_DIR/progress-tracker.sh" "$SPEC_DIR" block "Graceful stop requested"
            notify_slack "🛑 Ralph Loop stopped gracefully"
            exit 0
        fi

        # Check budget
        if ! check_budget "$SPEC_DIR"; then
            "$SCRIPT_DIR/progress-tracker.sh" "$SPEC_DIR" block "Budget exceeded"
            notify_slack "💰 Ralph Loop stopped: Budget exceeded"
            exit 1
        fi

        # ─────────────────────────────────────────────────────────────────────
        # PARALLEL BATCH DETECTION (auto-detects [P] marked tasks)
        # ─────────────────────────────────────────────────────────────────────
        if [[ "$PARALLEL_ENABLED" == "true" ]]; then
            local parallel_batch
            parallel_batch=$("$SCRIPT_DIR/task-parser.sh" "$tasks_file" --parallel)

            local batch_size
            batch_size=$(echo "$parallel_batch" | jq 'length')

            # Execute as batch if we have multiple parallel tasks
            if [[ "$batch_size" -gt 1 ]]; then
                # Limit batch size to MAX_PARALLEL_TASKS
                if [[ "$batch_size" -gt "$MAX_PARALLEL_TASKS" ]]; then
                    parallel_batch=$(echo "$parallel_batch" | jq ".[:$MAX_PARALLEL_TASKS]")
                    batch_size=$MAX_PARALLEL_TASKS
                    log INFO "Limiting batch to $MAX_PARALLEL_TASKS tasks"
                fi

                local batch_first_id batch_last_id batch_desc
                batch_first_id=$(echo "$parallel_batch" | jq -r '.[0].id')
                batch_last_id=$(echo "$parallel_batch" | jq -r '.[-1].id')
                batch_desc=$(echo "$parallel_batch" | jq -r '.[0].description' | head -c 40)

                log INFO "═══ Parallel batch detected: $batch_size tasks ($batch_first_id-$batch_last_id) ═══"

                if execute_parallel_batch "$SPEC_DIR" "$parallel_batch" "$project_root"; then
                    ((completed += batch_size)) || true

                    # Verify build after batch
                    if ! verify_build "$project_root"; then
                        log ERROR "Build verification failed after batch $batch_first_id-$batch_last_id"
                        "$SCRIPT_DIR/progress-tracker.sh" "$SPEC_DIR" block "Build failed after batch"
                        notify_slack "🚫 Ralph Loop BLOCKED: Build failed after batch $batch_first_id-$batch_last_id"
                        exit 1
                    fi

                    # Auto-commit batch
                    if [[ -d "$project_root/.git" ]] && [[ "${RALPH_AUTO_COMMIT:-true}" == "true" ]]; then
                        (
                            cd "$project_root"
                            git add -A
                            if git commit -m "Ralph: $batch_first_id-$batch_last_id of T$total_tasks - $batch_desc (batch of $batch_size)" --no-verify --no-gpg-sign 2>/dev/null; then
                                local short_sha
                                short_sha=$(git rev-parse --short HEAD 2>/dev/null)
                                log_session "Commit $short_sha $batch_first_id-$batch_last_id"
                                if [[ "${RALPH_AUTO_PUSH:-true}" == "true" ]]; then
                                    if git rev-parse --abbrev-ref --symbolic-full-name @{u} &>/dev/null; then
                                        git push 2>/dev/null || log WARN "Push failed for batch"
                                    else
                                        git push -u origin HEAD 2>/dev/null || log WARN "Initial push failed for batch"
                                    fi
                                fi
                            fi
                        ) || true
                    fi

                    # Continue to next iteration (skip sequential execution)
                    continue
                else
                    # Batch failed - already blocked by execute_parallel_batch
                    notify_slack "🚫 Ralph Loop BLOCKED: Batch $batch_first_id-$batch_last_id failed"
                    exit 1
                fi
            fi
            # If batch_size <= 1, fall through to sequential execution
        fi

        # ─────────────────────────────────────────────────────────────────────
        # SEQUENTIAL EXECUTION (single task at a time)
        # ─────────────────────────────────────────────────────────────────────

        # Get next task
        local next_task
        next_task=$("$SCRIPT_DIR/task-parser.sh" "$tasks_file" --next)

        if [[ -z "$next_task" ]] || [[ "$next_task" == "null" ]]; then
            log OK "All tasks completed!"
            break
        fi

        local task_id
        task_id=$(echo "$next_task" | jq -r '.id')
        local task_phase
        task_phase=$(echo "$next_task" | jq -r '.phase')
        local task_desc
        task_desc=$(echo "$next_task" | jq -r '.description' )

        # Skip if below start phase
        if [[ "$task_phase" -lt "$START_PHASE" ]]; then
            mark_task_complete "$SPEC_DIR" "$task_id"
            continue
        fi

        # Execute task with retry logic
        local attempt=1
        local task_success=false

        while [[ $attempt -le $MAX_RETRIES ]]; do
            if execute_task "$SPEC_DIR" "$next_task" "$attempt"; then
                task_success=true
                break
            fi

            local exit_status=$?
            if [[ $exit_status -eq 2 ]]; then
                # Permanent failure
                break
            fi

            ((attempt++)) || true
            sleep 2
        done

        if [[ "$task_success" == "true" ]]; then
            ((completed++)) || true
            # Per-task Slack removed - commits provide visibility

            # Verify build after each task
            if ! verify_build "$project_root"; then
                log ERROR "Build verification failed after $task_id"
                log_session "Build failed — BLOCKED"
                "$SCRIPT_DIR/progress-tracker.sh" "$SPEC_DIR" block "Build failed after $task_id"
                notify_slack "🚫 Ralph Loop BLOCKED: Build failed after $task_id"
                exit 1
            fi

            # Auto-commit and push if configured
            if [[ -d "$project_root/.git" ]] && [[ "${RALPH_AUTO_COMMIT:-true}" == "true" ]]; then
                (
                    cd "$project_root"
                    git add -A
                    if git commit -m "Ralph: $task_id of T$total_tasks - $task_desc" --no-verify --no-gpg-sign 2>/dev/null; then
                        local short_sha
                        short_sha=$(git rev-parse --short HEAD 2>/dev/null)
                        log_session "Commit $short_sha $task_id"
                        if [[ "${RALPH_AUTO_PUSH:-true}" == "true" ]]; then
                            # Check if branch has upstream, if not use -u origin HEAD
                            if git rev-parse --abbrev-ref --symbolic-full-name @{u} &>/dev/null; then
                                git push 2>/dev/null || log WARN "Push failed for $task_id"
                            else
                                git push -u origin HEAD 2>/dev/null || log WARN "Initial push failed for $task_id"
                            fi
                        fi
                    fi
                ) || true
            fi
        else
            ((failed++)) || true
            log ERROR "Task $task_id failed after $MAX_RETRIES attempts"
            log_session "Failed $MAX_RETRIES attempts — BLOCKED"
            "$SCRIPT_DIR/progress-tracker.sh" "$SPEC_DIR" block "Task $task_id failed"
            notify_slack "🚫 Ralph Loop BLOCKED: Task $task_id failed after $MAX_RETRIES attempts"
            exit 1
        fi
    done

    # Complete
    "$SCRIPT_DIR/progress-tracker.sh" "$SPEC_DIR" done

    # Summary
    local summary
    summary=$("$SCRIPT_DIR/progress-tracker.sh" "$SPEC_DIR" summary)
    log OK "Ralph Loop Complete!"
    echo "$summary"

    notify_slack "🎉 Ralph Loop Complete: $spec_name - $completed tasks, $summary"
}

# Run main if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
