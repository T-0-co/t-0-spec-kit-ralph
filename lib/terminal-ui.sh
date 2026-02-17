#!/usr/bin/env bash
# terminal-ui.sh - Rich terminal progress display
# Part of speckit-ralph

set -euo pipefail

# Terminal UI for Ralph loop progress
# Usage: terminal-ui.sh <spec_dir> [--watch]

SPEC_DIR="${1:-}"
WATCH_MODE="${2:-}"

if [[ -z "$SPEC_DIR" ]]; then
    echo "Error: spec_dir required" >&2
    exit 1
fi

RALPH_DIR="$SPEC_DIR/.ralph"
PROGRESS_FILE="$RALPH_DIR/progress.json"

# ANSI escape codes
ESC="\033"
BOLD="${ESC}[1m"
DIM="${ESC}[2m"
RESET="${ESC}[0m"
RED="${ESC}[31m"
GREEN="${ESC}[32m"
YELLOW="${ESC}[33m"
BLUE="${ESC}[34m"
CYAN="${ESC}[36m"

# Box drawing characters
TL="╔"
TR="╗"
BL="╚"
BR="╝"
H="═"
V="║"
ML="╠"
MR="╣"

# Terminal dimensions
COLS=$(tput cols 2>/dev/null || echo 70)
WIDTH=$((COLS > 70 ? 70 : COLS))

# Draw horizontal line
draw_line() {
    local char="${1:-$H}"
    local left="${2:-$TL}"
    local right="${3:-$TR}"
    printf "%s" "$left"
    for ((i=0; i<WIDTH-2; i++)); do
        printf "%s" "$char"
    done
    printf "%s\n" "$right"
}

# Draw text line with padding
draw_text() {
    local text="$1"
    local align="${2:-left}"
    local stripped
    stripped=$(echo -e "$text" | sed 's/\x1b\[[0-9;]*m//g')
    local len=${#stripped}
    local padding=$((WIDTH - 4 - len))

    printf "%s  " "$V"
    if [[ "$align" == "center" ]]; then
        local left_pad=$((padding / 2))
        local right_pad=$((padding - left_pad))
        printf "%*s%b%*s" "$left_pad" "" "$text" "$right_pad" ""
    else
        printf "%b%*s" "$text" "$padding" ""
    fi
    printf "  %s\n" "$V"
}

# Draw progress bar
draw_progress_bar() {
    local current="$1"
    local total="$2"
    local bar_width=$((WIDTH - 20))

    if [[ "$total" -eq 0 ]]; then
        total=1
    fi

    local filled=$((current * bar_width / total))
    local empty=$((bar_width - filled))
    local percent=$((current * 100 / total))

    local bar=""
    for ((i=0; i<filled; i++)); do
        bar+="█"
    done
    for ((i=0; i<empty; i++)); do
        bar+="░"
    done

    draw_text "${GREEN}${bar}${RESET} ${percent}%"
}

# Get spec name from path
get_spec_name() {
    basename "$SPEC_DIR"
}

# Render full UI
render_ui() {
    if [[ ! -f "$PROGRESS_FILE" ]]; then
        echo "No progress data found"
        return
    fi

    # Read progress data
    local data
    data=$(cat "$PROGRESS_FILE")

    local status
    status=$(echo "$data" | jq -r '.status')
    local current_task
    current_task=$(echo "$data" | jq -r '.current_task // "none"')
    local current_attempt
    current_attempt=$(echo "$data" | jq -r '.current_attempt // 0')
    local completed_count
    completed_count=$(echo "$data" | jq -r '.completed_tasks | length')
    local failed_count
    failed_count=$(echo "$data" | jq -r '.failed_tasks | length')
    local total_input
    total_input=$(echo "$data" | jq -r '.total_input_tokens // 0')
    local total_output
    total_output=$(echo "$data" | jq -r '.total_output_tokens // 0')
    local total_cost
    total_cost=$(echo "$data" | jq -r '.total_cost_usd // 0')

    # Calculate elapsed time
    local started_at
    started_at=$(echo "$data" | jq -r '.started_at // ""')
    local elapsed=""
    if [[ -n "$started_at" ]]; then
        local start_epoch
        start_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$started_at" "+%s" 2>/dev/null || date -d "$started_at" "+%s" 2>/dev/null || echo "0")
        local now_epoch
        now_epoch=$(date "+%s")
        local diff=$((now_epoch - start_epoch))
        local hours=$((diff / 3600))
        local mins=$(((diff % 3600) / 60))
        elapsed="${hours}h ${mins}m"
    fi

    # Get total tasks from tasks.md
    local total_tasks=0
    if [[ -f "$SPEC_DIR/tasks.md" ]]; then
        total_tasks=$(grep -cE "^[[:space:]]*-[[:space:]]*\[[xX[:space:]]\][[:space:]]+T[0-9]+" "$SPEC_DIR/tasks.md" 2>/dev/null || echo "0")
    fi

    # Clear screen and draw
    printf "\033[2J\033[H"

    # Header
    draw_line "$H" "$TL" "$TR"
    draw_text "${BOLD}${BLUE}RALPH LOOP${RESET} - $(get_spec_name)" "center"
    draw_line "$H" "$ML" "$MR"

    # Status line
    local status_color="$GREEN"
    local status_icon="🔄"
    case "$status" in
        running)   status_color="$GREEN"; status_icon="🔄" ;;
        blocked)   status_color="$RED";   status_icon="🚫" ;;
        completed) status_color="$GREEN"; status_icon="✅" ;;
    esac
    draw_text "Status: ${status_color}${status}${RESET} $status_icon"

    # Progress
    draw_text "Progress: $completed_count / $total_tasks tasks"
    draw_progress_bar "$completed_count" "$total_tasks"

    draw_line "$H" "$ML" "$MR"

    # Current task
    if [[ "$current_task" != "none" ]] && [[ "$current_task" != "null" ]]; then
        draw_text "${YELLOW}Current Task:${RESET} $current_task"
        draw_text "Attempt: $current_attempt / 3"
    else
        draw_text "${DIM}No task in progress${RESET}"
    fi

    draw_line "$H" "$ML" "$MR"

    # Stats
    draw_text "${CYAN}Completed:${RESET} $completed_count   ${RED}Failed:${RESET} $failed_count"

    # Tokens and cost
    local input_k=$((total_input / 1000))
    local output_k=$((total_output / 1000))
    local cost_fmt
    cost_fmt=$(printf "%.2f" "$total_cost")
    draw_text "Tokens: ${input_k}K in / ${output_k}K out"
    draw_text "Cost: \$${cost_fmt}   Time: $elapsed"

    # Footer
    draw_line "$H" "$BL" "$BR"

    # Blocked reason if applicable
    if [[ "$status" == "blocked" ]]; then
        local reason
        reason=$(echo "$data" | jq -r '.blocked_reason // "unknown"')
        echo ""
        echo -e "${RED}BLOCKED:${RESET} $reason"
        echo "Run: ralph --resume $SPEC_DIR"
    fi
}

# Watch mode - refresh every 2 seconds
watch_ui() {
    while true; do
        render_ui
        sleep 2
    done
}

# Main
if [[ "$WATCH_MODE" == "--watch" ]]; then
    watch_ui
else
    render_ui
fi
