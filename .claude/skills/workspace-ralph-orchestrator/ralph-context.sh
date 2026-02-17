#!/usr/bin/env bash
# ralph-context.sh - Enhanced Ralph TUI Dashboard
# Part of workspace-ralph-orchestrator skill
#
# Usage:
#   ./ralph-context.sh <spec_dir> [project_dir]              # Single render (default size)
#   ./ralph-context.sh <spec_dir> --loop                     # Continuous refresh
#   ./ralph-context.sh <spec_dir> --compact                  # Compact layout (80 cols min)
#   ./ralph-context.sh <spec_dir> --large                    # Large layout (120 cols min)
#   ./ralph-context.sh <spec_dir> --simple                   # Force simple single-column layout
#   ./ralph-context.sh <spec_dir> --width=60                 # Force specific width
#   ./ralph-context.sh <spec_dir> --simple --loop            # Simple layout with refresh

set -uo pipefail
# Note: not using -e because some checks return non-zero intentionally
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Parse arguments
LOOP_MODE=false
SIMPLE_MODE=false
FORCE_WIDTH=""
SIZE_MODE="default"  # default=100, compact=80, large=120
SPEC_DIR=""
PROJECT_DIR=""

for arg in "$@"; do
    case "$arg" in
        --loop) LOOP_MODE=true ;;
        --simple) SIMPLE_MODE=true ;;
        --compact) SIZE_MODE="compact" ;;
        --large) SIZE_MODE="large" ;;
        --width=*) FORCE_WIDTH="${arg#--width=}" ;;
        *)
            if [[ -z "$SPEC_DIR" ]]; then
                SPEC_DIR="$arg"
            elif [[ -z "$PROJECT_DIR" ]]; then
                PROJECT_DIR="$arg"
            fi
            ;;
    esac
done

# Auto-detect active spec from running Ralph tmux session
if [[ -z "$SPEC_DIR" ]]; then
    # Look for running Ralph sessions like "ralph-013"
    ACTIVE_RALPH=$(tmux list-sessions -F '#{session_name}' 2>/dev/null | grep '^ralph-' | head -1)
    if [[ -n "$ACTIVE_RALPH" ]]; then
        # Extract spec number (e.g., "ralph-013" -> "013")
        SPEC_NUM="${ACTIVE_RALPH#ralph-}"
        # Find matching spec directory
        FOUND_SPEC=$(ls -d .specify/specs/${SPEC_NUM}-* specs/${SPEC_NUM}-* 2>/dev/null | head -1)
        if [[ -n "$FOUND_SPEC" ]]; then
            SPEC_DIR="$FOUND_SPEC"
        fi
    fi
fi

# Fallback to first available spec if nothing explicit/active was found
if [[ -z "$SPEC_DIR" ]]; then
    SPEC_DIR=$(ls -d .specify/specs/* specs/* 2>/dev/null | head -1 || true)
fi

if [[ -z "$SPEC_DIR" ]]; then
    echo "Error: no spec directory found. Pass one explicitly: ralph-context.sh <spec_dir>" >&2
    exit 1
fi

PROJECT_DIR="${PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
CLAUDE_PROJECT_PATH="$HOME/.claude/projects/-$(echo "$PROJECT_DIR" | tr '/' '-' | sed 's/^-//')"

# Load spec-level config for dashboard settings (DOCKER_FILTER, PORT_CHECK, etc.)
if [[ -f "$SPEC_DIR/ralph.config" ]]; then
    source "$SPEC_DIR/ralph.config"
fi

# Terminal dimensions
if [[ -n "$FORCE_WIDTH" ]]; then
    TERM_COLS=$FORCE_WIDTH
else
    TERM_COLS=$(tput cols 2>/dev/null || echo 80)
fi
TERM_ROWS=$(tput rows 2>/dev/null || echo 24)
MIN_WIDE_COLS=80

# Box-drawing characters (light style - less visual noise)
BOX_TL="┌" BOX_TR="┐" BOX_BL="└" BOX_BR="┘"
BOX_H="─" BOX_V="│" BOX_HV="┼"
BOX_VR="├" BOX_VL="┤" BOX_HD="┬" BOX_HU="┴"

# Colors (using $'...' for proper escape interpretation)
RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
BLUE=$'\033[0;34m'
CYAN=$'\033[0;36m'
BOLD=$'\033[1m'
DIM=$'\033[2m'
NC=$'\033[0m' # No Color

# ─────────────────────────────────────────────────────────────────────────────
# HELPER FUNCTIONS
# ─────────────────────────────────────────────────────────────────────────────

parse_utc_timestamp() {
    local ts="${1%Z}"
    TZ=UTC date -j -f "%Y-%m-%dT%H:%M:%S" "$ts" "+%s" 2>/dev/null
}

format_duration() {
    local secs=$1
    local hours=$((secs / 3600))
    local mins=$(((secs % 3600) / 60))
    local s=$((secs % 60))
    if [[ $hours -gt 0 ]]; then
        echo "${hours}h ${mins}m"
    elif [[ $mins -gt 0 ]]; then
        echo "${mins}m ${s}s"
    else
        echo "${s}s"
    fi
}

# Strip ANSI codes and get plain text length
strip_ansi() {
    # LC_ALL=C handles non-UTF8 byte sequences on macOS
    echo -e "$1" | LC_ALL=C sed 's/\x1b\[[0-9;]*m//g' 2>/dev/null || echo "$1"
}

# Calculate display width (plain char count after stripping ANSI)
display_width() {
    local text="$1"
    local plain=$(strip_ansi "$text")
    echo ${#plain}
}

# Truncate text to width (accounting for ANSI codes)
truncate_to_width() {
    local text="$1"
    local max_width="$2"
    local plain_text=$(strip_ansi "$text")
    local plain_len=${#plain_text}

    if [[ $plain_len -le $max_width ]]; then
        echo "$text"
    else
        # Simple truncation - may break ANSI codes but works for most cases
        local truncated=$(echo -e "$text" | head -c $((max_width + 50)) | sed 's/\x1b\[[0-9;]*m//g' | head -c $((max_width - 3)))
        echo "${truncated}..."
    fi
}

# Pad string to width (handles ANSI escape codes and wide chars)
pad_to_width() {
    local text="$1"
    local width="$2"
    local disp_len=$(display_width "$text")

    # First truncate if too long
    if [[ $disp_len -gt $width ]]; then
        text=$(truncate_to_width "$text" $width)
        disp_len=$(display_width "$text")
    fi

    local padding=$((width - disp_len))
    if [[ $padding -gt 0 ]]; then
        printf '%s%*s' "$text" "$padding" ""
    else
        printf '%s' "$text"
    fi
}

# Print horizontal line
print_hline() {
    local width="$1"
    local left="$2"
    local right="$3"
    local fill="${4:-$BOX_H}"
    printf '%s' "$left"
    for ((i=1; i<width-1; i++)); do printf '%s' "$fill"; done
    printf '%s\n' "$right"
}

# Print text with borders
print_bordered() {
    local text="$1"
    local width="$2"
    local padded=$(pad_to_width "$text" $((width - 4)))
    printf '%s %s %s\n' "$BOX_V" "$padded" "$BOX_V"
}

# Format raw action with colors based on type
format_action() {
    local raw="$1"
    local max_len="${2:-40}"  # Default max length for truncation
    local content=""

    case "$raw" in
        LOOP:*)
            # Ralph loop events (started/completed/failed tasks)
            content="${raw#LOOP:}"
            [[ ${#content} -gt $max_len ]] && content="${content:0:$max_len}.."
            if [[ "$content" == "✓"* ]]; then
                echo -e "${GREEN}${content}${NC}"
            elif [[ "$content" == "✗"* ]]; then
                echo -e "${RED}${content}${NC}"
            elif [[ "$content" == "⚠"* ]]; then
                echo -e "${YELLOW}${content}${NC}"
            elif [[ "$content" == "▸"* ]]; then
                echo -e "${CYAN}${content}${NC}"
            else
                echo -e "${DIM}${content}${NC}"
            fi
            ;;
        SUBAGENT:*)
            # Subagent spawned via Task tool - distinct visual
            content="${raw#SUBAGENT:}"
            local sub_status=""
            if [[ "$content" == *" ✓" ]]; then
                sub_status=" ${GREEN}✓${NC}"
                content="${content% ✓}"
            elif [[ "$content" == *" ✗" ]]; then
                sub_status=" ${RED}✗${NC}"
                content="${content% ✗}"
            fi
            [[ ${#content} -gt $max_len ]] && content="${content:0:$max_len}.."
            echo -e "\033[0;35m→ ${content}${NC}${sub_status}"  # Purple arrow for subagents
            ;;
        TOOL:*)
            content="${raw#TOOL:}"
            # Extract status suffix (✓ or ✗) if present
            local tool_status=""
            if [[ "$content" == *" ✓" ]]; then
                tool_status=" ${GREEN}✓${NC}"
                content="${content% ✓}"
            elif [[ "$content" == *" ✗" ]]; then
                tool_status=" ${RED}✗${NC}"
                content="${content% ✗}"
            fi
            # Split tool name from detail (Name|detail)
            local tool_name="$content"
            local tool_detail=""
            if [[ "$content" == *"|"* ]]; then
                tool_name="${content%%|*}"
                tool_detail="${content#*|}"
            fi
            # Format detail for known tools
            local detail_str=""
            if [[ -n "$tool_detail" ]]; then
                case "$tool_name" in
                    Bash)
                        # Parse common commands into brief labels
                        case "$tool_detail" in
                            *playwright*|*npx\ playwright*)
                                local pw_detail="${tool_detail##*playwright }"
                                pw_detail="${pw_detail%% *}"
                                [[ ${#pw_detail} -gt 25 ]] && pw_detail="${pw_detail:0:25}.."
                                detail_str=" playwright ${pw_detail}"
                                ;;
                            *npm\ run\ *)
                                local npm_cmd="${tool_detail##*npm run }"
                                npm_cmd="${npm_cmd%% *}"
                                detail_str=" npm run ${npm_cmd}"
                                ;;
                            *npm\ install*|*npm\ i\ *)
                                detail_str=" npm install"
                                ;;
                            *docker\ compose*|*docker-compose*)
                                local dc_cmd="${tool_detail##*compose }"
                                dc_cmd="${dc_cmd%% *}"
                                detail_str=" docker ${dc_cmd}"
                                ;;
                            *docker\ *)
                                local d_cmd="${tool_detail##*docker }"
                                d_cmd="${d_cmd%% *}"
                                detail_str=" docker ${d_cmd}"
                                ;;
                            *git\ diff*)   detail_str=" git diff" ;;
                            *git\ status*) detail_str=" git status" ;;
                            *git\ add*)    detail_str=" git add" ;;
                            *git\ commit*) detail_str=" git commit" ;;
                            *git\ log*)    detail_str=" git log" ;;
                            *git\ *)
                                local g_cmd="${tool_detail##*git }"
                                g_cmd="${g_cmd%% *}"
                                detail_str=" git ${g_cmd}"
                                ;;
                            *curl\ *)      detail_str=" curl" ;;
                            *cat\ *|*ls\ *|*mkdir\ *)
                                local sh_cmd="${tool_detail%% *}"
                                detail_str=" ${sh_cmd}"
                                ;;
                            *)
                                # Show first meaningful word(s)
                                local brief="${tool_detail%% 2>*}"  # strip stderr redirect
                                brief="${brief%% |*}"  # strip pipes
                                brief="${brief%% >*}"  # strip redirects
                                [[ ${#brief} -gt 30 ]] && brief="${brief:0:30}.."
                                detail_str=" ${brief}"
                                ;;
                        esac
                        ;;
                    Read|Edit|Write)
                        [[ ${#tool_detail} -gt 25 ]] && tool_detail="${tool_detail:0:25}.."
                        detail_str=" ${tool_detail}"
                        ;;
                    Grep|Glob)
                        [[ ${#tool_detail} -gt 25 ]] && tool_detail="${tool_detail:0:25}.."
                        detail_str=" ${tool_detail}"
                        ;;
                esac
            fi
            # Truncate combined output
            local display="${tool_name}${detail_str}"
            [[ ${#display} -gt $max_len ]] && display="${display:0:$((max_len - 2))}.."
            # Color-code by tool category
            case "$tool_name" in
                Edit|Write)         echo -e "${YELLOW}> ${display}${NC}${tool_status}" ;;
                Read|Glob|Grep)     echo -e "${BLUE}> ${display}${NC}${tool_status}" ;;
                Bash)               echo -e "${GREEN}> ${display}${NC}${tool_status}" ;;
                TodoWrite)          echo -e "${CYAN}> ${display}${NC}${tool_status}" ;;
                Skill)              echo -e "\033[0;35m> ${display}${NC}${tool_status}" ;;
                WebFetch|WebSearch) echo -e "${BLUE}> ${display}${NC}${tool_status}" ;;
                *)                  echo -e "${DIM}> ${display}${NC}${tool_status}" ;;
            esac
            ;;
        TEXT:*)
            content="${raw#TEXT:}"
            [[ ${#content} -gt $max_len ]] && content="${content:0:$max_len}.."
            echo -e "${DIM}  ${content}${NC}"
            ;;
        THINK:*)
            content="${raw#THINK:}"
            [[ ${#content} -gt $max_len ]] && content="${content:0:$max_len}.."
            echo -e "${DIM}  ..${content}${NC}"
            ;;
        *)
            echo -e "${DIM}  ${raw}${NC}"
            ;;
    esac
}

# ─────────────────────────────────────────────────────────────────────────────
# DATA GATHERING
# ─────────────────────────────────────────────────────────────────────────────

gather_data() {
    # Spec name
    SPEC_NAME=$(basename "$SPEC_DIR")

    # Progress data
    CURRENT_BATCH=()
    BATCH_STARTED_AT=""
    BATCH_STATUS="{}"
    BATCH_ELAPSED=0
    BATCH_TIMEOUT=14400  # 4 hours default

    if [[ -f "$SPEC_DIR/.ralph/progress.json" ]]; then
        PROGRESS_JSON=$(cat "$SPEC_DIR/.ralph/progress.json")
        STATUS=$(echo "$PROGRESS_JSON" | jq -r '.status')
        CURRENT_TASK=$(echo "$PROGRESS_JSON" | jq -r '.current_task // "none"')
        COMPLETED=$(echo "$PROGRESS_JSON" | jq -r '.completed_tasks | length')
        BLOCKED_REASON=$(echo "$PROGRESS_JSON" | jq -r '.blocked_reason // empty')
        COMPLETED_LIST=$(echo "$PROGRESS_JSON" | jq -r '.completed_tasks[]' 2>/dev/null)

        # Batch data
        local batch_json
        batch_json=$(echo "$PROGRESS_JSON" | jq -r '.current_batch // []')
        if [[ "$batch_json" != "[]" ]] && [[ "$batch_json" != "null" ]]; then
            while IFS= read -r task_id; do
                [[ -n "$task_id" ]] && CURRENT_BATCH+=("$task_id")
            done < <(echo "$batch_json" | jq -r '.[]' 2>/dev/null)
        fi
        BATCH_STARTED_AT=$(echo "$PROGRESS_JSON" | jq -r '.batch_started_at // empty')
        BATCH_STATUS=$(echo "$PROGRESS_JSON" | jq '.batch_status // {}')

        # Calculate batch elapsed time
        if [[ -n "$BATCH_STARTED_AT" ]] && [[ "$BATCH_STARTED_AT" != "null" ]]; then
            local batch_start_epoch
            batch_start_epoch=$(parse_utc_timestamp "$BATCH_STARTED_AT")
            if [[ -n "$batch_start_epoch" ]]; then
                NOW_EPOCH=$(date "+%s")
                BATCH_ELAPSED=$((NOW_EPOCH - batch_start_epoch))
            fi
        fi
    else
        STATUS="unknown"
        CURRENT_TASK="none"
        COMPLETED=0
        BLOCKED_REASON=""
        COMPLETED_LIST=""
    fi

    # Total tasks from tasks.md (including indented subtasks)
    TASKS_FILE="$SPEC_DIR/tasks.md"
    if [[ -f "$TASKS_FILE" ]]; then
        TOTAL_TASKS=$(grep -cE "^\s*- \[.\] T[0-9]+" "$TASKS_FILE" 2>/dev/null || echo "0")
    else
        TOTAL_TASKS=0
    fi

    # Calculate percentage
    if [[ "$TOTAL_TASKS" -gt 0 ]]; then
        PERCENT=$((COMPLETED * 100 / TOTAL_TASKS))
    else
        PERCENT=0
    fi

    # Run timing
    RUN_START=""
    RUN_ELAPSED=0
    TOTAL_ELAPSED=0
    SESSION_ELAPSED=0
    RESTART_COUNT=0
    TASK_ELAPSED=0
    TIMEOUT_SECS=7200  # Default: 120 minutes (matches Ralph's default)
    TASK_ATTEMPTS=1

    if [[ -f "$SPEC_DIR/.ralph/session.log" ]]; then
        NOW_EPOCH=$(date "+%s")

        # Total time: since FIRST task started (entire feature duration)
        FIRST_START=$(grep "Started task T" "$SPEC_DIR/.ralph/session.log" | head -1 | grep -o '^\[[^]]*\]' | tr -d '[]')
        if [[ -n "$FIRST_START" ]]; then
            FIRST_START_EPOCH=$(parse_utc_timestamp "$FIRST_START")
            if [[ -n "$FIRST_START_EPOCH" ]]; then
                TOTAL_ELAPSED=$((NOW_EPOCH - FIRST_START_EPOCH))
            fi
        fi

        # Session time: since last "Resumed Ralph loop" (after intervention/restart)
        LAST_RESUME=$(grep "Resumed Ralph loop" "$SPEC_DIR/.ralph/session.log" | tail -1 | grep -o '^\[[^]]*\]' | tr -d '[]')
        if [[ -n "$LAST_RESUME" ]]; then
            LAST_RESUME_EPOCH=$(parse_utc_timestamp "$LAST_RESUME")
            if [[ -n "$LAST_RESUME_EPOCH" ]]; then
                SESSION_ELAPSED=$((NOW_EPOCH - LAST_RESUME_EPOCH))
            fi
        fi

        # Count restarts (handle missing file gracefully)
        RESTART_COUNT=$(grep -c "Resumed Ralph loop" "$SPEC_DIR/.ralph/session.log" 2>/dev/null || echo 0)
        [[ -z "$RESTART_COUNT" ]] && RESTART_COUNT=0

        # Legacy: RUN_ELAPSED = session elapsed for backwards compat
        RUN_START=$(grep "Started task T" "$SPEC_DIR/.ralph/session.log" | head -1 | grep -o '^\[[^]]*\]' | tr -d '[]')
        if [[ -n "$RUN_START" ]]; then
            RUN_START_EPOCH=$(parse_utc_timestamp "$RUN_START")
            if [[ -n "$RUN_START_EPOCH" ]]; then
                RUN_ELAPSED=$((NOW_EPOCH - RUN_START_EPOCH))
            fi
        fi

        # Task timing
        if [[ -n "$CURRENT_TASK" ]] && [[ "$CURRENT_TASK" != "null" ]] && [[ "$CURRENT_TASK" != "none" ]]; then
            TASK_START=$(grep "Started task $CURRENT_TASK" "$SPEC_DIR/.ralph/session.log" | tail -1 | grep -o '^\[[^]]*\]' | tr -d '[]')
            if [[ -n "$TASK_START" ]]; then
                TASK_START_EPOCH=$(parse_utc_timestamp "$TASK_START")
                if [[ -n "$TASK_START_EPOCH" ]]; then
                    TASK_ELAPSED=$((NOW_EPOCH - TASK_START_EPOCH))
                fi
            fi

            # Attempt count
            TASK_ATTEMPTS=$(grep -c "Started task $CURRENT_TASK" "$SPEC_DIR/.ralph/session.log" 2>/dev/null || echo 1)
        fi

        # Timeout from running process (format: "timeout 7200 claude ...")
        TIMEOUT_PROC=$(ps aux 2>/dev/null | grep -E "timeout [0-9]+ claude" | grep -v grep | head -1 | sed -E 's/.*timeout ([0-9]+) claude.*/\1/')
        [[ -n "$TIMEOUT_PROC" ]] && TIMEOUT_SECS=$TIMEOUT_PROC
    fi

    # Stale detection: time since Claude last wrote output
    STALE_ELAPSED=0
    STALE_LIMIT_SECS=360  # Default: 36 × 10s
    # Load STALE_LIMIT from ralph.config if available
    if [[ -f "$SPEC_DIR/ralph.config" ]]; then
        local cfg_stale
        cfg_stale=$(grep -E '^STALE_LIMIT=' "$SPEC_DIR/ralph.config" 2>/dev/null | tail -1 | cut -d= -f2 | cut -d'#' -f1 | tr -dc '0-9')
        [[ -n "$cfg_stale" ]] && STALE_LIMIT_SECS=$((cfg_stale * 10))
    fi
    # Load TASK_TIMEOUT from ralph.config if available
    if [[ -f "$SPEC_DIR/ralph.config" ]]; then
        local cfg_timeout
        cfg_timeout=$(grep -E '^TASK_TIMEOUT=' "$SPEC_DIR/ralph.config" 2>/dev/null | tail -1 | cut -d= -f2 | cut -d'#' -f1 | tr -dc '0-9')
        [[ -n "$cfg_timeout" ]] && TIMEOUT_SECS=$cfg_timeout
    fi
    # Skipped tasks
    SKIPPED=""
    if [[ -n "$CURRENT_TASK" ]] && [[ "$CURRENT_TASK" != "null" ]] && [[ "$CURRENT_TASK" != "none" ]]; then
        CURRENT_NUM=$((10#$(echo "$CURRENT_TASK" | grep -o '[0-9]\+')))
        for i in $(seq 1 $((CURRENT_NUM - 1))); do
            TASK_ID=$(printf "T%03d" $i)
            if ! echo "$COMPLETED_LIST" | grep -q "^$TASK_ID$"; then
                if [[ -n "$SKIPPED" ]]; then
                    SKIPPED="$SKIPPED, $TASK_ID"
                else
                    SKIPPED="$TASK_ID"
                fi
            fi
        done
    fi

    # Current task description (limit based on terminal width)
    # Supports both top-level tasks (^- [ ]) and indented subtasks (^  - [ ])
    TASK_DESC=""
    if [[ -n "$CURRENT_TASK" ]] && [[ "$CURRENT_TASK" != "null" ]] && [[ -f "$SPEC_DIR/tasks.md" ]]; then
        TASK_LINE=$(grep -E "^[[:space:]]*- \[[ x]\] $CURRENT_TASK " "$SPEC_DIR/tasks.md" 2>/dev/null | head -1)
        local max_desc_len=$((TERM_COLS / 2 - 15))  # Leave room for task ID and borders
        [[ $max_desc_len -lt 20 ]] && max_desc_len=20
        [[ $max_desc_len -gt 60 ]] && max_desc_len=60
        TASK_DESC=$(echo "$TASK_LINE" | sed -E "s/^[[:space:]]*- \[[ x]\] $CURRENT_TASK //" | head -c $max_desc_len)
    fi

    # Next task
    NEXT_TASK_ID=""
    NEXT_TASK_DESC=""
    if [[ -f "$SPEC_DIR/.ralph/progress.json" ]] && [[ -f "$SPEC_DIR/tasks.md" ]]; then
        COMPLETED_REGEX=$(echo "$COMPLETED_LIST" | tr '\n' '|' | sed 's/|$//')
        while IFS= read -r line; do
            TID=$(echo "$line" | grep -o 'T[0-9]\+' | head -1)
            if [[ -n "$TID" ]] && [[ "$TID" != "$CURRENT_TASK" ]]; then
                if [[ -z "$COMPLETED_REGEX" ]] || ! echo "$TID" | grep -qE "^($COMPLETED_REGEX)$"; then
                    NEXT_TASK_ID="$TID"
                    NEXT_TASK_DESC=$(echo "$line" | sed "s/^- \[ \] $TID //" | head -c 60)
                    break
                fi
            fi
        done < <(grep "^- \[ \]" "$SPEC_DIR/tasks.md" 2>/dev/null)
    fi

    # Metrics calculation
    AVG_TIME=0
    SUCCESS_RATE=100
    ETA=0
    FAILED_COUNT=0

    if [[ -f "$SPEC_DIR/.ralph/session.log" ]] && [[ "$COMPLETED" -gt 0 ]]; then
        # Calculate avg task duration: time from last Started to Completed for each task
        COMPLETED_TIMES=()
        local last_start_epoch=""
        while IFS= read -r line; do
            if [[ "$line" =~ ^\[([^\]]+)\].*Started\ task ]]; then
                local ts="${BASH_REMATCH[1]}"
                last_start_epoch=$(parse_utc_timestamp "$ts")
            elif [[ "$line" =~ ^\[([^\]]+)\].*Completed\ task ]]; then
                local ts="${BASH_REMATCH[1]}"
                local end_epoch=$(parse_utc_timestamp "$ts")
                if [[ -n "$last_start_epoch" ]] && [[ -n "$end_epoch" ]]; then
                    local dur=$((end_epoch - last_start_epoch))
                    [[ $dur -gt 0 ]] && COMPLETED_TIMES+=($dur)
                fi
                last_start_epoch=""
            fi
        done < "$SPEC_DIR/.ralph/session.log"

        if [[ ${#COMPLETED_TIMES[@]} -gt 0 ]]; then
            TOTAL_TIME=0
            for t in "${COMPLETED_TIMES[@]}"; do
                TOTAL_TIME=$((TOTAL_TIME + t))
            done
            AVG_TIME=$((TOTAL_TIME / ${#COMPLETED_TIMES[@]}))
        fi

        # Failed count: unique tasks that permanently failed (not retries)
        FAILED_COUNT=$(jq '.failed_tasks | length' "$SPEC_DIR/.ralph/progress.json" 2>/dev/null || echo 0)

        # Success rate: completed tasks vs total attempted (completed + permanently failed unique tasks)
        local unique_failed
        unique_failed=$(jq '[.failed_tasks[].id] | unique | length' "$SPEC_DIR/.ralph/progress.json" 2>/dev/null || echo 0)
        if [[ $((COMPLETED + unique_failed)) -gt 0 ]]; then
            SUCCESS_RATE=$((COMPLETED * 100 / (COMPLETED + unique_failed)))
        fi

        # ETA
        REMAINING=$((TOTAL_TASKS - COMPLETED))
        if [[ "$AVG_TIME" -gt 0 ]] && [[ "$REMAINING" -gt 0 ]]; then
            ETA=$((REMAINING * AVG_TIME))
        fi
    fi

    # Git activity
    GIT_COMMITS=0
    GIT_LATEST=""
    GIT_FILES=0

    if [[ -n "$RUN_START" ]]; then
        RUN_START_ISO=$(echo "$RUN_START" | sed 's/T/ /')

        cd "$PROJECT_DIR" 2>/dev/null || cd "$(dirname "$SPEC_DIR")" 2>/dev/null

        if git rev-parse --git-dir &>/dev/null; then
            GIT_COMMITS=$(git log --oneline --since="$RUN_START_ISO" 2>/dev/null | wc -l | tr -d ' ')
            local max_commit_len=$((TERM_COLS / 2 - 15))
            [[ $max_commit_len -lt 30 ]] && max_commit_len=30
            [[ $max_commit_len -gt 50 ]] && max_commit_len=50
            GIT_LATEST=$(git log --oneline -1 2>/dev/null | head -c $max_commit_len)
            if [[ "$GIT_COMMITS" -gt 0 ]]; then
                GIT_FILES=$(git diff --name-only HEAD~$GIT_COMMITS 2>/dev/null | wc -l | tr -d ' ')
            fi
        fi
    fi

    # Active session - find Ralph's CURRENT session
    # Ralph sessions have "# Task Execution Context" at the START of the first user message
    ACTIVE_SESSION=""
    SESSION_ID=""

    # Find most recent Ralph session (sorted by mod time, first match wins)
    for session in $(ls -t "$CLAUDE_PROJECT_PATH"/*.jsonl 2>/dev/null | head -15); do
        # Check if FIRST user message starts with "# Task Execution Context"
        local first_user_msg
        first_user_msg=$(head -5 "$session" 2>/dev/null | jq -r 'select(.type == "user") | .message.content' 2>/dev/null | head -1)

        if [[ "$first_user_msg" == "# Task Execution Context"* ]]; then
            ACTIVE_SESSION="$session"
            SESSION_ID=$(basename "$session" .jsonl)
            break
        fi

        # For resumed sessions starting with summary: check first user message after summary
        local first_type
        first_type=$(head -1 "$session" 2>/dev/null | jq -r '.type' 2>/dev/null)
        if [[ "$first_type" == "summary" ]]; then
            first_user_msg=$(head -20 "$session" 2>/dev/null | jq -r 'select(.type == "user") | .message.content' 2>/dev/null | head -1)
            if [[ "$first_user_msg" == "# Task Execution Context"* ]]; then
                ACTIVE_SESSION="$session"
                SESSION_ID=$(basename "$session" .jsonl)
                break
            fi
        fi
    done

    # Stale mtime check (must be after ACTIVE_SESSION is found)
    if [[ -n "$ACTIVE_SESSION" ]] && [[ -f "$ACTIVE_SESSION" ]]; then
        local session_mtime
        session_mtime=$(stat -f%m "$ACTIVE_SESSION" 2>/dev/null || echo 0)
        if [[ "$session_mtime" -gt 0 ]]; then
            local now_epoch
            now_epoch=$(date "+%s")
            STALE_ELAPSED=$((now_epoch - session_mtime))
            [[ $STALE_ELAPSED -lt 0 ]] && STALE_ELAPSED=0
        fi
    fi

    # Recent actions (last 25) - show tool_use, text, and thinking
    RECENT_ACTIONS=()
    RECENT_ACTIONS_RAW=()
    if [[ -n "$ACTIVE_SESSION" ]] && [[ -f "$ACTIVE_SESSION" ]]; then
        local actions_output
        # Extract tool_use (with id) and tool_result (with id + is_error) in one pass,
        # then post-process to append ✓/✗ to each tool line
        actions_output=$(tail -500 "$ACTIVE_SESSION" 2>/dev/null | jq -r '
            if .type == "assistant" then
                .message.content[]? |
                if .type == "tool_use" then
                    if .name == "Task" then
                        "SUBAGENT:" + .id + ":" + (.input.description // "subagent")
                    elif .name == "Bash" then
                        "TOOL:" + .id + ":Bash|" + ((.input.command // "") | split("\n")[0] | .[0:100])
                    elif .name == "Read" then
                        "TOOL:" + .id + ":Read|" + ((.input.file_path // "") | split("/") | last)
                    elif .name == "Edit" then
                        "TOOL:" + .id + ":Edit|" + ((.input.file_path // "") | split("/") | last)
                    elif .name == "Write" then
                        "TOOL:" + .id + ":Write|" + ((.input.file_path // "") | split("/") | last)
                    elif .name == "Grep" then
                        "TOOL:" + .id + ":Grep|" + (.input.pattern // "")
                    elif .name == "Glob" then
                        "TOOL:" + .id + ":Glob|" + (.input.pattern // "")
                    else
                        "TOOL:" + .id + ":" + .name
                    end
                elif .type == "text" then "TEXT:" + (.text | split("\n")[0] | .[0:120])
                elif .type == "thinking" then "THINK:" + (.thinking | split("\n")[0] | .[0:120])
                else empty
                end
            elif .type == "user" then
                .message.content[]? |
                select(.type == "tool_result") |
                "RESULT:" + .tool_use_id + ":" + (if .is_error then "err" else "ok" end)
            else empty
            end' 2>/dev/null | grep -v '^$' | tail -60)

        # Build result lookup and merge into tool lines
        local result_ids_ok=()
        local result_ids_err=()
        local merged_lines=()
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            if [[ "$line" == RESULT:* ]]; then
                local rid="${line#RESULT:}"
                local tool_id="${rid%%:*}"
                local status="${rid##*:}"
                if [[ "$status" == "err" ]]; then
                    result_ids_err+=("$tool_id")
                else
                    result_ids_ok+=("$tool_id")
                fi
            else
                merged_lines+=("$line")
            fi
        done <<< "$actions_output"

        # Append ✓/✗ to tool/subagent lines based on result
        for line in "${merged_lines[@]}"; do
            local prefix="${line%%:*}"
            if [[ "$prefix" == "TOOL" || "$prefix" == "SUBAGENT" ]]; then
                local rest="${line#*:}"
                local tool_id="${rest%%:*}"
                local content="${rest#*:}"
                local suffix=""
                if [[ ${#result_ids_err[@]} -gt 0 ]]; then
                    for eid in "${result_ids_err[@]}"; do
                        [[ "$eid" == "$tool_id" ]] && suffix=" ✗" && break
                    done
                fi
                if [[ -z "$suffix" ]] && [[ ${#result_ids_ok[@]} -gt 0 ]]; then
                    for oid in "${result_ids_ok[@]}"; do
                        [[ "$oid" == "$tool_id" ]] && suffix=" ✓" && break
                    done
                fi
                RECENT_ACTIONS_RAW+=("${prefix}:${content}${suffix}")
            else
                RECENT_ACTIONS_RAW+=("$line")
            fi
        done
        # Keep only last 25
        if [[ ${#RECENT_ACTIONS_RAW[@]} -gt 25 ]]; then
            RECENT_ACTIONS_RAW=("${RECENT_ACTIONS_RAW[@]: -25}")
        fi
    fi

    # Add loop events for the CURRENT task from session.log
    # These get prepended so they appear as context before Claude's actions
    if [[ -f "$SPEC_DIR/.ralph/session.log" ]] && [[ -n "$CURRENT_TASK" ]] && [[ "$CURRENT_TASK" != "null" ]]; then
        local loop_lines=()
        local in_current_task=false
        # Read from bottom up, find events between "Started task $CURRENT_TASK" and now
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            # Strip timestamp: [2026-02-05T23:14:07Z] -> rest
            local rest="${line#*] }"
            # Check for level tag: [INFO] msg -> msg, or plain msg
            local content="$rest"
            if [[ "$rest" == \[*\]* ]]; then
                content="${rest#*] }"
            fi
            if [[ "$content" == "Started task $CURRENT_TASK"* ]]; then
                in_current_task=true
                loop_lines=()  # Reset on each start (handles restarts)
                loop_lines+=("LOOP:▸ Start $CURRENT_TASK")
            elif [[ "$in_current_task" == true ]]; then
                if [[ "$content" == "Completed task"* ]]; then
                    loop_lines+=("LOOP:✓ Done $CURRENT_TASK")
                elif [[ "$content" == "Failed task"* ]] || [[ "$content" == *"failed"* ]] || [[ "$content" == *"BLOCKED"* ]]; then
                    loop_lines+=("LOOP:✗ Failed")
                elif [[ "$content" == *"Build passed"* ]]; then
                    loop_lines+=("LOOP:✓ Build")
                elif [[ "$content" == *"Tests passed"* ]]; then
                    loop_lines+=("LOOP:✓ Tests")
                elif [[ "$content" == *"Build failed"* ]]; then
                    loop_lines+=("LOOP:✗ Build")
                elif [[ "$content" == *"Tests failed"* ]]; then
                    loop_lines+=("LOOP:✗ Tests")
                elif [[ "$content" == *"Invoking Claude"* ]]; then
                    loop_lines+=("LOOP:▸ Claude")
                elif [[ "$content" == *"build verification"* ]] || [[ "$content" == *"Verifying"* ]]; then
                    loop_lines+=("LOOP:▸ Verify")
                elif [[ "$content" == Commit* ]]; then
                    loop_lines+=("LOOP:✓ ${content}")
                elif [[ "$content" == *"Timeout"* ]]; then
                    loop_lines+=("LOOP:✗ Timeout")
                elif [[ "$content" == *"Retrying"* ]]; then
                    loop_lines+=("LOOP:⚠ Retry")
                elif [[ "$content" == *"Stop requested"* ]]; then
                    loop_lines+=("LOOP:⚠ Stop")
                elif [[ "$content" == *"BLOCKED"* ]]; then
                    loop_lines+=("LOOP:✗ BLOCKED")
                elif [[ "$content" == "Failed"* ]]; then
                    loop_lines+=("LOOP:✗ ${content}")
                fi
            fi
        done < <(tail -30 "$SPEC_DIR/.ralph/session.log" 2>/dev/null)
        # Prepend loop events, then Claude actions follow
        if [[ ${#loop_lines[@]} -gt 0 ]]; then
            RECENT_ACTIONS_RAW=("${loop_lines[@]}" "${RECENT_ACTIONS_RAW[@]}")
        fi
        # Trim to last 30
        if [[ ${#RECENT_ACTIONS_RAW[@]} -gt 30 ]]; then
            RECENT_ACTIONS_RAW=("${RECENT_ACTIONS_RAW[@]: -30}")
        fi
    fi

    # Format raw actions with colors (reverse order - newest first)
    # Max length scales with terminal width (right column gets 50%)
    local action_fmt_len=$(( (TERM_COLS - 3) / 2 - 4 ))
    [[ $action_fmt_len -lt 40 ]] && action_fmt_len=40
    if [[ ${#RECENT_ACTIONS_RAW[@]} -gt 0 ]]; then
        for ((i=${#RECENT_ACTIONS_RAW[@]}-1; i>=0; i--)); do
            RECENT_ACTIONS+=("$(format_action "${RECENT_ACTIONS_RAW[$i]}" "$action_fmt_len")")
        done
    fi

    # Session Tasks (TodoWrite) - read from current Claude session's todo storage only
    # No fallback to old sessions — stale todos from completed tasks should not show
    SESSION_TODOS=()
    local TODO_FILE=""

    if [[ -n "$SESSION_ID" ]]; then
        local ralph_todo="$HOME/.claude/todos/${SESSION_ID}-agent-${SESSION_ID}.json"
        if [[ -f "$ralph_todo" ]] && [[ $(stat -f%z "$ralph_todo" 2>/dev/null || echo 0) -gt 10 ]]; then
            TODO_FILE="$ralph_todo"
        fi
    fi

    if [[ -n "$TODO_FILE" ]] && [[ -f "$TODO_FILE" ]]; then
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            SESSION_TODOS+=("$line")
        done < <(jq -r '.[] |
            (if .status == "in_progress" then "[~] "
             elif .status == "completed" then "[x] "
             else "[ ] " end) + .content' "$TODO_FILE" 2>/dev/null)
    fi

    # Skills used in current task
    CURRENT_TASK_SKILLS=""
    if [[ -n "$ACTIVE_SESSION" ]] && [[ -f "$ACTIVE_SESSION" ]]; then
        CURRENT_TASK_SKILLS=$(jq -r 'select(.type == "assistant") | .message.content[]? | select(.type == "tool_use" and .name == "Skill") | .input.skill' "$ACTIVE_SESSION" 2>/dev/null | sort -u | head -3 | tr '\n' ', ' | sed 's/,$//')
    fi

    # Skills used (this run)
    SKILLS_AGG=""
    if [[ -n "$RUN_START" ]]; then
        RUN_START_EPOCH_SKILLS=$(parse_utc_timestamp "$RUN_START" 2>/dev/null)
        if [[ -n "$RUN_START_EPOCH_SKILLS" ]]; then
            SKILLS_AGG=$(find "$CLAUDE_PROJECT_PATH" -name "*.jsonl" -type f 2>/dev/null | while read f; do
                FILE_MTIME=$(stat -f '%m' "$f" 2>/dev/null)
                if [[ -n "$FILE_MTIME" ]] && [[ "$FILE_MTIME" -ge "$RUN_START_EPOCH_SKILLS" ]]; then
                    if head -20 "$f" 2>/dev/null | grep -q "Task Execution Context"; then
                        jq -r 'select(.type == "assistant") | .message.content[]? | select(.type == "tool_use" and .name == "Skill") | .input.skill' "$f" 2>/dev/null
                    fi
                fi
            done | sort | uniq -c | sort -rn | head -5)
        fi
    fi

    # Process info
    RALPH_PID=""
    CLAUDE_PID=""
    CLAUDE_VERSION=""
    SPEC_NAME_SHORT=$(basename "$SPEC_DIR")
    RALPH_PID=$(ps aux | grep "ralph.sh.*$SPEC_NAME_SHORT" | grep -v grep | awk '{print $2}' | head -1)
    if [[ -n "$RALPH_PID" ]]; then
        # Get Claude child process PID
        CLAUDE_PID=$(ps -o pid,ppid,comm | awk -v ppid="$RALPH_PID" '$2 == ppid && $3 ~ /claude|node/ {print $1}' | head -1)
    fi
    # Get Claude Code version
    if command -v claude &>/dev/null; then
        CLAUDE_VERSION=$(claude --version 2>/dev/null | head -1 | awk '{print "v"$1}')
    fi

    # Detect model from running ralph.sh process args or from ralph.sh source
    CLAUDE_MODEL=""
    if [[ -n "$RALPH_PID" ]]; then
        CLAUDE_MODEL=$(ps aux | grep "$RALPH_PID" | grep -o '\-\-model [^ ]*' | head -1 | awk '{print $2}')
    fi
    if [[ -z "$CLAUDE_MODEL" ]]; then
        # Fallback: extract from ralph.sh source
        local ralph_script=""
        local candidate
        for candidate in \
            "$PROJECT_DIR/.specify/ralph/lib/ralph.sh" \
            "$PROJECT_DIR/lib/ralph.sh" \
            "$SCRIPT_DIR/../../../lib/ralph.sh"
        do
            if [[ -f "$candidate" ]]; then
                ralph_script="$candidate"
                break
            fi
        done
        if [[ -n "$ralph_script" ]]; then
            CLAUDE_MODEL=$(grep -o '\-\-model [^ "]*' "$ralph_script" 2>/dev/null | head -1 | awk '{print $2}')
        fi
    fi

    # Git branch
    GIT_BRANCH=""
    if git rev-parse --git-dir &>/dev/null 2>&1; then
        GIT_BRANCH=$(git branch --show-current 2>/dev/null)
    fi

    # Commits per hour
    COMMITS_PER_HOUR=""
    if [[ "$GIT_COMMITS" -gt 0 ]] && [[ "$TOTAL_ELAPSED" -gt 0 ]]; then
        local hours_elapsed=$((TOTAL_ELAPSED / 3600))
        if [[ "$hours_elapsed" -gt 0 ]]; then
            COMMITS_PER_HOUR=$((GIT_COMMITS / hours_elapsed))
        else
            COMMITS_PER_HOUR="$GIT_COMMITS"
        fi
    fi

    # Last task completion time
    LAST_TASK_TIME=""
    if [[ -f "$SPEC_DIR/.ralph/session.log" ]] && [[ "$COMPLETED" -gt 0 ]]; then
        local last_completed
        last_completed=$(grep "Completed task" "$SPEC_DIR/.ralph/session.log" | tail -1 | grep -o '^\[[^]]*\]' | tr -d '[]')
        if [[ -n "$last_completed" ]]; then
            local last_epoch
            last_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$last_completed" "+%s" 2>/dev/null)
            if [[ -n "$last_epoch" ]]; then
                local ago=$(( $(date +%s) - last_epoch ))
                LAST_TASK_TIME="$(format_duration $ago) ago"
            fi
        fi
    fi

    # Failed count from progress.json
    FAILED_COUNT=0
    if [[ -f "$SPEC_DIR/.ralph/progress.json" ]]; then
        FAILED_COUNT=$(jq '.failed_tasks | length' "$SPEC_DIR/.ralph/progress.json" 2>/dev/null || echo 0)
    fi

    # Docker containers (show running containers, use DOCKER_FILTER from config if set)
    DOCKER_STATUS=()
    if command -v docker &>/dev/null; then
        local docker_filter="${DOCKER_FILTER:-}"
        if [[ -n "$docker_filter" ]]; then
            while IFS=$'\t' read -r name status; do
                [[ -n "$name" ]] && DOCKER_STATUS+=("$name:$status")
            done < <(docker ps --filter "name=$docker_filter" --format "{{.Names}}\t{{.Status}}" 2>/dev/null | head -3)
        else
            # No filter - show any running containers
            while IFS=$'\t' read -r name status; do
                [[ -n "$name" ]] && DOCKER_STATUS+=("$name:$status")
            done < <(docker ps --format "{{.Names}}\t{{.Status}}" 2>/dev/null | head -3)
        fi
    fi

    # Port health (use PORT_CHECK from config if set, default to 3000,3001)
    # Uses nc (netcat) for TCP check - works for any service, not just HTTP
    local ports_to_check="${PORT_CHECK:-3000,3001}"
    PORT_STATUS=()
    for port in ${ports_to_check//,/ }; do
        local status="down"
        # Use nc for TCP port check (works for databases, etc.)
        if command -v nc &>/dev/null; then
            nc -z localhost "$port" 2>/dev/null && status="up"
        else
            # Fallback to curl for HTTP
            curl -s -o /dev/null --max-time 1 "http://localhost:$port" 2>/dev/null && status="up"
        fi
        PORT_STATUS+=("$port:$status")
    done

    # Cost (from session if available)
    COST=""
    if [[ -n "$ACTIVE_SESSION" ]] && [[ -f "$ACTIVE_SESSION" ]]; then
        # Look for cost info in session (usually at end)
        COST_RAW=$(tail -100 "$ACTIVE_SESSION" | grep -o '"totalCost":[0-9.]*' | tail -1 | cut -d: -f2)
        if [[ -n "$COST_RAW" ]] && [[ "$COST_RAW" != "0" ]]; then
            COST=$(printf "%.2f" "$COST_RAW" 2>/dev/null)
        fi
    fi

    # Stop file
    STOP_FILE_EXISTS=false
    [[ -f "$SPEC_DIR/.ralph/.stop" ]] && STOP_FILE_EXISTS=true
}

# ─────────────────────────────────────────────────────────────────────────────
# RENDER: WIDE LAYOUT (80+ cols)
# ─────────────────────────────────────────────────────────────────────────────

render_wide() {
    local width=$TERM_COLS
    # Minimum width based on size mode (default=100, compact=80, large=120)
    local min_width=100
    case "$SIZE_MODE" in
        compact) min_width=80 ;;
        large)   min_width=120 ;;
    esac
    [[ $width -lt $min_width ]] && width=$min_width

    # Calculate content widths (excluding borders)
    # Equal 50/50 split, both columns wide
    local total_content=$((width - 3))  # 3 = left border + center border + right border
    local left_content=$((total_content / 2))
    local right_content=$((total_content - left_content))

    # Build progress bar (scales with left column, min 15, max 30)
    local bar_width=$((left_content / 3))
    [[ $bar_width -lt 15 ]] && bar_width=15
    [[ $bar_width -gt 30 ]] && bar_width=30
    local filled=$((PERCENT * bar_width / 100))
    local empty=$((bar_width - filled))
    local bar=""
    for ((i=0; i<filled; i++)); do bar+="█"; done
    for ((i=0; i<empty; i++)); do bar+="░"; done

    # Action text max length scales with right column
    local action_max_len=$((right_content - 4))

    # Helper to draw full-width line (top/bottom borders) - no center divider
    draw_full_line() {
        local left="$1" right="$2"
        printf '%s' "$left"
        for ((i=0; i<total_content+1; i++)); do printf '%s' "$BOX_H"; done
        printf '%s\n' "$right"
    }

    # Helper to draw two-column header line (with center divider ┬)
    draw_two_col_header() {
        printf '%s' "$BOX_VR"
        for ((i=0; i<left_content; i++)); do printf '%s' "$BOX_H"; done
        printf '%s' "$BOX_HD"
        for ((i=0; i<right_content; i++)); do printf '%s' "$BOX_H"; done
        printf '%s\n' "$BOX_VL"
    }

    # Helper to draw LEFT-ONLY separator (keeps right column continuous)
    draw_left_separator() {
        printf '%s' "$BOX_VR"
        for ((i=0; i<left_content; i++)); do printf '%s' "$BOX_H"; done
        printf '%s' "$BOX_VL"  # End left side
        # Right side: continue with content
        printf '%s' "$BOX_VR"  # Start right continuation
        for ((i=0; i<right_content-1; i++)); do printf ' '; done
        printf '%s\n' "$BOX_V"
    }

    # Helper to draw two-column content row
    draw_row() {
        local left_text="$1"
        local right_text="$2"
        local l=$(pad_to_width "$left_text" $left_content)
        local r=$(pad_to_width "$right_text" $right_content)
        printf '%s%s%s%s%s\n' "$BOX_V" "$l" "$BOX_V" "$r" "$BOX_V"
    }

    # Helper to draw full-width content row (no center divider)
    draw_full_content_row() {
        local text="$1"
        local full_width=$((total_content + 1))  # +1 for the center border we're replacing with space
        local padded=$(pad_to_width "$text" $full_width)
        printf '%s%s%s\n' "$BOX_V" "$padded" "$BOX_V"
    }

    # Helper to draw full-width separator that transitions to two-column
    draw_full_separator() {
        printf '%s' "$BOX_VR"
        for ((i=0; i<left_content; i++)); do printf '%s' "$BOX_H"; done
        printf '%s' "$BOX_HD"  # ┬ creates the column split
        for ((i=0; i<right_content; i++)); do printf '%s' "$BOX_H"; done
        printf '%s\n' "$BOX_VL"
    }

    # Collect all left-side content into arrays by section
    local -a left_lines=()
    local -a right_lines=()
    local action_idx=0

    # ═══════════════════════════════════════════════════════════════════════════
    # BUILD LEFT COLUMN CONTENT
    # ═══════════════════════════════════════════════════════════════════════════

    # Header row
    left_lines+=("${BOLD}Ralph: $SPEC_NAME${NC}")
    right_lines+=("Total: $(format_duration $TOTAL_ELAPSED) | #${RESTART_COUNT}")

    # Session time row
    left_lines+=("Session: $(format_duration $SESSION_ELAPSED)")
    right_lines+=("")

    # Cost (if present)
    if [[ -n "$COST" ]] && [[ "$COST" != "0.00" ]]; then
        left_lines+=("${YELLOW}Cost: \$$COST${NC}")
        right_lines+=("")
    fi

    # Blank line after header
    left_lines+=("")
    right_lines+=("")

    # Section: PROGRESS
    left_lines+=("${BOLD}─ PROGRESS ─${NC}")
    local session_label="${SESSION_ID:0:8}" # First 8 chars of session ID
    right_lines+=("${BOLD}─ RECENT ACTIONS ─${NC} ${DIM}(${session_label:-none})${NC}")

    local progress_text="[${GREEN}${bar}${NC}] ${COMPLETED}/${TOTAL_TASKS} (${PERCENT}%)"
    left_lines+=("$progress_text")
    right_lines+=("${RECENT_ACTIONS[$action_idx]:-}"); ((action_idx++))

    local status_color="$NC"
    case "$STATUS" in
        running) status_color="$GREEN" ;;
        blocked) status_color="$RED" ;;
        paused) status_color="$YELLOW" ;;
    esac
    left_lines+=("Status: ${status_color}${STATUS}${NC}")
    right_lines+=("${RECENT_ACTIONS[$action_idx]:-}"); ((action_idx++))

    if [[ -n "$SKIPPED" ]]; then
        left_lines+=("${YELLOW}Skipped: $SKIPPED${NC}")
        right_lines+=("${RECENT_ACTIONS[$action_idx]:-}"); ((action_idx++))
    fi
    left_lines+=("")  # Blank line after section
    right_lines+=("${RECENT_ACTIONS[$action_idx]:-}"); ((action_idx++))

    # Section: CURRENT TODOS (TodoWrite)
    left_lines+=("${BOLD}─ CURRENT TODOS ─${NC}")
    right_lines+=("${RECENT_ACTIONS[$action_idx]:-}"); ((action_idx++))

    if [[ ${#SESSION_TODOS[@]} -gt 0 ]]; then
        local todo_count=0
        for todo in "${SESSION_TODOS[@]}"; do
            [[ $todo_count -ge 5 ]] && break  # Limit to 5 todos
            left_lines+=("$todo")
            right_lines+=("${RECENT_ACTIONS[$action_idx]:-}"); ((action_idx++))
            ((todo_count++))
        done
        if [[ ${#SESSION_TODOS[@]} -gt 5 ]]; then
            left_lines+=("${DIM}... and $((${#SESSION_TODOS[@]} - 5)) more${NC}")
            right_lines+=("${RECENT_ACTIONS[$action_idx]:-}"); ((action_idx++))
        fi
    else
        left_lines+=("${DIM}No active todos${NC}")
        right_lines+=("${RECENT_ACTIONS[$action_idx]:-}"); ((action_idx++))
    fi
    left_lines+=("")  # Blank line after section
    right_lines+=("${RECENT_ACTIONS[$action_idx]:-}"); ((action_idx++))


    # Section: CURRENT TASK or CURRENT BATCH
    if [[ ${#CURRENT_BATCH[@]} -gt 1 ]]; then
        # ─── BATCH MODE ───
        local batch_count=${#CURRENT_BATCH[@]}
        local first_task="${CURRENT_BATCH[0]}"
        local last_task="${CURRENT_BATCH[$((batch_count-1))]}"

        left_lines+=("${BOLD}─ BATCH (${batch_count} tasks) ─${NC}")
        right_lines+=("${RECENT_ACTIONS[$action_idx]:-}"); ((action_idx++))

        # Show batch progress bar
        local batch_completed=0
        local batch_running=0
        for task_id in "${CURRENT_BATCH[@]}"; do
            local task_status
            task_status=$(echo "$BATCH_STATUS" | jq -r --arg id "$task_id" '.[$id] // "pending"')
            [[ "$task_status" == "completed" ]] && ((batch_completed++))
            [[ "$task_status" == "running" ]] && ((batch_running++))
        done

        local batch_bar_width=15
        local batch_filled=$((batch_completed * batch_bar_width / batch_count))
        local batch_bar=""
        for ((i=0; i<batch_filled; i++)); do batch_bar+="█"; done
        for ((i=batch_filled; i<batch_bar_width; i++)); do batch_bar+="░"; done

        left_lines+=("[${GREEN}${batch_bar}${NC}] ${batch_completed}/${batch_count}")
        right_lines+=("${RECENT_ACTIONS[$action_idx]:-}"); ((action_idx++))

        # Show each task status with title (up to 6)
        local shown=0
        for task_id in "${CURRENT_BATCH[@]}"; do
            [[ $shown -ge 6 ]] && break
            local task_status
            task_status=$(echo "$BATCH_STATUS" | jq -r --arg id "$task_id" '.[$id] // "pending"')
            local status_icon="○"
            case "$task_status" in
                completed) status_icon="${GREEN}✓${NC}" ;;
                running)   status_icon="${YELLOW}~${NC}" ;;
                failed)    status_icon="${RED}✗${NC}" ;;
            esac
            # Get task title from tasks.md (truncate to 30 chars)
            local task_title=""
            if [[ -f "$TASKS_FILE" ]]; then
                task_title=$(grep -E "^\s*- \[.\] $task_id " "$TASKS_FILE" 2>/dev/null | sed "s/.*$task_id //" | head -c 50)
            fi
            [[ -n "$task_title" ]] && task_title=": ${task_title}"
            left_lines+=("$status_icon $task_id${task_title}")
            right_lines+=("${RECENT_ACTIONS[$action_idx]:-}"); ((action_idx++))
            ((shown++))
        done

        # Batch timing
        local batch_time_remaining=$((BATCH_TIMEOUT - BATCH_ELAPSED))
        local batch_time_color="$GREEN"
        [[ $batch_time_remaining -le 1800 ]] && batch_time_color="$YELLOW"  # 30min
        [[ $batch_time_remaining -le 600 ]] && batch_time_color="$RED"      # 10min
        local batch_timeout_mins=$((BATCH_TIMEOUT / 60))
        left_lines+=("Time: ${batch_time_color}$(format_duration $BATCH_ELAPSED)${NC} / ${batch_timeout_mins}m")
        right_lines+=("${RECENT_ACTIONS[$action_idx]:-}"); ((action_idx++))
    else
        # ─── SINGLE TASK MODE ───
        left_lines+=("${BOLD}─ TASK ─${NC}")
        right_lines+=("${RECENT_ACTIONS[$action_idx]:-}"); ((action_idx++))

        local task_text="$CURRENT_TASK"
        [[ -n "$TASK_DESC" ]] && task_text="$CURRENT_TASK: $TASK_DESC"
        left_lines+=("$task_text")
        right_lines+=("${RECENT_ACTIONS[$action_idx]:-}"); ((action_idx++))

        # Task timeout countdown
        local time_remaining=$((TIMEOUT_SECS - TASK_ELAPSED))
        [[ $time_remaining -lt 0 ]] && time_remaining=0
        local time_pct=0
        [[ $TIMEOUT_SECS -gt 0 ]] && time_pct=$((TASK_ELAPSED * 100 / TIMEOUT_SECS))
        [[ $time_pct -gt 100 ]] && time_pct=100
        local time_color="$DIM"
        [[ $time_pct -ge 50 ]] && time_color="$YELLOW"
        [[ $time_pct -ge 80 ]] && time_color="$RED"
        local bar_filled=$((time_pct / 10))
        local bar_empty=$((10 - bar_filled))
        local time_bar=""
        for ((b=0; b<bar_filled; b++)); do time_bar+="█"; done
        for ((b=0; b<bar_empty; b++)); do time_bar+="░"; done
        local timeout_mins=$((TIMEOUT_SECS / 60))
        left_lines+=("${time_color}${time_bar} $(format_duration $time_remaining)${NC} / ${timeout_mins}m | Try $TASK_ATTEMPTS")
        right_lines+=("${RECENT_ACTIONS[$action_idx]:-}"); ((action_idx++))

        # Stale countdown (time since last output) — only when running
        if [[ "$STATUS" == "running" ]] && [[ $STALE_LIMIT_SECS -gt 0 ]]; then
            local stale_pct=0
            [[ $STALE_LIMIT_SECS -gt 0 ]] && stale_pct=$((STALE_ELAPSED * 100 / STALE_LIMIT_SECS))
            [[ $stale_pct -gt 100 ]] && stale_pct=100
            local stale_color="$DIM"
            [[ $stale_pct -ge 50 ]] && stale_color="$YELLOW"
            [[ $stale_pct -ge 80 ]] && stale_color="$RED"
            local sbar_filled=$((stale_pct / 10))
            local sbar_empty=$((10 - sbar_filled))
            local stale_bar=""
            for ((b=0; b<sbar_filled; b++)); do stale_bar+="█"; done
            for ((b=0; b<sbar_empty; b++)); do stale_bar+="░"; done
            local stale_remaining=$((STALE_LIMIT_SECS - STALE_ELAPSED))
            [[ $stale_remaining -lt 0 ]] && stale_remaining=0
            if [[ $STALE_ELAPSED -le 10 ]]; then
                left_lines+=("${DIM}${stale_bar} active${NC}")
            else
                left_lines+=("${stale_color}${stale_bar} idle ${STALE_ELAPSED}s${NC} / ${STALE_LIMIT_SECS}s")
            fi
            right_lines+=("${RECENT_ACTIONS[$action_idx]:-}"); ((action_idx++))
        fi

        if [[ -n "$NEXT_TASK_ID" ]]; then
            left_lines+=("${DIM}Next: $NEXT_TASK_ID $NEXT_TASK_DESC${NC}")
            right_lines+=("${RECENT_ACTIONS[$action_idx]:-}"); ((action_idx++))
        fi
    fi
    left_lines+=("")  # Blank line after section
    right_lines+=("${RECENT_ACTIONS[$action_idx]:-}"); ((action_idx++))

    # Section: METRICS
    left_lines+=("${BOLD}─ METRICS ─${NC}")
    right_lines+=("${RECENT_ACTIONS[$action_idx]:-}"); ((action_idx++))

    local metrics_line="Avg: $(format_duration $AVG_TIME)/task | Success: ${SUCCESS_RATE}%"
    [[ "$FAILED_COUNT" -gt 0 ]] && metrics_line+=" | ${RED}${FAILED_COUNT} failed${NC}"
    left_lines+=("$metrics_line")
    right_lines+=("${RECENT_ACTIONS[$action_idx]:-}"); ((action_idx++))

    left_lines+=("ETA: ~$(format_duration $ETA) (${REMAINING:-0} tasks left)")
    right_lines+=("${RECENT_ACTIONS[$action_idx]:-}"); ((action_idx++))

    if [[ -n "$LAST_TASK_TIME" ]]; then
        left_lines+=("${DIM}Last completed: $LAST_TASK_TIME${NC}")
        right_lines+=("${RECENT_ACTIONS[$action_idx]:-}"); ((action_idx++))
    fi
    left_lines+=("")  # Blank line after section
    right_lines+=("${RECENT_ACTIONS[$action_idx]:-}"); ((action_idx++))

    # Section: INFRASTRUCTURE
    left_lines+=("${BOLD}─ INFRA ─${NC}")
    right_lines+=("${RECENT_ACTIONS[$action_idx]:-}"); ((action_idx++))

    local proc_icon="✗" proc_color="$RED"
    [[ -n "$RALPH_PID" ]] && proc_icon="✓" && proc_color="$GREEN"
    local claude_info="Claude Code ${CLAUDE_VERSION:-?}"
    [[ -n "$CLAUDE_PID" ]] && claude_info+=" (PID: $CLAUDE_PID)" || claude_info+=" (waiting)"
    left_lines+=("${proc_color}${proc_icon}${NC} $claude_info")
    right_lines+=("${RECENT_ACTIONS[$action_idx]:-}"); ((action_idx++))

    if [[ -n "$CLAUDE_MODEL" ]]; then
        left_lines+=("${CYAN}Model: $CLAUDE_MODEL${NC}")
        right_lines+=("${RECENT_ACTIONS[$action_idx]:-}"); ((action_idx++))
    fi

    if [[ ${#DOCKER_STATUS[@]} -gt 0 ]]; then
        for ds in "${DOCKER_STATUS[@]}"; do
            local name="${ds%%:*}"
            local st="${ds##*:}"
            local icon="${RED}✗${NC}"
            [[ "$st" == *"healthy"* ]] || [[ "$st" == *"Up"* ]] && icon="${GREEN}✓${NC}"
            left_lines+=("$icon ${name%%-local}")
            right_lines+=("${RECENT_ACTIONS[$action_idx]:-}"); ((action_idx++))
        done
    else
        left_lines+=("${DIM}No containers${NC}")
        right_lines+=("${RECENT_ACTIONS[$action_idx]:-}"); ((action_idx++))
    fi

    local port_text="Ports: "
    for ps in "${PORT_STATUS[@]}"; do
        local port="${ps%%:*}"
        local status="${ps##*:}"
        [[ "$status" == "up" ]] && port_text+="${GREEN}✓${NC}$port " || port_text+="${RED}✗${NC}$port "
    done
    left_lines+=("$port_text")
    right_lines+=("${RECENT_ACTIONS[$action_idx]:-}"); ((action_idx++))
    left_lines+=("")  # Blank line after section
    right_lines+=("${RECENT_ACTIONS[$action_idx]:-}"); ((action_idx++))

    # Section: GIT
    left_lines+=("${BOLD}─ GIT ─${NC}")
    right_lines+=("${RECENT_ACTIONS[$action_idx]:-}"); ((action_idx++))

    local git_summary="$GIT_COMMITS commits | $GIT_FILES files"
    [[ -n "$COMMITS_PER_HOUR" ]] && git_summary+=" | ~${COMMITS_PER_HOUR}/hr"
    left_lines+=("$git_summary")
    right_lines+=("${RECENT_ACTIONS[$action_idx]:-}"); ((action_idx++))

    if [[ -n "$GIT_BRANCH" ]]; then
        left_lines+=("${CYAN}⎇ $GIT_BRANCH${NC}")
        right_lines+=("${RECENT_ACTIONS[$action_idx]:-}"); ((action_idx++))
    fi

    if [[ -n "$GIT_LATEST" ]]; then
        left_lines+=("${DIM}$GIT_LATEST${NC}")
        right_lines+=("${RECENT_ACTIONS[$action_idx]:-}"); ((action_idx++))
    fi
    left_lines+=("")  # Blank line after section
    right_lines+=("${RECENT_ACTIONS[$action_idx]:-}"); ((action_idx++))

    # Section: SKILLS
    left_lines+=("${BOLD}─ SKILLS ─${NC}")
    right_lines+=("${RECENT_ACTIONS[$action_idx]:-}"); ((action_idx++))

    local skill_line="${DIM}None${NC}"
    if [[ -n "$SKILLS_AGG" ]]; then
        skill_line=$(echo "$SKILLS_AGG" | head -1)
    fi
    left_lines+=("Run: $skill_line")
    right_lines+=("${RECENT_ACTIONS[$action_idx]:-}"); ((action_idx++))

    if [[ -n "$CURRENT_TASK_SKILLS" ]]; then
        left_lines+=("${CYAN}Task: $CURRENT_TASK_SKILLS${NC}")
        right_lines+=("${RECENT_ACTIONS[$action_idx]:-}"); ((action_idx++))
    fi

    # ═══════════════════════════════════════════════════════════════════════════
    # RENDER OUTPUT
    # ═══════════════════════════════════════════════════════════════════════════

    # ASCII Art Header
    echo -e "${DIM}  ____       _       _"
    echo " |  _ \\ __ _| |_ __ | |__"
    echo " | |_) / _\` | | '_ \\| '_ \\"
    echo " |  _ < (_| | | |_) | | | |"
    echo " |_| \\_\\__,_|_| .__/|_| |_|"
    echo -e "              |_|  ${NC}${BOLD}Wiggum Loop${NC}${DIM} · Spec-Kit Extension by T-0${NC}"
    echo ""
    echo -e "${DIM}Version 0.1.0 - Autonomous Task Monitoring${NC}"
    echo ""

    # ─── ACTIVE TASK(S) HEADER (full width) ───
    local has_active_header=false
    if [[ ${#CURRENT_BATCH[@]} -gt 1 ]]; then
        has_active_header=true
    elif [[ -n "$CURRENT_TASK" ]] && [[ "$CURRENT_TASK" != "none" ]] && [[ "$CURRENT_TASK" != "null" ]]; then
        has_active_header=true
    fi

    # Top border - full width if we have active header, otherwise two-column
    if [[ "$has_active_header" == true ]]; then
        draw_full_line "$BOX_TL" "$BOX_TR"
    else
        # Two-column top border with center divider
        printf '%s' "$BOX_TL"
        for ((i=0; i<left_content; i++)); do printf '%s' "$BOX_H"; done
        printf '%s' "$BOX_HD"
        for ((i=0; i<right_content; i++)); do printf '%s' "$BOX_H"; done
        printf '%s\n' "$BOX_TR"
    fi

    if [[ ${#CURRENT_BATCH[@]} -gt 1 ]]; then
        # Batch mode - show all active tasks
        draw_full_content_row "${BOLD}ACTIVE BATCH (${#CURRENT_BATCH[@]} tasks)${NC}"
        for task_id in "${CURRENT_BATCH[@]}"; do
            local task_title=""
            if [[ -f "$TASKS_FILE" ]]; then
                task_title=$(grep -E "^\s*- \[.\] $task_id " "$TASKS_FILE" 2>/dev/null | sed "s/.*$task_id //" | head -1)
            fi
            local task_status
            task_status=$(echo "$BATCH_STATUS" | jq -r --arg id "$task_id" '.[$id] // "pending"' 2>/dev/null)
            local status_icon="○"
            case "$task_status" in
                completed) status_icon="${GREEN}✓${NC}" ;;
                running)   status_icon="${YELLOW}▸${NC}" ;;
                failed)    status_icon="${RED}✗${NC}" ;;
            esac
            draw_full_content_row " $status_icon ${CYAN}$task_id${NC}: $task_title"
        done
        draw_full_separator
    elif [[ -n "$CURRENT_TASK" ]] && [[ "$CURRENT_TASK" != "none" ]] && [[ "$CURRENT_TASK" != "null" ]]; then
        # Single task mode
        local task_title=""
        if [[ -f "$TASKS_FILE" ]]; then
            task_title=$(grep -E "^\s*- \[.\] $CURRENT_TASK " "$TASKS_FILE" 2>/dev/null | sed "s/.*$CURRENT_TASK //" | head -1)
        fi
        draw_full_content_row "${BOLD}ACTIVE TASK${NC}"
        draw_full_content_row " ${YELLOW}▸${NC} ${CYAN}$CURRENT_TASK${NC}: $task_title"
        draw_full_separator
    fi

    # Pad rows to fill terminal height with remaining actions
    # Header art=8 lines, active task=2-3, top border=1, separator=1, bottom border=1, footer=1 ≈ ~14 overhead
    local term_rows=$(tput lines 2>/dev/null || echo 40)
    local overhead=14
    if [[ "$has_active_header" == true ]]; then
        overhead=$((overhead + 3))
    fi
    local available_rows=$((term_rows - overhead))
    [[ $available_rows -lt ${#left_lines[@]} ]] && available_rows=${#left_lines[@]}

    # Extend left/right arrays to fill available space
    while [[ ${#left_lines[@]} -lt $available_rows ]]; do
        left_lines+=("")
        right_lines+=("${RECENT_ACTIONS[$action_idx]:-}")
        ((action_idx++))
    done

    # Render all rows (two-column)
    for ((i=0; i<${#left_lines[@]}; i++)); do
        local left="${left_lines[$i]}"
        local right="${right_lines[$i]}"
        draw_row "$left" "$right"
    done

    # Bottom border (always two-column style with center divider)
    printf '%s' "$BOX_BL"
    for ((i=0; i<left_content; i++)); do printf '%s' "$BOX_H"; done
    printf '%s' "$BOX_HU"  # ┴
    for ((i=0; i<right_content; i++)); do printf '%s' "$BOX_H"; done
    printf '%s\n' "$BOX_BR"

    # Footer info
    local updated="Updated: $(date '+%H:%M:%S')"
    if [[ "$STOP_FILE_EXISTS" == true ]]; then
        echo -e "${RED}⚠ Stop file present${NC}  |  $updated"
    else
        echo -e "${DIM}$updated  |  Ctrl+C to exit${NC}"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# RENDER: NARROW LAYOUT (<80 cols) - All same info as wide, single column
# ─────────────────────────────────────────────────────────────────────────────

render_narrow() {
    # ASCII Art Header
    echo -e "${DIM}  ____       _       _"
    echo " |  _ \\ __ _| |_ __ | |__"
    echo " | |_) / _\` | | '_ \\| '_ \\"
    echo " |  _ < (_| | | |_) | | | |"
    echo " |_| \\_\\__,_|_| .__/|_| |_|"
    echo -e "              |_|  ${NC}${BOLD}Wiggum Loop${NC}${DIM} · Spec-Kit Extension by T-0${NC}"
    echo ""
    echo -e "${DIM}Version 0.1.0 - Autonomous Task Monitoring${NC}"
    echo ""

    # Header with timing
    echo -e "${BOLD}═══ Ralph: $(basename "$SPEC_DIR") ═══${NC}"
    echo -e "Total: $(format_duration $TOTAL_ELAPSED) | Restarts: ${RESTART_COUNT}"
    echo -e "Session: $(format_duration $SESSION_ELAPSED)"
    echo ""

    # Cost banner
    if [[ -n "$COST" ]] && [[ "$COST" != "0.00" ]]; then
        echo -e "${YELLOW}💰 Session: \$$COST${NC}"
        echo ""
    fi

    # Build progress bar
    local bar_width=20
    local filled=$((PERCENT * bar_width / 100))
    local empty=$((bar_width - filled))
    local bar=""
    for ((i=0; i<filled; i++)); do bar+="█"; done
    for ((i=0; i<empty; i++)); do bar+="░"; done

    # ─── PROGRESS ───
    echo -e "${YELLOW}─── PROGRESS ───${NC}"
    echo -e "[${GREEN}${bar}${NC}] ${COMPLETED}/${TOTAL_TASKS} (${PERCENT}%)"

    local status_color="$NC"
    case "$STATUS" in
        running) status_color="$GREEN" ;;
        blocked) status_color="$RED" ;;
        paused) status_color="$YELLOW" ;;
    esac
    echo -e "Status: ${status_color}${STATUS}${NC}"
    [[ -n "$SKIPPED" ]] && echo -e "${YELLOW}Skipped: $SKIPPED${NC}"
    echo ""

    # ─── CURRENT TODOS (TodoWrite) ───
    echo -e "${YELLOW}─── CURRENT TODOS ───${NC}"
    if [[ ${#SESSION_TODOS[@]} -gt 0 ]]; then
        local todo_count=0
        for todo in "${SESSION_TODOS[@]}"; do
            [[ $todo_count -ge 5 ]] && break  # Limit to 5 todos
            echo "$todo"
            ((todo_count++))
        done
        if [[ ${#SESSION_TODOS[@]} -gt 5 ]]; then
            echo -e "${DIM}... and $((${#SESSION_TODOS[@]} - 5)) more${NC}"
        fi
    else
        echo -e "${DIM}No active todos${NC}"
    fi
    echo ""

    # ─── CURRENT TASK or BATCH ───
    if [[ ${#CURRENT_BATCH[@]} -gt 1 ]]; then
        # ─── BATCH MODE ───
        local batch_count=${#CURRENT_BATCH[@]}
        echo -e "${YELLOW}─── BATCH (${batch_count} tasks) ───${NC}"

        # Show batch progress
        local batch_completed=0
        for task_id in "${CURRENT_BATCH[@]}"; do
            local task_status
            task_status=$(echo "$BATCH_STATUS" | jq -r --arg id "$task_id" '.[$id] // "pending"')
            [[ "$task_status" == "completed" ]] && ((batch_completed++))
        done

        local batch_bar_width=15
        local batch_filled=$((batch_completed * batch_bar_width / batch_count))
        local batch_bar=""
        for ((i=0; i<batch_filled; i++)); do batch_bar+="█"; done
        for ((i=batch_filled; i<batch_bar_width; i++)); do batch_bar+="░"; done
        echo -e "[${GREEN}${batch_bar}${NC}] ${batch_completed}/${batch_count}"

        # Show each task status with title
        local shown=0
        for task_id in "${CURRENT_BATCH[@]}"; do
            [[ $shown -ge 6 ]] && break
            local task_status
            task_status=$(echo "$BATCH_STATUS" | jq -r --arg id "$task_id" '.[$id] // "pending"')
            local status_icon="○"
            case "$task_status" in
                completed) status_icon="${GREEN}✓${NC}" ;;
                running)   status_icon="${YELLOW}~${NC}" ;;
                failed)    status_icon="${RED}✗${NC}" ;;
            esac
            # Get task title from tasks.md (truncate to 30 chars)
            local task_title=""
            if [[ -f "$TASKS_FILE" ]]; then
                task_title=$(grep -E "^\s*- \[.\] $task_id " "$TASKS_FILE" 2>/dev/null | sed "s/.*$task_id //" | head -c 50)
            fi
            [[ -n "$task_title" ]] && task_title=": ${task_title}"
            echo -e "$status_icon $task_id${task_title}"
            ((shown++))
        done

        # Batch timing
        local batch_time_remaining=$((BATCH_TIMEOUT - BATCH_ELAPSED))
        local batch_time_color="$GREEN"
        [[ $batch_time_remaining -le 1800 ]] && batch_time_color="$YELLOW"
        [[ $batch_time_remaining -le 600 ]] && batch_time_color="$RED"
        local batch_timeout_mins=$((BATCH_TIMEOUT / 60))
        echo -e "Time: ${batch_time_color}$(format_duration $BATCH_ELAPSED)${NC} / ${batch_timeout_mins}m"
    else
        # ─── SINGLE TASK MODE ───
        echo -e "${YELLOW}─── CURRENT TASK ───${NC}"
        local task_text="$CURRENT_TASK"
        [[ -n "$TASK_DESC" ]] && task_text="$CURRENT_TASK: $TASK_DESC"
        echo "$task_text"

        local time_remaining=$((TIMEOUT_SECS - TASK_ELAPSED))
        local time_color="$GREEN"
        [[ $time_remaining -le 600 ]] && time_color="$YELLOW"
        [[ $time_remaining -le 300 ]] && time_color="$RED"
        local timeout_mins=$((TIMEOUT_SECS / 60))
        echo -e "Time: ${time_color}$(format_duration $TASK_ELAPSED)${NC} / ${timeout_mins}m limit"
        echo "Attempt: $TASK_ATTEMPTS"
        [[ -n "$NEXT_TASK_ID" ]] && echo -e "${DIM}Next: $NEXT_TASK_ID $NEXT_TASK_DESC${NC}"
    fi
    echo ""

    # ─── METRICS ───
    echo -e "${YELLOW}─── METRICS ───${NC}"
    echo "Avg: $(format_duration $AVG_TIME)/task"
    echo "Success: ${SUCCESS_RATE}%"
    local remaining=$((TOTAL_TASKS - COMPLETED))
    echo "ETA: ~$(format_duration $ETA) ($remaining tasks left)"
    echo ""

    # ─── INFRASTRUCTURE ───
    echo -e "${YELLOW}─── INFRA ───${NC}"
    if [[ -n "$RALPH_PID" ]]; then
        local claude_info="Claude Code ${CLAUDE_VERSION:-?}"
        [[ -n "$CLAUDE_PID" ]] && claude_info+=" (PID: $CLAUDE_PID)" || claude_info+=" (waiting)"
        echo -e "${GREEN}✓${NC} $claude_info"
    else
        echo -e "${RED}✗${NC} No Ralph process"
    fi

    if [[ ${#DOCKER_STATUS[@]} -gt 0 ]]; then
        for ds in "${DOCKER_STATUS[@]}"; do
            local name="${ds%%:*}"
            local st="${ds##*:}"
            if [[ "$st" == *"healthy"* ]] || [[ "$st" == *"Up"* ]]; then
                echo -e "${GREEN}✓${NC} ${name%%-local}"
            else
                echo -e "${RED}✗${NC} ${name%%-local}"
            fi
        done
    else
        echo -e "${DIM}No containers${NC}"
    fi

    local port_line=""
    for ps in "${PORT_STATUS[@]}"; do
        local port="${ps%%:*}"
        local status="${ps##*:}"
        [[ "$status" == "up" ]] && port_line+="${GREEN}✓${NC}$port " || port_line+="${RED}✗${NC}$port "
    done
    echo -e "Ports: $port_line"
    echo ""

    # ─── GIT ───
    echo -e "${YELLOW}─── GIT ───${NC}"
    echo "$GIT_COMMITS commits | $GIT_FILES files"
    [[ -n "$GIT_LATEST" ]] && echo -e "${DIM}$GIT_LATEST${NC}"
    echo ""

    # ─── SKILLS ───
    echo -e "${YELLOW}─── SKILLS ───${NC}"
    if [[ -n "$SKILLS_AGG" ]]; then
        echo "$SKILLS_AGG" | head -3
    else
        echo -e "${DIM}None${NC}"
    fi
    [[ -n "$CURRENT_TASK_SKILLS" ]] && echo -e "${CYAN}Task: $CURRENT_TASK_SKILLS${NC}"
    echo ""

    # ─── RECENT ACTIONS ───
    local session_label="${SESSION_ID:0:8}"
    echo -e "${YELLOW}─── RECENT ACTIONS ───${NC} ${DIM}(${session_label:-none})${NC}"
    if [[ ${#RECENT_ACTIONS[@]} -gt 0 ]]; then
        for action in "${RECENT_ACTIONS[@]}"; do
            echo "$action"
        done
    else
        echo -e "${DIM}No actions yet${NC}"
    fi
    echo ""

    # Footer
    local updated="Updated: $(date '+%H:%M:%S')"
    if [[ "$STOP_FILE_EXISTS" == true ]]; then
        echo -e "${RED}⚠ Stop file present${NC}"
    fi
    echo -e "${DIM}$updated | Ctrl+C to exit${NC}"
}

# ─────────────────────────────────────────────────────────────────────────────
# MAIN
# ─────────────────────────────────────────────────────────────────────────────

render_dashboard() {
    gather_data

    if [[ "$SIMPLE_MODE" == true ]]; then
        render_narrow
    elif [[ $TERM_COLS -ge $MIN_WIDE_COLS ]]; then
        render_wide
    else
        render_narrow
    fi
}

if [[ "$LOOP_MODE" == true ]]; then
    trap 'exit 0' EXIT INT TERM
    REFRESH_SECS="${RALPH_CONTEXT_REFRESH_SECS:-1}"
    [[ "$REFRESH_SECS" =~ ^[0-9]+$ ]] || REFRESH_SECS=1
    (( REFRESH_SECS < 1 )) && REFRESH_SECS=1

    while true; do
        # Update terminal size (unless forced)
        if [[ -z "$FORCE_WIDTH" ]]; then
            TERM_COLS=$(tput cols 2>/dev/null || echo 80)
        fi
        TERM_ROWS=$(tput rows 2>/dev/null || echo 24)

        # Buffer ALL output, then print at once
        OUTPUT=$(render_dashboard)

        # Clear and print in one shot
        printf '\033c%s' "$OUTPUT"

        sleep "$REFRESH_SECS"
    done
else
    render_dashboard
fi
