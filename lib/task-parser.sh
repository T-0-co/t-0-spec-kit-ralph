#!/usr/bin/env bash
# task-parser.sh - Parse tasks.md into JSON for Ralph iteration
# Part of speckit-ralph

# Only set strict mode when executed directly (not sourced)
if [[ "${BASH_SOURCE[0]:-$0}" == "${0}" ]]; then
    set -euo pipefail
fi

parse_tasks() {
    local tasks_file="$1"
    local SPEC_DIR
    SPEC_DIR="$(dirname "$tasks_file")"
    local current_phase=""
    local current_phase_num=0
    local phase_name=""
    local tasks_json="[]"
    local task_count=0

    while IFS= read -r line || [[ -n "$line" ]]; do
        # Match phase headers: ## Phase N: Name
        if [[ "$line" =~ ^##[[:space:]]+Phase[[:space:]]+([0-9]+):[[:space:]]*(.+)$ ]]; then
            current_phase_num="${BASH_REMATCH[1]}"
            phase_name="${BASH_REMATCH[2]}"
            current_phase="Phase ${current_phase_num}: ${phase_name}"
            continue
        fi

        # Match task lines: - [ ] T001 [P] [US1] Description or - [x] T001 ...
        if [[ "$line" =~ ^[[:space:]]*-[[:space:]]*\[([xX[:space:]])\][[:space:]]+(T[0-9]+[a-z]?)[[:space:]]+(.+)$ ]]; then
            local status="${BASH_REMATCH[1]}"
            local task_id="${BASH_REMATCH[2]}"
            local rest="${BASH_REMATCH[3]}"

            # Determine completion status
            local completed="false"
            if [[ "$status" =~ [xX] ]]; then
                completed="true"
            fi

            # Check for [P] parallel marker
            local parallel="false"
            if [[ "$rest" =~ ^\[P\][[:space:]]* ]]; then
                parallel="true"
                rest="${rest#\[P\] }"
                rest="${rest#\[P\]}"
            fi

            # Check for [US#] user story marker
            local user_story=""
            if [[ "$rest" =~ ^\[US([0-9]+)\][[:space:]]* ]]; then
                user_story="US${BASH_REMATCH[1]}"
                rest="${rest#\[US[0-9]*\] }"
                rest="${rest#\[US[0-9]*\]}"
            fi

            # Remaining text is the description
            local description="$rest"

            # Build task JSON object
            local task_json
            task_json=$(cat <<EOF
{
  "id": "$task_id",
  "phase": $current_phase_num,
  "phase_name": "$phase_name",
  "description": $(echo "$description" | jq -Rs .),
  "parallel": $parallel,
  "user_story": $(if [[ -n "$user_story" ]]; then echo "\"$user_story\""; else echo "null"; fi),
  "completed": $completed
}
EOF
)
            # Append to tasks array
            if [[ "$tasks_json" == "[]" ]]; then
                tasks_json="[$task_json]"
            else
                tasks_json="${tasks_json%]}, $task_json]"
            fi
            ((task_count++)) || true
        fi
    done < "$tasks_file"

    # Build output structure
    local output
    output=$(cat <<EOF
{
  "spec_dir": "$SPEC_DIR",
  "tasks_file": "$tasks_file",
  "total_tasks": $task_count,
  "tasks": $tasks_json
}
EOF
)
    echo "$output" | jq .
}

get_status() {
    local tasks_file="$1"
    local json
    json=$(parse_tasks "$tasks_file")

    local total completed pending
    total=$(echo "$json" | jq '.total_tasks')
    completed=$(echo "$json" | jq '[.tasks[] | select(.completed == true)] | length')
    pending=$((total - completed))

    # Get phase breakdown
    local phases
    phases=$(echo "$json" | jq -r '
        .tasks | group_by(.phase) | map({
            phase: .[0].phase,
            name: .[0].phase_name,
            total: length,
            completed: [.[] | select(.completed == true)] | length
        }) | .[] | "Phase \(.phase): \(.name) - \(.completed)/\(.total)"
    ')

    echo "=== Ralph Task Status ==="
    echo "Total: $completed/$total completed ($pending pending)"
    echo ""
    echo "By Phase:"
    echo "$phases"
    echo ""

    # Show next incomplete tasks
    local next_tasks
    next_tasks=$(echo "$json" | jq -r '
        [.tasks[] | select(.completed == false)] | .[0:5] | .[] |
        "  \(.id): \(.description | .[0:60])..."
    ')

    if [[ -n "$next_tasks" ]]; then
        echo "Next tasks:"
        echo "$next_tasks"
    fi
}

get_next_task() {
    local tasks_file="$1"
    local json
    json=$(parse_tasks "$tasks_file")

    # Find first incomplete task
    echo "$json" | jq -c '[.tasks[] | select(.completed == false)][0] // empty'
}

get_parallel_batch() {
    local tasks_file="$1"
    local json
    json=$(parse_tasks "$tasks_file")

    # Get first incomplete task and any parallel tasks in same phase
    local first_task
    first_task=$(echo "$json" | jq -c '[.tasks[] | select(.completed == false)][0] // empty')

    if [[ -z "$first_task" ]]; then
        echo "[]"
        return
    fi

    local phase
    phase=$(echo "$first_task" | jq '.phase')

    # Get all incomplete parallel tasks in same phase
    echo "$json" | jq -c "[.tasks[] | select(.completed == false and .phase == $phase and .parallel == true)]"
}

# Main dispatch - only run when executed directly
if [[ "${BASH_SOURCE[0]:-$0}" == "${0}" ]]; then
    TASKS_FILE="${1:-}"
    OUTPUT_MODE="${2:---json}"

    if [[ -z "$TASKS_FILE" ]] || [[ ! -f "$TASKS_FILE" ]]; then
        echo "Error: tasks.md file required" >&2
        echo "Usage: task-parser.sh <tasks.md> [--json|--status|--next|--parallel]" >&2
        exit 1
    fi

    case "$OUTPUT_MODE" in
        --json)
            parse_tasks "$TASKS_FILE"
            ;;
        --status)
            get_status "$TASKS_FILE"
            ;;
        --next)
            get_next_task "$TASKS_FILE"
            ;;
        --parallel)
            get_parallel_batch "$TASKS_FILE"
            ;;
        *)
            echo "Unknown mode: $OUTPUT_MODE" >&2
            echo "Usage: task-parser.sh <tasks.md> [--json|--status|--next|--parallel]" >&2
            exit 1
            ;;
    esac
fi
