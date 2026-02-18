#!/usr/bin/env bash
# context-builder.sh - Build context for Claude per task
# Part of speckit-ralph

# Only set strict mode when executed directly
if [[ "${BASH_SOURCE[0]:-$0}" == "${0}" ]]; then
    set -euo pipefail
fi

# Configuration defaults (can be overridden by config file or env)
SPEC_LINES="${RALPH_SPEC_LINES:-0}"        # 0 = full, otherwise truncate
PLAN_LINES="${RALPH_PLAN_LINES:-0}"        # 0 = full, otherwise truncate
DATA_MODEL_LINES="${RALPH_DATA_MODEL_LINES:-0}"  # 0 = full

# Load config from spec directory if exists
load_spec_config() {
    local spec_dir="$1"

    # Check for ralph config in spec directory
    if [[ -f "$spec_dir/ralph.config" ]]; then
        source "$spec_dir/ralph.config"
    fi

    # Check for global ralph config
    local global_config
    if [[ -f "$spec_dir/../ralph.config" ]]; then
        source "$spec_dir/../ralph.config"
    fi
}

# Include file content (full or truncated based on config)
include_file_content() {
    local file="$1"
    local max_lines="${2:-0}"

    if [[ ! -f "$file" ]]; then
        echo "(File not found)"
        return
    fi

    if [[ "$max_lines" -eq 0 ]]; then
        # Full content
        cat "$file"
    else
        # Truncated
        head -"$max_lines" "$file"
        echo "..."
        echo "(truncated to $max_lines lines)"
    fi
}

# Build context prompt
build_context() {
    cat <<EOF
# Task Execution Context

## Current Task
- **ID**: $TASK_ID
- **Phase**: $TASK_PHASE - $TASK_PHASE_NAME
$(if [[ -n "$TASK_US" ]]; then echo "- **User Story**: $TASK_US"; fi)
- **Description**: $TASK_DESC

## Project Structure
Working in: \`$PROJECT_ROOT\`
Spec directory: \`$SPEC_DIR\`

EOF

    # Include spec files (full by default, configurable via RALPH_*_LINES)
    if [[ -f "$SPEC_DIR/spec.md" ]]; then
        cat <<EOF

## Feature Specification
\`\`\`markdown
$(include_file_content "$SPEC_DIR/spec.md" "$SPEC_LINES")
\`\`\`

EOF
    fi

    if [[ -f "$SPEC_DIR/plan.md" ]]; then
        cat <<EOF

## Implementation Plan
\`\`\`markdown
$(include_file_content "$SPEC_DIR/plan.md" "$PLAN_LINES")
\`\`\`

EOF
    fi

    if [[ -f "$SPEC_DIR/data-model.md" ]]; then
        cat <<EOF

## Data Model
\`\`\`markdown
$(include_file_content "$SPEC_DIR/data-model.md" "$DATA_MODEL_LINES")
\`\`\`

EOF
    fi

    # Include research if exists (patterns, prior art, technical context)
    if [[ -f "$SPEC_DIR/research.md" ]]; then
        cat <<EOF

## Research & Patterns
\`\`\`markdown
$(include_file_content "$SPEC_DIR/research.md" "${RALPH_RESEARCH_LINES:-0}")
\`\`\`

EOF
    fi

    # Include quickstart if exists (developer onboarding, setup steps)
    if [[ -f "$SPEC_DIR/quickstart.md" ]]; then
        cat <<EOF

## Quickstart Guide
\`\`\`markdown
$(include_file_content "$SPEC_DIR/quickstart.md" "${RALPH_QUICKSTART_LINES:-0}")
\`\`\`

EOF
    fi

    # Load global ralph prompt (applies to all specs)
    if [[ -f "$PROJECT_ROOT/.specify/ralph/ralph-global.md" ]]; then
        cat <<EOF

## Global Context
$(cat "$PROJECT_ROOT/.specify/ralph/ralph-global.md")

EOF
    fi

    # Include custom prompt if exists (per-spec customization, can override/extend global)
    if [[ -f "$SPEC_DIR/ralph-spec.md" ]]; then
        cat <<EOF

## Additional Context
$(cat "$SPEC_DIR/ralph-spec.md")

EOF
    fi

    # Include relevant contracts if task mentions API/endpoint
    if [[ -d "$SPEC_DIR/contracts" ]] && echo "$TASK_DESC" | grep -qiE "(api|endpoint|route|tool|mcp)"; then
        cat <<EOF

## API Contracts
\`\`\`yaml
$(cat "$SPEC_DIR/contracts/"*.yaml 2>/dev/null | head -100 || echo "No contracts found")
\`\`\`

EOF
    fi

    # Include progress context
    if [[ -f "$SPEC_DIR/.ralph/progress.json" ]]; then
        local completed
        completed=$(jq -r '.completed_tasks | join(", ")' "$SPEC_DIR/.ralph/progress.json" 2>/dev/null || echo "none")
        cat <<EOF

## Completed Tasks
$completed

EOF
    fi

    # Execution instructions
    cat <<EOF

## Project Context

**IMPORTANT**: Read \`CLAUDE.md\` first for project-specific instructions, conventions, and available skills.

Available skills are in \`.claude/skills/\` - use them when relevant.
Check \`.claude/skills/\` for project-specific skills (e.g., docker servers, test runners, API testers).

## Execution Instructions

1. **Read CLAUDE.md** for project context and conventions
2. **Focus ONLY on task $TASK_ID**: $TASK_DESC
3. **Use available skills** from \`.claude/skills/\` when needed
4. **Follow existing code patterns** in the project
5. **Test your changes** - ensure servers are running first if needed
6. **Do NOT commit** — the orchestrator handles commits

### Important
- If you need clarification, state what's unclear
- If the task seems impossible, explain why
- If task requires running servers, start them first (see docker-dev-server skill)
- Output a clear success/failure status at the end

## Begin Implementation

Implement task $TASK_ID now:
> $TASK_DESC

EOF
}

# Build batch context for parallel task execution via subagents
build_batch_context() {
    local batch_json="$1"  # JSON array of tasks
    local batch_count
    batch_count=$(echo "$batch_json" | jq 'length')

    # Get phase info from first task
    local phase_num phase_name
    phase_num=$(echo "$batch_json" | jq -r '.[0].phase')
    phase_name=$(echo "$batch_json" | jq -r '.[0].phase_name')

    cat <<EOF
# Parallel Task Batch Execution

## Batch Overview
- **Phase**: $phase_num - $phase_name
- **Task Count**: $batch_count tasks
- **Mode**: Parallel execution via subagents

## Project Structure
Working in: \`$PROJECT_ROOT\`
Spec directory: \`$SPEC_DIR\`

## Tasks to Execute

EOF

    # List each task
    local idx=1
    echo "$batch_json" | jq -c '.[]' | while read -r task; do
        local task_id task_desc
        task_id=$(echo "$task" | jq -r '.id')
        task_desc=$(echo "$task" | jq -r '.description')
        echo "$idx. **$task_id**: $task_desc"
        ((idx++))
    done

    # Include spec files (abbreviated for batch mode)
    if [[ -f "$SPEC_DIR/spec.md" ]]; then
        cat <<EOF

## Feature Specification
\`\`\`markdown
$(include_file_content "$SPEC_DIR/spec.md" "${RALPH_BATCH_SPEC_LINES:-100}")
\`\`\`

EOF
    fi

    if [[ -f "$SPEC_DIR/plan.md" ]]; then
        cat <<EOF

## Implementation Plan
\`\`\`markdown
$(include_file_content "$SPEC_DIR/plan.md" "${RALPH_BATCH_PLAN_LINES:-100}")
\`\`\`

EOF
    fi

    # Include quickstart if exists
    if [[ -f "$SPEC_DIR/quickstart.md" ]]; then
        cat <<EOF

## Quickstart Guide
\`\`\`markdown
$(include_file_content "$SPEC_DIR/quickstart.md" "${RALPH_QUICKSTART_LINES:-0}")
\`\`\`

EOF
    fi

    # Load global ralph prompt
    if [[ -f "$PROJECT_ROOT/.specify/ralph/ralph-global.md" ]]; then
        cat <<EOF

## Global Context
$(cat "$PROJECT_ROOT/.specify/ralph/ralph-global.md")

EOF
    fi

    # Include progress context
    if [[ -f "$SPEC_DIR/.ralph/progress.json" ]]; then
        local completed
        completed=$(jq -r '.completed_tasks | join(", ")' "$SPEC_DIR/.ralph/progress.json" 2>/dev/null || echo "none")
        cat <<EOF

## Completed Tasks
$completed

EOF
    fi

    cat <<EOF

## Execution Instructions

**CRITICAL**: Execute ALL $batch_count tasks IN PARALLEL using the Task tool.

### How to Execute

1. **Launch ALL tasks as parallel subagents in a SINGLE message**:
   - Use the \`Task\` tool with \`subagent_type: "general-purpose"\` for each task
   - Send ALL Task tool calls in ONE response (this enables parallel execution)
   - Each subagent will work independently on its assigned task

2. **Subagent prompt pattern** - for each task, use this format:
   \`\`\`
   Task tool call:
     description: "<task_id>: <short summary>"
     subagent_type: "general-purpose"
     prompt: |
       Implement task <task_id>: <full description>

       Context:
       - Project: $PROJECT_ROOT
       - Spec: $SPEC_DIR
       - Read CLAUDE.md for project conventions

       Requirements:
       - Focus ONLY on this specific task
       - Follow existing code patterns
       - Test changes if possible
       - Report success/failure clearly
   \`\`\`

3. **After all subagents complete**:
   - Report which tasks succeeded and which failed
   - Summarize any issues encountered

### Expected Tool Calls

You should make a SINGLE response with $batch_count Task tool calls:

EOF

    # Generate expected pattern
    echo "$batch_json" | jq -c '.[]' | while read -r task; do
        local task_id task_desc
        task_id=$(echo "$task" | jq -r '.id')
        task_desc=$(echo "$task" | jq -r '.description' | head -c 40)
        echo "- Task: description=\"$task_id: $task_desc\", subagent_type=\"general-purpose\""
    done

    cat <<EOF

### Success Criteria

- All $batch_count tasks implemented correctly
- No breaking changes introduced
- Clear report of results for each task

## Begin Parallel Execution

Launch $batch_count subagents NOW to implement these tasks in parallel.

EOF
}

# Main dispatch - only run when executed directly
if [[ "${BASH_SOURCE[0]:-$0}" == "${0}" ]]; then
    SPEC_DIR="${1:-}"
    MODE="${2:-single}"  # "single" or "--batch"
    TASK_JSON="${3:-}"

    # Handle legacy two-arg format: context-builder.sh <spec_dir> '<task_json>'
    if [[ "$MODE" != "--batch" ]] && [[ -z "$TASK_JSON" ]]; then
        TASK_JSON="$MODE"
        MODE="single"
    fi

    if [[ -z "$SPEC_DIR" ]]; then
        echo "Error: spec_dir required" >&2
        echo "Usage: context-builder.sh <spec_dir> '<task_json>'" >&2
        echo "       context-builder.sh <spec_dir> --batch '<batch_json>'" >&2
        exit 1
    fi

    # Load configuration from spec directory
    load_spec_config "$SPEC_DIR"

    # Find project root
    # Structure: PROJECT_ROOT/.specify/specs/SPEC_NAME/
    # Need to go up 3 levels from spec dir to reach project root
    PROJECT_ROOT="$SPEC_DIR"
    _parent_dir="$(dirname "$SPEC_DIR")"
    if [[ "$(basename "$_parent_dir")" == "specs" ]]; then
        _specify_dir="$(dirname "$_parent_dir")"
        if [[ "$(basename "$_specify_dir")" == ".specify" ]]; then
            # Standard structure: go up 3 levels
            PROJECT_ROOT="$(dirname "$_specify_dir")"
        else
            # Legacy structure without .specify: go up 2 levels
            PROJECT_ROOT="$_specify_dir"
        fi
    fi

    if [[ "$MODE" == "--batch" ]]; then
        # Batch mode: TASK_JSON contains array of tasks
        if [[ -z "$TASK_JSON" ]] || [[ "$TASK_JSON" == "[]" ]]; then
            echo "Error: batch_json required for --batch mode" >&2
            exit 1
        fi
        build_batch_context "$TASK_JSON"
    else
        # Single task mode
        if [[ -z "$TASK_JSON" ]]; then
            echo "Error: task_json required" >&2
            exit 1
        fi

        # Extract task details
        TASK_ID=$(echo "$TASK_JSON" | jq -r '.id')
        TASK_DESC=$(echo "$TASK_JSON" | jq -r '.description')
        TASK_PHASE=$(echo "$TASK_JSON" | jq -r '.phase')
        TASK_PHASE_NAME=$(echo "$TASK_JSON" | jq -r '.phase_name')
        TASK_US=$(echo "$TASK_JSON" | jq -r '.user_story // empty')

        build_context
    fi
fi
