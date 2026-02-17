#!/usr/bin/env bash
# cost-tracker.sh - Track token usage and costs
# Part of speckit-ralph

set -euo pipefail

# Cost tracking for Claude API usage
# Pricing (Opus 4): $15/1M input tokens, $75/1M output tokens
# Usage: cost-tracker.sh <spec_dir> <command> [args...]

SPEC_DIR="${1:-}"
COMMAND="${2:-summary}"
shift 2 || true

if [[ -z "$SPEC_DIR" ]]; then
    echo "Error: spec_dir required" >&2
    exit 1
fi

RALPH_DIR="$SPEC_DIR/.ralph"
COSTS_FILE="$RALPH_DIR/costs.json"

# Pricing constants (per token)
INPUT_PRICE=0.000015   # $15 per 1M tokens
OUTPUT_PRICE=0.000075  # $75 per 1M tokens

# Initialize costs file
init_costs() {
    mkdir -p "$RALPH_DIR"

    if [[ ! -f "$COSTS_FILE" ]]; then
        cat > "$COSTS_FILE" <<EOF
{
  "tasks": [],
  "totals": {
    "input_tokens": 0,
    "output_tokens": 0,
    "cost_usd": 0.0
  },
  "budget": null,
  "started_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
    fi
}

# Record task cost
record_task() {
    local task_id="$1"
    local input_tokens="${2:-0}"
    local output_tokens="${3:-0}"

    # Calculate cost
    local cost
    cost=$(echo "scale=6; ($input_tokens * $INPUT_PRICE) + ($output_tokens * $OUTPUT_PRICE)" | bc)

    # Update costs.json
    jq --arg task_id "$task_id" \
       --argjson input "$input_tokens" \
       --argjson output "$output_tokens" \
       --argjson cost "$cost" \
       --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
       '.tasks += [{
         id: $task_id,
         input_tokens: $input,
         output_tokens: $output,
         cost_usd: $cost,
         timestamp: $ts
       }] |
       .totals.input_tokens += $input |
       .totals.output_tokens += $output |
       .totals.cost_usd += $cost' \
       "$COSTS_FILE" > "$COSTS_FILE.tmp" && mv "$COSTS_FILE.tmp" "$COSTS_FILE"

    echo "Task $task_id: $input_tokens in / $output_tokens out = \$$cost"
}

# Set budget limit
set_budget() {
    local budget="$1"

    jq --argjson budget "$budget" '.budget = $budget' \
       "$COSTS_FILE" > "$COSTS_FILE.tmp" && mv "$COSTS_FILE.tmp" "$COSTS_FILE"

    echo "Budget set to \$$budget"
}

# Check if within budget
check_budget() {
    local budget
    budget=$(jq -r '.budget // 0' "$COSTS_FILE")

    if [[ "$budget" == "0" ]] || [[ "$budget" == "null" ]]; then
        return 0  # No budget set
    fi

    local current
    current=$(jq -r '.totals.cost_usd' "$COSTS_FILE")

    if (( $(echo "$current >= $budget" | bc -l) )); then
        echo "EXCEEDED: \$$current >= \$$budget"
        return 1
    fi

    # Warn at 80%
    local threshold
    threshold=$(echo "$budget * 0.8" | bc -l)
    if (( $(echo "$current >= $threshold" | bc -l) )); then
        echo "WARNING: \$$current ($(echo "scale=0; $current / $budget * 100" | bc)% of \$$budget)"
        return 0
    fi

    echo "OK: \$$current of \$$budget ($(echo "scale=0; $current / $budget * 100" | bc)%)"
    return 0
}

# Get summary
get_summary() {
    if [[ ! -f "$COSTS_FILE" ]]; then
        echo "No cost data available"
        return
    fi

    jq -r '
        "=== Cost Summary ===" +
        "\nTotal Input Tokens:  \(.totals.input_tokens | . / 1000 | floor)K" +
        "\nTotal Output Tokens: \(.totals.output_tokens | . / 1000 | floor)K" +
        "\nTotal Cost:          $\(.totals.cost_usd | . * 100 | round / 100)" +
        (if .budget then "\nBudget:              $\(.budget)" else "" end) +
        "\nTasks Recorded:      \(.tasks | length)"
    ' "$COSTS_FILE"
}

# Get detailed breakdown
get_breakdown() {
    if [[ ! -f "$COSTS_FILE" ]]; then
        echo "No cost data available"
        return
    fi

    jq -r '
        "Task ID         Input      Output     Cost",
        "--------------- ---------- ---------- --------",
        (.tasks[] | "\(.id | . + "               "[0:15]) \(.input_tokens | tostring + "          "[0:10]) \(.output_tokens | tostring + "          "[0:10]) $\(.cost_usd | . * 100 | round / 100)"),
        "--------------- ---------- ---------- --------",
        "TOTAL           \(.totals.input_tokens | tostring + "          "[0:10]) \(.totals.output_tokens | tostring + "          "[0:10]) $\(.totals.cost_usd | . * 100 | round / 100)"
    ' "$COSTS_FILE"
}

# Parse Claude CLI output for token counts (heuristic)
parse_claude_output() {
    local output_file="$1"

    # Look for token usage patterns in output
    # This is a placeholder - actual parsing depends on Claude CLI output format
    local input_tokens=0
    local output_tokens=0

    # Try to extract from common patterns
    if grep -q "tokens" "$output_file" 2>/dev/null; then
        # Pattern: "Used X input tokens and Y output tokens"
        input_tokens=$(grep -oP 'Used \K\d+(?= input)' "$output_file" 2>/dev/null || echo "0")
        output_tokens=$(grep -oP 'and \K\d+(?= output)' "$output_file" 2>/dev/null || echo "0")
    fi

    # Estimate if not found (rough heuristic)
    if [[ "$input_tokens" == "0" ]]; then
        # Estimate based on output size (very rough)
        local output_chars
        output_chars=$(wc -c < "$output_file" 2>/dev/null || echo "0")
        # ~4 chars per token average
        output_tokens=$((output_chars / 4))
        # Assume input is ~2x output for code generation
        input_tokens=$((output_tokens * 2))
    fi

    echo "$input_tokens $output_tokens"
}

# Main dispatch
case "$COMMAND" in
    init)
        init_costs
        ;;
    record)
        record_task "${1:-}" "${2:-0}" "${3:-0}"
        ;;
    budget)
        set_budget "${1:-0}"
        ;;
    check)
        check_budget
        ;;
    summary)
        get_summary
        ;;
    breakdown)
        get_breakdown
        ;;
    parse)
        parse_claude_output "${1:-}"
        ;;
    *)
        echo "Unknown command: $COMMAND" >&2
        echo "Commands: init, record, budget, check, summary, breakdown, parse" >&2
        exit 1
        ;;
esac
