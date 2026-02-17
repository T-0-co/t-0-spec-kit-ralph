# speckit-ralph

**Ralph Wiggum Loop** `v0.1.0` - T-0's experimental adaptation of [Geoff Huntley's Ralph Wiggum technique](https://ghuntley.com/loop/) for autonomous task execution.

Execute tasks from `tasks.md` with fresh Claude context per task and build/test verification between iterations.

> **⚠️ This is a TEMPLATE repository**
>
> Clone or fork this repo for each workspace/project you work on. The Ralph harness is meant to be customized per-project with:
> - `ralph-global.md` - Workspace-global skill mappings (copied on install, customize per-project)
> - `ralph-spec.md` - Feature-specific prompts (per spec)
> - Project-specific config (`.specify/ralph/config.sh`)
>
> **Do NOT push changes back to the main template.** Keep your customizations in your workspace fork.

## Relationship to Spec Kit

Ralph is designed to work with repositories using [spec kit](https://github.com/github/spec-kit) (or similar spec-driven workflows). In the typical spec kit workflow:

```
/speckit.specify → /speckit.plan → /speckit.tasks → /speckit.implement
```

Ralph serves as an **alternative to `/speckit.implement`** for autonomous execution of `tasks.md`. Instead of running tasks in a single Claude session, Ralph executes each task with fresh context, avoiding context compaction on large task lists.

**Not a hard requirement:** Ralph works with any `tasks.md` following the format below. It can be adapted to other specification frameworks or used standalone with manually created task lists.

**Experimental:** This is T-0's adaptation of [Huntley's Ralph Wiggum technique](https://ghuntley.com/loop/), currently being evaluated against Claude Code's built-in autonomous development loops. Future improvements may include parallelization and tighter spec kit integration.

```
  ____       _       _
 |  _ \ __ _| |_ __ | |__
 | |_) / _` | | '_ \| '_ \
 |  _ < (_| | | |_) | | | |
 |_| \_\__,_|_| .__/|_| |_|
              |_|  Wiggum Loop
```

## What's Different from Original Ralph

This implementation builds on [Geoff Huntley's Ralph Wiggum technique](https://ghuntley.com/loop/) with spec kit integration and production tooling.

### Original Ralph (Huntley)

The original is elegantly minimal:
```bash
while :; do cat PROMPT.md | claude ; done
```

Core files: `loop.sh`, `PROMPT_plan.md`, `PROMPT_build.md`, `AGENTS.md`, `IMPLEMENTATION_PLAN.md`

Two modes: Planning (gap analysis) → Building (implementation), with Jobs-to-Be-Done (JTBD) specifications and backpressure via tests.

### T-0 Additions

| Category | Original | speckit-ralph |
|----------|----------|---------------|
| **Task format** | `IMPLEMENTATION_PLAN.md` | Spec kit's `tasks.md` with phases, `[P]` parallel markers, `[US#]` user stories |
| **Prompts** | Single `AGENTS.md` | Two-level: `ralph-global.md` (workspace) + `ralph-spec.md` (feature) |
| **Config** | None | Hierarchical `config.sh` + per-spec `ralph.config` |
| **Parallelism** | Single loop | Subagent batches for `[P]` tasks + worktrees for features |
| **Monitoring** | Terminal output | `ralph-context.sh` live dashboard |
| **Cost tracking** | None | Token usage, budget limits (`--budget`) |
| **Control** | Kill process | Graceful stop (`.stop` file), tmux integration |
| **Notifications** | None | Slack webhooks (placeholder) |
| **Claude Code** | None | Orchestrator skill for in-editor control |
| **Timeout** | None | 120-min per task (hardcoded) |
| **State** | `IMPLEMENTATION_PLAN.md` | `progress.json`, `session.log`, `costs.json` |

## Why Ralph?

Spec kit creates great specifications, plans, and task lists. But executing 50+ tasks manually is tedious. Ralph automates this:

- **Fresh context per task** - Avoids context compaction, keeps Claude focused
- **Build/test backpressure** - Fails fast, retries, blocks when stuck
- **Cost tracking** - Know exactly how much each run costs
- **Parallel execution** - `[P]` tasks run as subagent batches, worktrees for parallel features
- **Slack notifications** - Get notified of progress and blocks

## Installation

```bash
# Clone the repo
git clone https://github.com/T-0-co/speckit-ralph.git

# Install into your project (symlink mode - recommended for development)
cd your-project
./path/to/speckit-ralph/install.sh --symlink

# Or copy mode (standalone)
./path/to/speckit-ralph/install.sh --copy

# Or install globally
./path/to/speckit-ralph/install.sh --global
```

## Usage

### Basic Usage

```bash
# After running spec kit commands:
# /speckit.specify → /speckit.plan → /speckit.tasks → tasks.md

# Run Ralph on a spec
./ralph specs/001-feature/

# Preview what would run (no execution)
./ralph --dry-run specs/001-feature/

# Resume after fixing a blocker
./ralph --resume specs/001-feature/
```

### Advanced Options

```bash
# Start from specific phase
./ralph --phase 3 specs/001-feature/

# With budget limit ($20 max)
./ralph --budget 20 specs/001-feature/

# With Slack notifications (requires T0_HUB_TOKEN)
./ralph --slack --slack-channel "#dev" specs/001-feature/

# With worktree isolation (parallel development)
./ralph --worktree --branch feature-branch specs/001-feature/

# Verbose output for debugging
./ralph --verbose specs/001-feature/
```

> **Note:** The `--ui` flag is a placeholder. Use `ralph-context.sh` for monitoring (see [Monitoring](#monitoring)).

### All Options

```
Commands:
  start               Start executing tasks (default)
  stop                Stop running Ralph processes
  status              Show current progress

Options:
  --dry-run           Preview tasks without executing
  --resume            Resume from last state
  --phase <n>         Start from specific phase
  --max-retries <n>   Max retry attempts per task (default: 3)
  --parallel          Enable parallel batch execution (default: on)
  --no-parallel       Disable parallel execution, run all tasks sequentially
  --max-concurrent <n> Max tasks per parallel batch (default: 4)
  --budget <usd>      Stop if cost exceeds budget
  --worktree          Enable worktree isolation
  --worktree-base <d> Parent directory for worktrees
  --branch <name>     Branch to use in worktree
  --slack             Enable Slack notifications (placeholder)
  --slack-channel <c> Slack channel for notifications
  --ui                Terminal UI (placeholder, use ralph-context.sh)
  --verbose           Verbose output
  --version           Show version
  --help              Show help
```

### Parallel Task Batches

Tasks marked with `[P]` are automatically batched and executed in parallel using Claude Code subagents:

```markdown
## Phase 5: Theming Fixes

- [ ] T085 [P] Fix light mode for IconPickerField
- [ ] T086 [P] Fix light mode for URLField
- [ ] T087 [P] Fix light mode for CTAArrayField
- [ ] T088 [P] Fix Section overlay colors
```

When Ralph detects consecutive `[P]` tasks:
1. Groups them into a batch (up to `MAX_PARALLEL_TASKS`)
2. Spawns a single Claude session with batch context
3. Claude launches parallel subagents via the `Task` tool
4. Each subagent implements one task independently
5. After all complete, Ralph verifies build and commits

```bash
# Control batch size
./ralph --max-concurrent 4 specs/001-feature/

# Disable parallel (sequential only)
./ralph --no-parallel specs/001-feature/
```

**Configuration:**
```bash
# In ralph.config
PARALLEL_ENABLED=true      # Auto-detect [P] tasks (default: true)
MAX_PARALLEL_TASKS=5       # Max tasks per batch (default: 5)
PARALLEL_TIMEOUT=14400     # Batch timeout in seconds (default: 4 hours)
```

### Parallel Features with Worktrees

Run multiple Ralph loops on different features simultaneously:

```bash
# Loop 1: Feature A (in main repo)
./ralph specs/010-feature-a/

# Loop 2: Feature B (in worktree - different branch)
./ralph --worktree specs/012-feature-b/

# Or specify custom paths
./ralph --worktree-base ~/worktrees --branch feature-b specs/012-feature-b/
```

Each loop runs in isolation:
- Separate git worktree with its own branch
- Independent commits and pushes
- Can run in parallel tmux sessions

## How It Works

```
┌─────────────────────────────────────────────────────────────────┐
│  PHASE 1: Spec Kit (Interactive - you're present)              │
├─────────────────────────────────────────────────────────────────┤
│  /speckit.specify  →  spec.md                                   │
│  /speckit.plan     →  plan.md, data-model.md                   │
│  /speckit.tasks    →  tasks.md (e.g., 50 tasks in 5 phases)    │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│  PHASE 2: Ralph Loop (Headless - you walk away)                │
├─────────────────────────────────────────────────────────────────┤
│  $ ./ralph specs/001-feature/                                   │
│                                                                 │
│  Loop runs autonomously:                                        │
│    Task T001 → Claude → build/test ✓ → commit                  │
│    Task T002 → Claude → build/test ✓ → commit                  │
│    Task T003 → Claude → build/test ✗ → retry → ✓ → commit      │
│    ...                                                          │
│    Task T050 → Claude → build/test ✓ → DONE                    │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│  PHASE 3: Review (You come back)                               │
├─────────────────────────────────────────────────────────────────┤
│  Check: .ralph/progress.json, session.log, git log             │
│  If blocked: fix issue, run ./ralph --resume                   │
│  If done: PR ready, all tests passing                          │
└─────────────────────────────────────────────────────────────────┘
```

## Claude Code Harness

Ralph spawns Claude Code CLI for each task with a carefully constructed context.

### Invocation

```bash
timeout 7200 claude --print --dangerously-skip-permissions -p "$prompt"
```

- **`timeout 7200`** - 120-minute timeout per task
- **`--print`** - Non-interactive mode, outputs to stdout
- **`--dangerously-skip-permissions`** - Autonomous execution without confirmation prompts

### What Claude Code Has Access To

When Ralph spawns Claude Code, the session has access to:

**From the workspace:**
- `CLAUDE.md` - Project instructions, conventions, available skills
- `.claude/skills/` - All skills in the workspace (docker servers, test runners, etc.)
- Full filesystem access to the project

**Injected by Ralph (the prompt):**
- Current task details (ID, phase, description, user story)
- `spec.md` - Feature specification
- `plan.md` - Implementation plan
- `data-model.md` - Data structures (if exists)
- `research.md` - Technical research (if exists)
- `quickstart.md` - Developer onboarding (if exists)
- `ralph-global.md` - Workspace-level instructions (skill mappings)
- `ralph-spec.md` - Feature-specific instructions
- API contracts (if task mentions API/endpoint)
- List of completed tasks in this session

### Context Building

Ralph's `context-builder.sh` assembles the prompt:

```
┌─────────────────────────────────────────┐
│  Task Execution Context                 │
├─────────────────────────────────────────┤
│  Task ID: T024                          │
│  Phase: 3 - Core Implementation         │
│  Description: Add auth middleware       │
├─────────────────────────────────────────┤
│  spec.md (full or truncated)            │
│  plan.md (full or truncated)            │
│  data-model.md                          │
│  research.md                            │
│  quickstart.md                          │
├─────────────────────────────────────────┤
│  ralph-global.md (workspace skills)     │
│  ralph-spec.md (feature-specific)       │
├─────────────────────────────────────────┤
│  Completed tasks: T001, T002, ...       │
├─────────────────────────────────────────┤
│  Execution instructions:                │
│  - Read CLAUDE.md first                 │
│  - Use skills from .claude/skills/      │
│  - Focus only on this task              │
│  - Commit after success                 │
└─────────────────────────────────────────┘
```

### Skill Availability

Claude Code automatically discovers skills in `.claude/skills/`. Ralph's `ralph-global.md` should map tasks to skills:

```markdown
# ralph-global.md

| When Task Involves | USE THIS SKILL |
|--------------------|----------------|
| Starting servers   | `hf-app-docker-dev-server` |
| Running E2E tests  | `hf-app-playwright-runner` |
| API testing        | `hf-app-api-test-runner` |
| Database changes   | `hf-app-database-migration` |
```

This ensures Ralph's Claude sessions use the same patterns as interactive Claude Code sessions.

## Task Format

Ralph parses `tasks.md` files with this format:

```markdown
## Phase 1: Setup

- [ ] T001 Create project structure
- [ ] T002 [P] Initialize backend service
- [ ] T003 [P] Initialize frontend app
- [ ] T004 [US1] Implement user auth

## Phase 2: Core Features

- [ ] T005 [P] [US1] Add login endpoint
- [ ] T006 [US1] Add session management
```

- `[P]` - Task can run in parallel with others
- `[US#]` - Associated user story
- `[x]` - Task completed (Ralph marks these automatically)

## State Files

Ralph stores state in `.ralph/` (gitignored):

```
specs/001-feature/.ralph/
├── progress.json    # Task completion state + summary costs
├── costs.json       # Detailed per-task cost breakdown
├── tasks.json       # Parsed tasks cache
├── session.log      # Execution log
└── .stop            # Create this file for graceful stop
```

## Monitoring

### Live Dashboard (Recommended)

Run `ralph-context.sh` in a separate terminal (e.g., Warp split tab) alongside the Ralph tmux session:

**Terminal 1 - Ralph Loop (tmux):**
```bash
tmux new-session -d -s ralph-010 -c "/path/to/project"
tmux send-keys -t ralph-010 './ralph.sh start .specify/specs/010-feature/' Enter
tmux attach -t ralph-010
```

**Terminal 2 - Live Dashboard (split tab):**
```bash
.claude/skills/workspace-ralph-orchestrator/ralph-context.sh .specify/specs/010-feature/ --simple --loop
```

The dashboard shows:
- Current task or batch progress (with per-task status icons)
- Completion percentage and timing
- Claude's internal todo list (from TodoWrite tool)
- Skills being invoked in the session
- Recent tool calls and messages
- Docker container health and port status
- Stop file status for graceful shutdown

### Terminal UI (Placeholder)

The `--ui` flag exists but is currently a placeholder for future built-in UI. Use `ralph-context.sh` instead.

## Cost Tracking

Ralph can track token usage and calculate costs:

```
=== Cost Summary ===
Total Input Tokens:  156K
Total Output Tokens: 28K
Total Cost:          $4.44
Budget:              $50
Tasks Recorded:      23
```

> **Note:** Cost tracking is currently inactive when running on Claude Code subscription (local runs). Future versions may fetch model-specific pricing dynamically.

## Requirements

- **Required**
  - **Claude Code CLI** - `npm install -g @anthropic-ai/claude-code`
  - **bash** - Shell runtime (`#!/usr/bin/env bash`)
  - **git** - Needed for commit/push/worktree flows
  - **jq** - JSON parsing in task/progress/context scripts
- **Optional (feature-dependent)**
  - **tmux** - Background/session control for long loops and orchestrator flows
  - **bc** - Budget/cost math helpers
  - **curl** - Slack notifier integration
  - **timeout** - Task timeout wrapper (GNU `timeout` or equivalent)

**Quick dependency check:**
```bash
command -v claude bash git jq >/dev/null && echo "Core deps ok"
command -v tmux bc curl timeout >/dev/null || echo "Some optional deps missing"
```

**Spec input dependency:**
- Ralph does **not** require GitHub Spec Kit tooling to be installed.
- Ralph needs a valid `tasks.md` in the target spec directory (generated by any workflow, including Spec Kit).

> **Note:** Each task has a 120-minute timeout (hardcoded, not yet configurable). Complex tasks should be broken down further.

## Configuration

### Prompt Files (Two-Level Hierarchy)

Ralph injects context at two levels:

| File | Scope | Purpose |
|------|-------|---------|
| `.specify/ralph/ralph-global.md` | **Workspace-global** | Applies to ALL specs in this project. Contains project-wide skill mappings and mandatory patterns. |
| `.specify/specs/[feature]/ralph-spec.md` | **Spec-specific** | Applies to ONE spec/feature. Contains feature-specific patterns (e.g., Puck editor, specific APIs). |

**How it works:**
1. `ralph-global.md` is **copied** (not symlinked) during install - customize it with your project's skills
2. `ralph-spec.md` is created per-feature when you need feature-specific guidance
3. Both are injected into the Claude context when running tasks

**Example `ralph-global.md`:**
```markdown
# MANDATORY: Skill Usage

| When Task Involves | YOU MUST USE |
|--------------------|--------------|
| Starting servers | `Skill(skill="my-app-docker-server")` |
| Running E2E tests | `Skill(skill="my-app-playwright-runner")` |
```

**Example `ralph-spec.md`:**
```markdown
## Feature-Specific Context

This feature uses Puck Editor. Key patterns:
- Use dynamic import with `ssr: false`
- Import `@puckeditor/puck/puck.css` in layout
```

### Config Files

Ralph supports hierarchical configuration:

```
.specify/
├── ralph/
│   ├── config.sh           # Global config for all specs
│   └── ralph-global.md     # Workspace-global prompt (customize this!)
└── specs/
    └── 010-feature/
        ├── ralph.config    # Per-spec config (overrides global)
        └── ralph-spec.md   # Feature-specific prompt
```

### All Configuration Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `MAX_RETRIES` | `3` | Retry attempts per task before blocking |
| `PARALLEL_ENABLED` | `true` | Auto-detect and batch `[P]` tasks |
| `MAX_PARALLEL_TASKS` | `5` | Maximum tasks per parallel batch |
| `PARALLEL_TIMEOUT` | `14400` | Batch timeout in seconds (4 hours) |
| `WORKTREE_ENABLED` | `false` | Enable git worktree isolation |
| `WORKTREE_BASE` | `""` | Parent directory for worktrees |
| `FEATURE_BRANCH` | `""` | Branch name for worktree |
| `SLACK_ENABLED` | `false` | Enable Slack notifications (placeholder) |
| `SLACK_CHANNEL` | `""` | Slack channel for notifications |
| `RALPH_SPEC_LINES` | `0` | Lines of spec.md to include (0 = full) |
| `RALPH_PLAN_LINES` | `0` | Lines of plan.md to include (0 = full) |
| `RALPH_DATA_MODEL_LINES` | `0` | Lines of data-model.md to include |
| `RALPH_RESEARCH_LINES` | `0` | Lines of research.md to include |
| `RALPH_QUICKSTART_LINES` | `0` | Lines of quickstart.md to include |

**Example `.specify/ralph/config.sh`:**

```bash
# Global Ralph configuration
WORKTREE_ENABLED=true
WORKTREE_BASE="../worktrees"
MAX_RETRIES=3

# Context truncation (0 = full content, N = truncate to N lines)
RALPH_SPEC_LINES=0           # Include full spec.md
RALPH_PLAN_LINES=0           # Include full plan.md
RALPH_DATA_MODEL_LINES=0     # Include full data-model.md
RALPH_RESEARCH_LINES=0       # Include full research.md
RALPH_QUICKSTART_LINES=0     # Include full quickstart.md

# Slack notifications (placeholder - requires T0_HUB_TOKEN)
SLACK_ENABLED=false
SLACK_CHANNEL="#dev-automation"
```

**Example `specs/010-feature/ralph.config`:**

```bash
# Override for this specific feature
FEATURE_BRANCH="010-schedule-improvements"
MAX_RETRIES=5  # More retries for complex tasks
```

**Example `specs/010-feature/ralph-spec.md`:**

```markdown
## Feature-Specific Context

This is a frontend-only feature. Focus on:
- React components in `components/schedule/`
- Use existing hooks from `hooks/use-classes.ts`
- Run Playwright tests after UI changes

Do NOT modify backend code.
```

### Environment Variables

```bash
# Slack notifications (optional, currently inactive placeholder)
export T0_HUB_TOKEN="<jwt-token>"  # For t0-mcp-hub Slack integration

# Context truncation (override config files)
export RALPH_SPEC_LINES=100  # Truncate spec to 100 lines
```

### Project Integration

After installation, Ralph adds to your `.gitignore`:

```gitignore
# Ralph Wiggum Loop state
.ralph/
```

## Claude Code Integration

Ralph includes a Claude Code skill for monitoring and controlling loops without leaving your editor.

### The Orchestrator Skill

Located at `.claude/skills/workspace-ralph-orchestrator/`, this skill provides:

- **Live monitoring** - Real-time progress, Claude's todo list, recent actions
- **Graceful stops** - Stop after current task completes (preserves state)
- **Session inspection** - View what Claude is doing, which skills it's using
- **Health checks** - Docker container status, port availability

The skill is symlinked from [t0-mcp-hub](https://github.com/T-0-co/t-0-hub) and contains comprehensive documentation for all orchestration commands.

### Live Monitoring

Use `ralph-context.sh` for a real-time dashboard:

```bash
# Live dashboard with auto-refresh (recommended)
.claude/skills/workspace-ralph-orchestrator/ralph-context.sh <spec_dir> --simple --loop

# Example:
.claude/skills/workspace-ralph-orchestrator/ralph-context.sh .specify/specs/010-feature/ --simple --loop
```

The dashboard shows:
- Current task or batch progress (per-task status)
- Completion percentage and timing
- Claude's internal todo list (from TodoWrite)
- Skills being invoked
- Recent tool calls
- Docker container health
- Stop file status

### Graceful Stop

Stop Ralph cleanly after the current task finishes:

```bash
# Create stop file - Ralph checks between tasks
touch <spec_dir>/.ralph/.stop

# Example:
touch .specify/specs/010-feature/.ralph/.stop
```

Ralph will:
1. Finish the current task
2. Update `progress.json` with final state
3. Exit cleanly

For immediate stop (use sparingly):
```bash
tmux kill-session -t ralph-010
```

### Quick Reference

| Action | Command |
|--------|---------|
| Start loop | `./ralph.sh start <spec_dir>` |
| Live dashboard | `.claude/skills/workspace-ralph-orchestrator/ralph-context.sh <spec_dir> --simple --loop` |
| Graceful stop | `touch <spec_dir>/.ralph/.stop` |
| Hard stop | `tmux kill-session -t ralph-<id>` |
| Check progress | `cat <spec_dir>/.ralph/progress.json \| jq .` |
| View session log | `tail -50 <spec_dir>/.ralph/session.log` |

## License

MIT

## Credits

Based on:
- [Geoff Huntley's Ralph Wiggum technique](https://ghuntley.com/loop/) - The original autonomous loop methodology
- [The Ralph Playbook](https://github.com/ClaytonFarr/ralph-playbook) - Comprehensive Ralph documentation
- [Anthropic: Claude Code Best Practices](https://www.anthropic.com/engineering/claude-code-best-practices)
- [Parallel AI Coding with Git Worktrees](https://docs.agentinterviews.com/blog/parallel-ai-coding-with-gitworktrees/)

---

Made with 🦭 by [T-0](https://t-0.co)
