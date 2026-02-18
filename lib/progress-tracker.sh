#!/usr/bin/env bash
# progress-tracker.sh - Persist Ralph loop state across invocations
# Part of speckit-ralph

# Only set strict mode when executed directly
if [[ "${BASH_SOURCE[0]:-$0}" == "${0}" ]]; then
    set -euo pipefail
fi

# Initialize .ralph directory
init_ralph() {
    mkdir -p "$RALPH_DIR"

    if [[ ! -f "$PROGRESS_FILE" ]]; then
        cat > "$PROGRESS_FILE" <<EOF
{
  "spec_dir": "$SPEC_DIR",
  "started_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "status": "running",
  "current_task": null,
  "current_attempt": 0,
  "completed_tasks": [],
  "failed_tasks": [],
  "total_input_tokens": 0,
  "total_output_tokens": 0,
  "total_cost_usd": 0.0,
  "last_updated": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
        log "Initialized Ralph progress tracking"
    fi
}

# Log message to session log
log() {
    local msg="$1"
    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    echo "[$timestamp] $msg" >> "$SESSION_LOG"
    echo "[$timestamp] $msg"
}

# Get current status
get_status() {
    if [[ ! -f "$PROGRESS_FILE" ]]; then
        echo "Not initialized. Run: progress-tracker.sh <spec_dir> init"
        return 1
    fi
    jq . "$PROGRESS_FILE"
}

# Mark task as started
start_task() {
    local task_id="$1"
    local attempt="${2:-1}"

    jq --arg task_id "$task_id" \
       --argjson attempt "$attempt" \
       --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
       '.current_task = $task_id |
        .current_attempt = $attempt |
        .last_updated = $ts' \
       "$PROGRESS_FILE" > "$PROGRESS_FILE.tmp" && mv "$PROGRESS_FILE.tmp" "$PROGRESS_FILE"

    log "Started task $task_id (attempt $attempt)"
}

# Mark task as completed
complete_task() {
    local task_id="$1"
    local input_tokens="${2:-0}"
    local output_tokens="${3:-0}"

    # Calculate cost (Opus pricing: $15/1M input, $75/1M output)
    local cost
    cost=$(echo "scale=4; ($input_tokens * 0.000015) + ($output_tokens * 0.000075)" | bc)

    jq --arg task_id "$task_id" \
       --argjson input_tokens "$input_tokens" \
       --argjson output_tokens "$output_tokens" \
       --argjson cost "$cost" \
       --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
       '.completed_tasks += [$task_id] |
        .current_task = null |
        .current_attempt = 0 |
        .total_input_tokens += $input_tokens |
        .total_output_tokens += $output_tokens |
        .total_cost_usd += $cost |
        .last_updated = $ts' \
       "$PROGRESS_FILE" > "$PROGRESS_FILE.tmp" && mv "$PROGRESS_FILE.tmp" "$PROGRESS_FILE"

    log "Completed task $task_id (cost: \$$cost)"
}

# Mark task as failed
fail_task() {
    local task_id="$1"
    local error_msg="${2:-unknown error}"

    jq --arg task_id "$task_id" \
       --arg error "$error_msg" \
       --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
       '.failed_tasks += [{id: $task_id, error: $error, timestamp: $ts}] |
        .last_updated = $ts' \
       "$PROGRESS_FILE" > "$PROGRESS_FILE.tmp" && mv "$PROGRESS_FILE.tmp" "$PROGRESS_FILE"

    log "Failed task $task_id: $error_msg"
}

# Mark loop as blocked (needs human intervention)
block_loop() {
    local reason="${1:-unknown}"

    jq --arg reason "$reason" \
       --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
       '.status = "blocked" |
        .blocked_reason = $reason |
        .blocked_at = $ts |
        .last_updated = $ts' \
       "$PROGRESS_FILE" > "$PROGRESS_FILE.tmp" && mv "$PROGRESS_FILE.tmp" "$PROGRESS_FILE"

    log "BLOCKED: $reason"
}

# Mark loop as completed
complete_loop() {
    jq --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
       '.status = "completed" |
        .completed_at = $ts |
        .last_updated = $ts' \
       "$PROGRESS_FILE" > "$PROGRESS_FILE.tmp" && mv "$PROGRESS_FILE.tmp" "$PROGRESS_FILE"

    log "Ralph loop completed!"
}

# Resume from blocked state
resume() {
    jq --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
       '.status = "running" |
        .blocked_reason = null |
        .blocked_at = null |
        .last_updated = $ts' \
       "$PROGRESS_FILE" > "$PROGRESS_FILE.tmp" && mv "$PROGRESS_FILE.tmp" "$PROGRESS_FILE"

    log "Resumed Ralph loop"
}

# Check if task is already completed
is_completed() {
    local task_id="$1"
    jq -e --arg task_id "$task_id" '.completed_tasks | index($task_id) != null' "$PROGRESS_FILE" > /dev/null
}

# ─────────────────────────────────────────────────────────────────────────────
# BATCH EXECUTION FUNCTIONS (for parallel task execution)
# ─────────────────────────────────────────────────────────────────────────────

# Start a batch of parallel tasks
start_batch() {
    local task_ids_json="$1"  # JSON array of task IDs, e.g., '["T085","T086"]'

    # Build batch_status object with all tasks as "pending"
    local batch_status
    batch_status=$(echo "$task_ids_json" | jq 'reduce .[] as $id ({}; .[$id] = "pending")')

    jq --argjson task_ids "$task_ids_json" \
       --argjson batch_status "$batch_status" \
       --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
       '.current_batch = $task_ids |
        .batch_started_at = $ts |
        .batch_status = $batch_status |
        .last_updated = $ts' \
       "$PROGRESS_FILE" > "$PROGRESS_FILE.tmp" && mv "$PROGRESS_FILE.tmp" "$PROGRESS_FILE"

    local task_count
    task_count=$(echo "$task_ids_json" | jq 'length')
    log "Started batch with $task_count tasks: $(echo "$task_ids_json" | jq -r 'join(", ")')"
}

# Update status of a single task within the batch
update_batch_status() {
    local task_id="$1"
    local status="$2"  # "pending", "running", "completed", "failed"

    jq --arg task_id "$task_id" \
       --arg status "$status" \
       --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
       '.batch_status[$task_id] = $status |
        .last_updated = $ts' \
       "$PROGRESS_FILE" > "$PROGRESS_FILE.tmp" && mv "$PROGRESS_FILE.tmp" "$PROGRESS_FILE"

    log "Batch task $task_id: $status"
}

# Complete the batch - move all batch tasks to completed_tasks
complete_batch() {
    local input_tokens="${1:-0}"
    local output_tokens="${2:-0}"

    # Calculate cost (Opus pricing: $15/1M input, $75/1M output)
    local cost
    cost=$(echo "scale=4; ($input_tokens * 0.000015) + ($output_tokens * 0.000075)" | bc)

    # Get batch tasks and add to completed_tasks, clear batch fields
    jq --argjson input_tokens "$input_tokens" \
       --argjson output_tokens "$output_tokens" \
       --argjson cost "$cost" \
       --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
       '.completed_tasks += .current_batch |
        .current_batch = [] |
        .batch_started_at = null |
        .batch_status = {} |
        .current_task = null |
        .current_attempt = 0 |
        .total_input_tokens += $input_tokens |
        .total_output_tokens += $output_tokens |
        .total_cost_usd += $cost |
        .last_updated = $ts' \
       "$PROGRESS_FILE" > "$PROGRESS_FILE.tmp" && mv "$PROGRESS_FILE.tmp" "$PROGRESS_FILE"

    log "Batch completed (cost: \$$cost)"
}

# Get current batch info
get_batch_status() {
    if [[ ! -f "$PROGRESS_FILE" ]]; then
        echo "{}"
        return
    fi
    jq '{
        current_batch: .current_batch,
        batch_started_at: .batch_started_at,
        batch_status: .batch_status
    }' "$PROGRESS_FILE"
}

# Get summary stats
get_summary() {
    if [[ ! -f "$PROGRESS_FILE" ]]; then
        echo "Not initialized"
        return 1
    fi

    jq -r '
        "Status: \(.status)" +
        "\nCompleted: \(.completed_tasks | length) tasks" +
        "\nFailed: \(.failed_tasks | length) tasks" +
        "\nTokens: \(.total_input_tokens) in / \(.total_output_tokens) out" +
        "\nCost: $\(.total_cost_usd | . * 100 | round / 100)"
    ' "$PROGRESS_FILE"
}

# Main dispatch - only run when executed directly
if [[ "${BASH_SOURCE[0]:-$0}" == "${0}" ]]; then
    SPEC_DIR="${1:-}"
    COMMAND="${2:-status}"
    shift 2 || true

    if [[ -z "$SPEC_DIR" ]]; then
        echo "Error: spec_dir required" >&2
        exit 1
    fi

    RALPH_DIR="$SPEC_DIR/.ralph"
    PROGRESS_FILE="$RALPH_DIR/progress.json"
    SESSION_LOG="$RALPH_DIR/session.log"

    case "$COMMAND" in
        init)
            init_ralph
            ;;
        status)
            get_status
            ;;
        summary)
            get_summary
            ;;
        start)
            start_task "${1:-}" "${2:-1}"
            ;;
        complete)
            complete_task "${1:-}" "${2:-0}" "${3:-0}"
            ;;
        fail)
            fail_task "${1:-}" "${2:-}"
            ;;
        block)
            block_loop "${1:-}"
            ;;
        done)
            complete_loop
            ;;
        resume)
            resume
            ;;
        is-completed)
            is_completed "${1:-}"
            ;;
        start-batch)
            # Usage: progress-tracker.sh <spec_dir> start-batch '["T085","T086","T087"]'
            start_batch "${1:-[]}"
            ;;
        update-batch)
            # Usage: progress-tracker.sh <spec_dir> update-batch T085 completed
            update_batch_status "${1:-}" "${2:-pending}"
            ;;
        complete-batch)
            # Usage: progress-tracker.sh <spec_dir> complete-batch [input_tokens] [output_tokens]
            complete_batch "${1:-0}" "${2:-0}"
            ;;
        batch-status)
            get_batch_status
            ;;
        *)
            echo "Unknown command: $COMMAND" >&2
            echo "Commands: init, status, summary, start, complete, fail, block, done, resume, is-completed" >&2
            echo "Batch: start-batch, update-batch, complete-batch, batch-status" >&2
            exit 1
            ;;
    esac
fi
