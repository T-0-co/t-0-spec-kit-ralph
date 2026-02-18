#!/usr/bin/env bash
# ralph_ctl.sh - Control script for Ralph orchestration via tmux
# Usage: ralph_ctl.sh <command> [args]

set -euo pipefail

TMUX_SESSION="ralph"

usage() {
    cat <<USAGE
Ralph Orchestrator Control

Usage: ralph_ctl.sh <command> [args]

Commands:
  start <project_root> <spec_dir>  Start Ralph in tmux
  stop                              Kill Ralph and processes
  status                            Show tmux session status
  watch [lines]                     Show tmux output (default: 20 lines)
  open                              Open tmux in Warp for user
  logs <spec_dir>                   Show session log

Examples:
  ralph_ctl.sh start /path/to/my-project specs/001-my-feature
  ralph_ctl.sh stop
  ralph_ctl.sh watch 50
USAGE
}

cmd_start() {
    local project_root="${1:-}"
    local spec_dir="${2:-}"
    
    if [[ -z "$project_root" ]] || [[ -z "$spec_dir" ]]; then
        echo "Error: project_root and spec_dir required" >&2
        exit 1
    fi
    
    # Kill existing session
    tmux kill-session -t "$TMUX_SESSION" 2>/dev/null || true
    
    # Start new session
    tmux new-session -d -s "$TMUX_SESSION" -c "$project_root"
    tmux send-keys -t "$TMUX_SESSION" "./.specify/ralph/lib/ralph.sh --resume $spec_dir/" Enter
    
    echo "Ralph started in tmux session '$TMUX_SESSION'"
    echo "Attach with: tmux attach -t $TMUX_SESSION"
}

cmd_stop() {
    pkill -f "ralph.sh" 2>/dev/null || true
    pkill -f "timeout.*claude" 2>/dev/null || true
    tmux kill-session -t "$TMUX_SESSION" 2>/dev/null || true
    echo "Ralph stopped"
}

cmd_status() {
    if tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
        echo "Session: $TMUX_SESSION (running)"
        tmux list-sessions | grep "$TMUX_SESSION"
    else
        echo "Session: $TMUX_SESSION (not running)"
    fi
    
    # Show any ralph processes
    echo ""
    echo "Processes:"
    ps aux | grep -E "(ralph|timeout.*claude)" | grep -v grep || echo "  (none)"
}

cmd_watch() {
    local lines="${1:-20}"
    
    if ! tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
        echo "No tmux session '$TMUX_SESSION'" >&2
        exit 1
    fi
    
    tmux capture-pane -t "$TMUX_SESSION" -p | tail -"$lines"
}

cmd_open() {
    # macOS + Warp terminal specific. Adapt for your terminal emulator
    # or replace with: tmux attach -t "$TMUX_SESSION"
    osascript \
        -e 'tell application "Warp" to activate' \
        -e 'delay 0.5' \
        -e 'tell application "System Events" to tell process "Warp" to keystroke "t" using command down' \
        -e 'delay 0.3' \
        -e 'tell application "System Events" to tell process "Warp" to keystroke "tmux attach -t ralph"' \
        -e 'tell application "System Events" to tell process "Warp" to key code 36'
    echo "Opened tmux in Warp (macOS only - adapt cmd_open for other terminals)"
}

cmd_logs() {
    local spec_dir="${1:-}"
    
    if [[ -z "$spec_dir" ]]; then
        echo "Error: spec_dir required" >&2
        exit 1
    fi
    
    local log_file="$spec_dir/.ralph/session.log"
    if [[ -f "$log_file" ]]; then
        tail -20 "$log_file"
    else
        echo "No log file at $log_file"
    fi
}

# Main dispatch
case "${1:-}" in
    start)  shift; cmd_start "$@" ;;
    stop)   cmd_stop ;;
    status) cmd_status ;;
    watch)  shift; cmd_watch "$@" ;;
    open)   cmd_open ;;
    logs)   shift; cmd_logs "$@" ;;
    -h|--help|"") usage ;;
    *)
        echo "Unknown command: $1" >&2
        usage >&2
        exit 1
        ;;
esac
