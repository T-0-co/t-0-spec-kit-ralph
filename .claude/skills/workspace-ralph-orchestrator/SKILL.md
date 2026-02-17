---
name: workspace-ralph-orchestrator
description: Orchestrate Ralph automation loops for spec-driven development. Use when starting, stopping, monitoring, or checking status of Ralph loops. Triggers on Ralph start, Ralph stop, Ralph status, spec automation, task loop, run tasks, check progress, kill Ralph, resume Ralph, or tmux session management.
---

# Workspace Ralph Orchestrator

Orchestrate Ralph automation loops via tmux sessions with full control from Claude Code.

## Quick Reference

| Command | Description |
|---------|-------------|
| `ralph start <spec_dir>` | Start Ralph loop (parallel batches enabled by default) |
| `ralph --no-parallel <spec_dir>` | Run sequentially (disable parallel batches) |
| `ralph stop` | Hard kill Ralph processes |
| `ralph stop --graceful` | Graceful stop after current task |
| `ralph status <spec_dir>` | Show current progress |
| `ralph context <spec_dir> --simple --loop` | Live dashboard (recommended) |
| `ralph --worktree <spec_dir>` | Run in isolated worktree |

## Graceful Stop (Recommended)

Stop Ralph after the current task completes, preserving state:

```bash
# Create stop file - Ralph checks this between tasks
touch <spec_dir>/.ralph/.stop

# Example:
touch specs/001-my-feature/.ralph/.stop
```

Ralph will:
1. Finish the current task
2. Update progress.json with final state
3. Log the graceful stop
4. Exit cleanly

**From Claude Code**, use this pattern:
```bash
# Graceful stop
SPEC_DIR="specs/001-my-feature"
touch "$SPEC_DIR/.ralph/.stop"
echo "Stop file created - Ralph will stop after current task"
```

### Hard Stop (Immediate)

When you need to stop immediately:

```bash
# Kill specific session
tmux kill-session -t ralph-001 2>/dev/null

# Kill all Ralph processes
pkill -f "ralph.sh"
pkill -f "timeout.*claude"

# Kill Playwright tests (if running)
pkill -f "playwright"
pkill -f "npx.*playwright"

# Nuclear option - kills ALL tmux
tmux kill-server
```

**Complete cleanup script:**
```bash
# Stop everything Ralph-related
tmux kill-session -t ralph-001 2>/dev/null
pkill -f "ralph.sh"
pkill -f "timeout.*claude"
pkill -f "playwright"
pkill -f "npx.*playwright"
```

**Important**: After hard stop, manually update progress.json to document state.

## Viewing Claude Session Context

Ralph spawns a Claude Code session for each task. Use the included helper script for a complete overview.

### Quick Context (Recommended)

```bash
# Live dashboard with auto-refresh (recommended)
.claude/skills/workspace-ralph-orchestrator/ralph-context.sh <spec_dir> --simple --loop

# Single snapshot
.claude/skills/workspace-ralph-orchestrator/ralph-context.sh <spec_dir>

# Example:
.claude/skills/workspace-ralph-orchestrator/ralph-context.sh specs/001-my-feature --simple --loop
```

This shows:
- **Progress**: Current task, completed count, status
- **Active Session**: Which Claude session is running
- **Claude's Todo List**: Subtasks Claude is tracking (from TodoWrite)
- **Skills Used**: Any skills invoked in the session
- **Recent Actions**: Last 10 tool calls and messages
- **Control**: Stop file status
- **Processes**: Running Claude processes
- **Docker Containers**: Container status and health
- **Port Health**: Whether frontend/backend are responding
- **Session Log**: Recent Ralph log entries

### Manual Inspection

If you need more detail:

```bash
# Find most recently modified session files for your current project
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
CLAUDE_PROJECT_PATH="$HOME/.claude/projects/-$(echo "$PROJECT_ROOT" | tr '/' '-' | sed 's/^-//')"
ls -lt "$CLAUDE_PROJECT_PATH"/*.jsonl | head -5

# Check which Claude processes are running
ps aux | grep claude | grep -v grep
```

### Read Session Transcript

```bash
# Get recent assistant messages (what Claude said/did)
SESSION_FILE="<path_to_session>.jsonl"
tail -50 "$SESSION_FILE" | jq -r '
  select(.type == "assistant") |
  .message.content[] |
  select(.type == "text") |
  .text' 2>/dev/null | tail -30
```

### View Claude's Todo List

Ralph's Claude often uses TodoWrite to track subtasks:

```bash
# Find the todo file for the session
SESSION_ID="<session-id>"
cat ~/.claude/todos/${SESSION_ID}-agent-${SESSION_ID}.json 2>/dev/null | jq -r '.[] |
  if .status == "completed" then "✅ \(.content)"
  elif .status == "in_progress" then "🔄 \(.content)"
  else "⬚ \(.content)"
  end'
```

### Extract Claude's Recent Actions

```bash
# Get last 20 tool calls and responses
SESSION_FILE="<path>.jsonl"
tail -100 "$SESSION_FILE" | jq -r '
  if .type == "assistant" then
    if .message.content[0].text then "CLAUDE: " + .message.content[0].text[:200]
    elif .message.content[0].type == "tool_use" then "TOOL: " + .message.content[0].name
    else empty
    end
  else empty
  end' 2>/dev/null | tail -20
```

## Starting a Single Loop

Start Ralph in a tmux session:

```bash
# Kill any existing session
tmux kill-session -t ralph 2>/dev/null

# Start new session with spec name
SPEC_NAME="010-feature"
tmux new-session -d -s "ralph-$SPEC_NAME" -c <project_root>

# Run Ralph
tmux send-keys -t "ralph-$SPEC_NAME" '<ralph_path>/ralph.sh start specs/<spec_name>/' Enter
```

Example:
```bash
tmux kill-session -t ralph-001 2>/dev/null
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
tmux new-session -d -s ralph-001 -c "$PROJECT_ROOT"
tmux send-keys -t ralph-001 './ralph start specs/001-my-feature/' Enter
```

### Auto-Open Context Viewer (Default: On)

When starting Ralph, automatically open the context viewer in a separate Warp tab for real-time monitoring. This is **enabled by default** but can be disabled.

**Complete start with context viewer:**
```bash
# Set variables
SPEC_DIR="specs/001-my-feature"
SPEC_NAME="010"
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
SKILL_PATH="$PROJECT_ROOT/.claude/skills/workspace-ralph-orchestrator"

# Start Ralph in tmux
tmux kill-session -t ralph-$SPEC_NAME 2>/dev/null
tmux new-session -d -s ralph-$SPEC_NAME -c "$PROJECT_ROOT"
tmux send-keys -t ralph-$SPEC_NAME "./ralph start $SPEC_DIR/" Enter

# Auto-open context viewer in new Warp tab (default: on)
OPEN_CONTEXT_VIEWER=${OPEN_CONTEXT_VIEWER:-true}
if [[ "$OPEN_CONTEXT_VIEWER" == "true" ]]; then
  osascript -e 'tell application "Warp" to activate' \
    -e 'delay 0.5' \
    -e 'tell application "System Events" to tell process "Warp" to keystroke "t" using command down' \
    -e 'delay 0.3' \
    -e "tell application \"System Events\" to tell process \"Warp\" to keystroke \"watch -n5 '$SKILL_PATH/ralph-context.sh' '$SPEC_DIR'\"" \
    -e 'tell application "System Events" to tell process "Warp" to key code 36'
fi
```

**To disable auto-open:**
```bash
OPEN_CONTEXT_VIEWER=false  # Set before starting Ralph
```

**Progress terminal (recommended):**
```bash
# Simple single-column layout with auto-refresh (default)
.claude/skills/workspace-ralph-orchestrator/ralph-context.sh <spec_dir> --simple --loop

# Example:
.claude/skills/workspace-ralph-orchestrator/ralph-context.sh specs/001-my-feature --simple --loop
```

**Available flags:**
| Flag | Description |
|------|-------------|
| `--loop` | Auto-refresh (default 1s; override with `RALPH_CONTEXT_REFRESH_SECS`) |
| `--simple` | Single-column layout (less visual noise) |
| `--width=N` | Force specific terminal width |

**What the context viewer shows:**
- Progress (current task, completion %)
- Claude's todo list (subtasks)
- Skills being used
- Recent tool calls
- Docker container health
- Port status (3000/3001)
- Stop file status

## Parallel Task Batches

Tasks marked with `[P]` are automatically batched and executed in parallel using Claude Code subagents:

```markdown
## Phase 5: Theming Fixes

- [ ] T085 [P] Fix light mode for IconPickerField
- [ ] T086 [P] Fix light mode for URLField
- [ ] T087 [P] Fix Section overlay colors
```

When Ralph detects consecutive `[P]` tasks:
1. Groups them into a batch (up to `MAX_PARALLEL_TASKS`, default: 5)
2. Spawns a single Claude session with batch context
3. Claude launches parallel subagents via the Task tool
4. Each subagent implements one task independently
5. After all complete, Ralph verifies build and commits

**Configuration (`ralph.config`):**
```bash
PARALLEL_ENABLED=true      # Auto-detect [P] tasks (default: true)
MAX_PARALLEL_TASKS=5       # Max tasks per batch
PARALLEL_TIMEOUT=14400     # Batch timeout (4 hours)
```

**Dashboard shows batch progress:**
- Batch section with per-task status icons (✓ completed, ~ running, ○ pending)
- Progress bar for batch completion
- Batch timing vs timeout

**Recent actions show subagents:**
- `→ T085: Fix light mode...` (purple arrow) - Subagent spawned
- `> Read` (blue) - Direct tool calls

## Parallel Features with Worktrees

Run multiple Ralph loops on different features simultaneously:

```bash
# Loop 1: Feature A (main repo, branch 010)
tmux new-session -d -s ralph-001 -c /path/to/project
tmux send-keys -t ralph-001 './ralph.sh start specs/010-feature-a/' Enter

# Loop 2: Feature B (worktree, branch 012)
tmux new-session -d -s ralph-002 -c /path/to/project
tmux send-keys -t ralph-002 './ralph.sh --worktree start specs/012-feature-b/' Enter
```

Each loop runs in isolation:
- Separate git worktree with its own branch
- Independent commits and pushes
- Separate tmux sessions (`ralph-001`, `ralph-002`)

### Worktree Options

```bash
# Auto-create worktree based on spec name
./ralph.sh --worktree start specs/012-feature/

# Specify worktree location
./ralph.sh --worktree-base ~/worktrees start specs/012-feature/

# Specify branch name
./ralph.sh --worktree --branch feature-branch start specs/012-feature/
```

## Configuration

### Global Config (`.specify/ralph/config.sh`)

```bash
# Enable worktrees for all specs
WORKTREE_ENABLED=true
WORKTREE_BASE="../worktrees"

# Context settings (0 = full, N = truncate to N lines)
RALPH_SPEC_LINES=0      # Include full spec.md
RALPH_PLAN_LINES=0      # Include full plan.md

# Retries and notifications
MAX_RETRIES=3
SLACK_ENABLED=true
```

### Per-Spec Config (`<spec_dir>/ralph.config`)

```bash
# Override branch for this spec
FEATURE_BRANCH="010-schedule-improvements"
MAX_RETRIES=5
```

### Prompt Files (Two-Level Hierarchy)

Ralph injects prompts at two levels:

| File | Scope | Purpose |
|------|-------|---------|
| `.specify/ralph/ralph-global.md` | **Workspace-global** | All specs - project-wide skill mappings |
| `<spec_dir>/ralph-spec.md` | **Spec-specific** | One feature - patterns for this spec |

**Example `ralph-global.md`:**
```markdown
# MANDATORY: Skill Usage

| When Task Involves | YOU MUST USE |
|--------------------|--------------|
| Starting servers | `Skill(skill="hf-app-docker-dev-server")` |
| Running E2E tests | `Skill(skill="hf-app-playwright-runner")` |
```

**Example `ralph-spec.md`:**
```markdown
## Feature-Specific Context

This is a frontend-only feature. Focus on:
- React components in `components/schedule/`
- Run Playwright tests after UI changes

Do NOT modify backend code.
```

## Monitoring Ralph

### Quick Status Check

```bash
# Progress JSON
cat <spec_dir>/.ralph/progress.json | jq .

# Session log
tail -20 <spec_dir>/.ralph/session.log

# Git commits from Ralph
git log --oneline -10 | grep "Ralph:"

# Built-in status command
./ralph.sh status specs/010-feature/
```

### Live tmux Output

```bash
# Read current tmux output
tmux capture-pane -t ralph-001 -p | tail -20

# Extended history (last 500 lines)
tmux capture-pane -t ralph-001 -p -S -500 | tail -100

# List all Ralph sessions
tmux list-sessions | grep ralph
```

### Monitor Claude's Background Tasks

Ralph's Claude may run commands in background. Check output files:

```bash
# List recent task outputs
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
CLAUDE_TMP_PATH="/private/tmp/claude/-$(echo "$PROJECT_ROOT" | tr '/' '-' | sed 's/^-//')/tasks"
ls -lt "$CLAUDE_TMP_PATH"/*.output | head -5

# Tail active output
tail -f "$CLAUDE_TMP_PATH"/<task_id>.output
```

## Opening View for User

Open tmux in Warp:
```bash
osascript -e 'tell application "Warp" to activate' \
  -e 'delay 0.5' \
  -e 'tell application "System Events" to tell process "Warp" to keystroke "t" using command down' \
  -e 'delay 0.3' \
  -e 'tell application "System Events" to tell process "Warp" to keystroke "tmux attach -t ralph-001"' \
  -e 'tell application "System Events" to tell process "Warp" to key code 36'
```

## Workflow: Multiple Features

1. **Start first loop on main branch:**
   ```bash
   git checkout 010-feature-branch
   tmux new-session -d -s ralph-001 -c /path/to/project
   tmux send-keys -t ralph-001 './ralph.sh start specs/010-feature/' Enter
   ```

2. **Start second loop with worktree:**
   ```bash
   tmux new-session -d -s ralph-002 -c /path/to/project
   tmux send-keys -t ralph-002 './ralph.sh --worktree start specs/012-feature/' Enter
   ```

3. **Monitor both:**
   ```bash
   # Terminal 1
   tmux attach -t ralph-001

   # Terminal 2
   tmux attach -t ralph-002
   ```

4. **When done:**
   ```bash
   # Each loop creates a PR when finished
   gh pr create --base main --head 010-feature-branch
   gh pr create --base main --head 012-feature-branch
   ```

## Troubleshooting

### Ralph Stuck / Not Progressing

1. Check if Claude is running:
   ```bash
   ps aux | grep claude | grep -v grep
   ```

2. Check session file activity:
   ```bash
   PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
   CLAUDE_PROJECT_PATH="$HOME/.claude/projects/-$(echo "$PROJECT_ROOT" | tr '/' '-' | sed 's/^-//')"
   find "$CLAUDE_PROJECT_PATH" -name "*.jsonl" -mmin -5
   ```

3. View Claude's recent actions (see "Viewing Claude Session Context" above)

4. If stuck, graceful stop and resume:
   ```bash
   touch <spec_dir>/.ralph/.stop
   # Wait for stop, then:
   ./ralph.sh --resume start <spec_dir>
   ```

### Session File Not Updating

Claude may be waiting for:
- User input (shouldn't happen with `--dangerously-skip-permissions`)
- A long-running background task
- Rate limiting

Check background task output files in `/private/tmp/claude/`.

### Docker/Server Issues

Ralph's Claude often needs running servers. If tests fail:
```bash
docker compose -f docker-compose.local.yml down
docker compose -f docker-compose.local.yml up -d --build
```

### Tmux Scrolling Issues (macOS)

If scrolling with trackpad in tmux creates escape sequences like `^[OA^[OA^[[A`:

```bash
# Enable mouse mode (allows trackpad scrolling)
tmux set -g mouse on

# Make it permanent
echo "set -g mouse on" >> ~/.tmux.conf
```

This fixes trackpad scrolling in attached tmux sessions.

## Resources

### speckit-ralph Repository
- `lib/ralph.sh` - Main orchestrator
- `lib/context-builder.sh` - Prompt assembly
- `lib/task-parser.sh` - Parse tasks.md
- `lib/progress-tracker.sh` - State management

### Project Files
- `.specify/ralph/config.sh` - Global config
- `.specify/ralph/ralph-global.md` - Workspace-global prompt (skill mappings)
- `<spec>/ralph.config` - Per-spec config
- `<spec>/ralph-spec.md` - Spec-specific prompt (feature patterns)
- `<spec>/.ralph/progress.json` - Task progress state
- `<spec>/.ralph/session.log` - Execution log
- `<spec>/.ralph/.stop` - Graceful stop trigger file

### Skill Files
- `.claude/skills/workspace-ralph-orchestrator/SKILL.md` - This documentation
- `.claude/skills/workspace-ralph-orchestrator/ralph-context.sh` - Context helper script

## Future Improvements

- [ ] **Streaming output**: Use `tee` to show Claude output in terminal while capturing
- [x] **Progress excerpts**: Auto-extract and display Claude's TodoWrite items (see `ralph-context.sh`)
- [x] **Graceful stop**: Stop file mechanism (`.ralph/.stop`)
- [x] **Container health**: Docker status and port checks in context script
- [x] **Skill tracking**: Show skills used in session
- [x] **Parallel batches**: Execute `[P]` tasks via Claude subagents
- [x] **Subagent visualization**: Dashboard shows subagent status with distinct icons
- [ ] **Webhook notifications**: POST progress updates to external services
- [ ] **Cost tracking**: Parse and accumulate token usage from Claude sessions
