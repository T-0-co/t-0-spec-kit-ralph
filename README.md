# T-0 Spec-Kit Ralph Loop Extension

```text
  ____       _       _
 |  _ \ __ _| |_ __ | |__
 | |_) / _` | | '_ \| '_ \
 |  _ < (_| | | |_) | | | |
 |_| \_\__,_|_| .__/|_| |_|
              |_|  Wiggum Loop · Spec-Kit Extension by T-0
```

**Ralph Wiggum Loop** `v0.1.0` - T-0's experimental adaptation of [Geoff Huntley's Ralph Wiggum technique](https://ghuntley.com/loop/) for autonomous task execution.

Execute tasks from `tasks.md` with fresh Claude context per task and build/test verification between iterations.

> **Open-source baseline**
>
> This repository is intended as a reusable baseline. You can customize it per project with:
> - `ralph-global.md` - Workspace-global skill mappings (copied on install, customize per-project)
> - `ralph-spec.md` - Feature-specific prompts (per spec, optional and complementary to your `.claude/CLAUDE.md`)
> - Project-specific config (`.specify/ralph/config.sh`)
>
> Contributions are welcome when they are generally useful. Keep project-specific logic in your own repository.

## Table of Contents

- [Why Ralph?](#why-ralph)
- [Relationship to Spec Kit](#relationship-to-spec-kit)
- [What's Different from Original Ralph](#whats-different-from-original-ralph)
- [Requirements](#requirements)
- [Installation](#installation)
- [Usage](#usage)
- [How It Works](#how-it-works)
- [Task Format](#task-format)
- [Configuration](#configuration)
- [Claude Code Harness](#claude-code-harness)
- [Monitoring & Orchestration](#monitoring--orchestration)
- [Parallel Execution](#parallel-execution)
- [Cost Tracking](#cost-tracking)
- [State Files](#state-files)
- [Included Agents & Skills](#included-agents--skills)
- [Contributing](#contributing)
- [Credits](#credits)
- [License](#license)

## Why Ralph?

Executing long task lists manually is tedious and fragile. Ralph automates this:

- **Fresh context per task** - Avoids context compaction, keeps Claude focused
- **Build/test backpressure** - Fails fast, retries, blocks when stuck
- **Cost tracking** - Know exactly how much each run costs
- **Parallel execution** - `[P]` tasks run as subagent batches, worktrees for parallel features
- **Slack notifications** - Get notified of progress and blocks

## Relationship to Spec Kit

Ralph is designed to work with repositories using [spec kit](https://github.com/github/spec-kit) (or similar spec-driven workflows). In the typical spec kit workflow:

```
/speckit.specify → /speckit.plan → /speckit.tasks → /speckit.implement
```

Ralph serves as an **alternative to `/speckit.implement`** for autonomous execution of `tasks.md`. Instead of running tasks in a single Claude session, Ralph executes each task with fresh context, avoiding context compaction on large task lists. Each task spawns its own individual Claude Code session.

**Spec Kit is not a hard requirement:** Ralph works with any `tasks.md` following the format below. It can be adapted to other specification frameworks or can be used standalone with manually created task lists.

**Experimental:** This is T-0's adaptation of [Huntley's Ralph Wiggum technique](https://ghuntley.com/loop/), currently being evaluated against Claude Code's built-in autonomous development loops. Future improvements may include parallelization and tighter spec kit integration. We use this as a reliable daily-driver in our own projects, so we are curious if it helps anyone else.

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
| **Notifications** | None | Slack webhooks (configurable) |
| **Claude Code** | None | Orchestrator skill for in-editor control |
| **Timeout** | None | 120-min per task (configurable) |
| **State** | `IMPLEMENTATION_PLAN.md` | `progress.json`, `session.log`, `costs.json` |

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
  - **network + git clone access** - only if using `install.sh --with-spec-kit`

**Quick dependency check:**
```bash
command -v claude bash git jq >/dev/null && echo "Core deps ok"
command -v tmux bc curl timeout >/dev/null || echo "Some optional deps missing"
```

**Spec input dependency:**
- Ralph does **not** require GitHub Spec Kit tooling to be installed, but we strongly recommend it - after all spec-kit integration is the main point. If someone wants to port it to another specification framework, we are happy to feature it. We are planning to support other harnesses soon - Codex CLI is next.
- Ralph needs a valid `tasks.md` in the target spec directory (generated by any workflow, including Spec Kit).
- If you want official Spec Kit command/template bootstrap files, use `install.sh --with-spec-kit` (optional).

> **Note:** Each task has a default 120-minute timeout and number of attempts. These can be configured. Complex tasks should be broken down further. The settings might need some evaluation before starting a loop. Harder tasks or extensive frontend tests might require longer timeouts or more attempts. You will learn how to find a good balance per spec but it might need some fiddling around initially.

## Installation

```bash
# Clone the repo
git clone https://github.com/T-0-co/t-0-spec-kit-ralph.git

# Install into your project (symlink mode - recommended for development)
cd your-project
./path/to/speckit-ralph/install.sh --symlink

# Copy mode (standalone, includes orchestrator command + skill by default)
./path/to/speckit-ralph/install.sh --copy

# Copy mode without orchestrator command/skill
./path/to/speckit-ralph/install.sh --copy --no-orchestrator-skill

# Copy mode + install official Spec Kit assets from upstream
./path/to/speckit-ralph/install.sh --copy --with-spec-kit

# Pin upstream Spec Kit install to a specific ref
./path/to/speckit-ralph/install.sh --copy --with-spec-kit --spec-kit-ref v0.0.53

# Or install globally
./path/to/speckit-ralph/install.sh --global
```

## Usage

### Basic Usage

```bash
# After running spec kit commands:
# /speckit.specify → /speckit.plan → /speckit.tasks → /speckit.ralph.extension

# Run Ralph on a spec
./speckit.ralph.extension specs/001-feature/

# Preview what would run (no execution)
./speckit.ralph.extension --dry-run specs/001-feature/

# Resume after fixing a blocker
./speckit.ralph.extension --resume specs/001-feature/
```

### Advanced Options

```bash
# Start from specific phase
./speckit.ralph.extension --phase 3 specs/001-feature/

# With budget limit ($20 max)
./speckit.ralph.extension --budget 20 specs/001-feature/

# With Slack notifications
./speckit.ralph.extension --slack --slack-channel "#dev" specs/001-feature/

# With worktree isolation (parallel development)
./speckit.ralph.extension --worktree --branch feature-branch specs/001-feature/

# Verbose output for debugging
./speckit.ralph.extension --verbose specs/001-feature/
```

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
  --slack             Enable Slack notifications (requires RALPH_SLACK_WEBHOOK_URL)
  --slack-channel <c> Slack channel for notifications
  --verbose           Verbose output
  --version           Show version
  --help              Show help
```

## How It Works

```text
+--------------------------------------------------------------------------+
| PHASE 1: Spec Kit (Interactive - you're present*)                        |
+--------------------------------------------------------------------------+
| /speckit.specify  ->  spec.md                                            |
| /speckit.plan     ->  plan.md, data-model.md                             |
| /speckit.tasks    ->  tasks.md (e.g., 50 tasks in 5 phases)              |
+--------------------------------------------------------------------------+
                                   |
                                   v
+--------------------------------------------------------------------------+
| PHASE 2: Ralph Loop (Headless - you walk away)                           |
+--------------------------------------------------------------------------+
| $ ./speckit.ralph.extension specs/001-feature/                           |
|                                                                          |
| Loop runs autonomously:                                                  |
|   Task T001 -> Claude -> build/test OK -> commit                         |
|   Task T002 -> Claude -> build/test OK -> commit                         |
|   Task T003 -> Claude -> build/test FAIL -> retry -> OK -> commit        |
|   ...                                                                    |
|   Task T050 -> Claude -> build/test OK -> DONE                           |
+--------------------------------------------------------------------------+
                                   |
                                   v
+--------------------------------------------------------------------------+
| PHASE 3: Review (You come back)                                          |
+--------------------------------------------------------------------------+
| Check: .ralph/progress.json, session.log, git log                        |
| If blocked: fix issue, run ./ralph --resume                              |
| If done: PR ready, all tests passing                                     |
+--------------------------------------------------------------------------+
```

*You can also create a simple task list to have the loop create the full spec itself. Just make sure to specify some input (e.g., a GitHub issue): engineer the loop to create the full spec by following all steps of the spec kit flow including some clarification runs, and make sure it picks up the new task list when running `/speckit.ralph.extension` instead of `/speckit.implement`.

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

## Configuration

### Prompt Files (Two-Level Hierarchy)

Ralph injects context at two levels:

| File | Scope | Purpose |
|------|-------|---------|
| `.specify/ralph/ralph-global.md` | **Workspace-global** | Applies to ALL specs in this project. Contains project-wide skill mappings and mandatory patterns. |
| `.specify/specs/[feature]/ralph-spec.md` | **Spec-specific** | Applies to ONE spec/feature. Contains feature-specific patterns (e.g., specific editor libraries, APIs). |

**How it works:**
1. `ralph-global.md` is **copied** (not symlinked) during install - customize it with your project's skills
2. `ralph-spec.md` is created per-feature when you need feature-specific guidance
3. Both are injected into the Claude context when running tasks
4. Decide what you really need for a smooth loop and avoid bloat or duplication with CLAUDE.md or other context sources

> **Note:** We prefer CLAUDE.md for general guardrails regarding the agent's workspace and sandbox. Global for project-related instructions and guidance (can also retrieve secondary sources or guide research), while spec complements the spec files with best practices or fixes when encountering timeouts or failed loops. We try to avoid spec-specific guidance if possible and just serve this context empty.

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

This feature uses a visual editor library. Key patterns:
- Use dynamic import with `ssr: false`
- Import editor CSS in layout component
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
| `SLACK_ENABLED` | `false` | Enable Slack notifications |
| `SLACK_CHANNEL` | `""` | Slack channel for notifications |
| `RALPH_SLACK_WEBHOOK_URL` | `""` | Slack Incoming Webhook URL (env var) |
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

# Slack notifications
SLACK_ENABLED=false
SLACK_CHANNEL="#dev-automation"
# export RALPH_SLACK_WEBHOOK_URL="https://hooks.slack.com/services/T.../B.../xxx"
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
# Slack integration
export RALPH_SLACK_WEBHOOK_URL="https://hooks.slack.com/services/T.../B.../xxx"

# Context truncation (override config files)
export RALPH_SPEC_LINES=100  # Truncate spec to 100 lines
```

### Project Integration

After installation, Ralph adds to your `.gitignore`:

```gitignore
# Ralph Wiggum Loop state
.ralph/
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

**On permissions:** The `--dangerously-skip-permissions` flag grants Claude full tool access without confirmation prompts. For more granular control, you can use Claude Code's [settings-based permission model](https://docs.anthropic.com/en/docs/claude-code/settings) instead. Configure `allowedTools` in `.claude/settings.json` to whitelist specific tools (e.g., `Bash(npm test:*)`, `Edit`, `Read`) while keeping confirmation prompts for others. This lets you run Ralph loops with scoped permissions rather than full autonomous access. Additional CLI flags like `--model` or `--max-turns` can also be configured per your needs.

### What Claude Code Has Access To

When Ralph spawns Claude Code, the session has access to:

**From the workspace:**
- `CLAUDE.md` - Project instructions, conventions, available skills
- `.claude/skills/` - All skills in the workspace (docker servers, test runners, etc.)
- Full filesystem access to the project (as scoped in `.claude/settings.json` or other [Claude Code settings](https://docs.anthropic.com/en/docs/claude-code/settings))

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

Claude Code automatically discovers skills in `.claude/skills/`. Ralph's `ralph-global.md` can map tasks to skills. Use directives like "Must use skills for these tasks" or "Skills are not optional" to strengthen skill reliance. These can be added to CLAUDE.md as well, as Anthropic recommends for skill use enforcement:

```markdown
# ralph-global.md

| When Task Involves | YOU MUST USE THIS SKILL |
|--------------------|-------------------------|
| Starting servers   | `my-app-docker-server`  |
| Running E2E tests  | `my-app-test-runner`    |
| API testing        | `my-app-api-tester`     |
| Database changes   | `my-app-db-migration`   |
```

This ensures Ralph's Claude sessions use the same patterns as interactive Claude Code sessions.

## Monitoring & Orchestration

### Orchestrator Skill

Ralph includes a Claude Code skill for monitoring and controlling loops without leaving your editor. Located at `.claude/skills/workspace-ralph-orchestrator/`, this skill provides:

- **Manage Loops** - Execute, manage and debug one or multiple Ralph loops in your workspace
- **Live monitoring** - Real-time progress, Claude's todo list, recent actions
- **Graceful stops** - Stop after current task completes (preserves state)
- **Session inspection** - View what Claude is doing, which skills it's using
- **Health checks** - Docker container status, port availability

The skill is included in this repository and can be installed into target projects via `install.sh`. We recommend symlinking it to your workspace `.claude/skills/` home for autodiscovery in your orchestration client.

### Live Dashboard

Run `ralph-context.sh` in a separate terminal (e.g., [Warp](https://www.warp.dev/) split tab) alongside the Ralph tmux session:

**Terminal 1 - Ralph Loop (tmux):**
```bash
tmux new-session -d -s ralph-010 -c "/path/to/project"
tmux send-keys -t ralph-010 './ralph.sh start .specify/specs/010-feature/' Enter
tmux attach -t ralph-010
```

**Terminal 2 - Live Dashboard (split tab):**
```bash
.claude/skills/workspace-ralph-orchestrator/ralph-context.sh .specify/specs/010-feature/ --loop
```

The dashboard shows:
- Current task or batch progress (with per-task status icons)
- Completion percentage and timing
- Claude's internal todo list (from TodoWrite tool)
- Skills being invoked in the session
- Recent tool calls and messages
- Docker container health and port status
- Stop file status for graceful shutdown

```
  ____       _       _
 |  _ \ __ _| |_ __ | |__
 | |_) / _` | | '_ \| '_ \
 |  _ < (_| | | |_) | | | |
 |_| \_\__,_|_| .__/|_| |_|
              |_|  Wiggum Loop · Spec-Kit Extension by T-0

Version 0.1.0 - Autonomous Task Monitoring Dashboard

┌──────────────────────────────────────────────────────────────────────────────────────────────────┐
│ACTIVE TASK                                                                                       │
│ ▸ T093: Fix all failing E2E tests from T092 — fix app code or test code as appropriate, re...    │
├────────────────────────────────────────────────┬─────────────────────────────────────────────────┤
│Ralph: 001-modern-stack-refactor                │Total: 11h 32m | #3                              │
│Session: 8h 15m                                 │                                                 │
│                                                │                                                 │
│─ PROGRESS ─                                    │─ RECENT ACTIONS ─ (7c456266)                    │
│[████████████░░░░] 87/107 (81%)                 │  ## T093 Complete — All E2E Tests Green         │
│Status: running                                 │> TodoWrite ✓                                    │
│Skipped: T001, T005, T006, T009, T037           │  **475 passed, 0 failed** across all 6 pr..     │
│                                                │> Bash playwright test ✓                         │
│─ CURRENT TODOS ─                               │  All 223 tests passed (chromium). Zero fa..     │
│No active todos                                 │> Bash playwright test ✓                         │
│                                                │  Now let me run the tests again.                │
│─ TASK ─                                        │> Bash curl ✓                                    │
│T093: Fix all failing E2E tests                 │  Assets are back. Now let me verify the c..     │
│███████░░░ 18m 52s / 80m | Try 21               │> Bash docker exec ✓                             │
│██████████ idle 1479s / 1200s                   │> Bash docker restart ✓                          │
│Next: T094 Run Playwright accessibility tests...│  The assets directory is empty inside the..     │
│                                                │> Bash docker exec ✓                             │
│─ METRICS ─                                     │> Bash ls ✓                                      │
│Avg: 2m 21s/task | Success: 95% | 7 failed      │> Bash curl ✓                                    │
│ETA: ~47m 0s (20 tasks left)                    │  The edit looks clean. Let me check if th..     │
│Last completed: 7h 0m ago                       │> Read admin.ts ✓                                │
│                                                │  Let me check if my admin.ts edit was cle..     │
│─ INFRA ─                                       │  ..Wait, this test was working in the first..   │
│✗ Claude Code v2.1.33 (waiting)                 │> Read admin-moderation.spec.ts ✓                │
│Model: claude-opus-4-6                          │  The `openAdminPanel` function is failing..     │
│✓ project-v14                                   │> Bash playwright test ✓                         │
│✓ avantgarde-mailhog                            │> Bash playwright test ✓                         │
│✓ project-v13                                   │  Let me look at the specific error more c..     │
│Ports: ✓8888 ✓8889 ✓3307                        │  ..Almost all admin tests are failing now. ..   │
│                                                │▸ Claude                                         │
│─ GIT ─                                         │▸ Start T093                                     │
│115 commits | 63 files | ~10/hr                 │                                                 │
│-> 001-modern-stack-refactor                    │                                                 │
│3ff3667 Ralph: T092 of T102 -                   │                                                 │
│                                                │                                                 │
│─ SKILLS ─                                      │                                                 │
│Run: None                                       │                                                 │
└────────────────────────────────────────────────┴─────────────────────────────────────────────────┘
Updated: 07:06:15  |  Ctrl+C to exit
```

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

## Parallel Execution

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

## State Files

Ralph stores state in `.ralph/` (by default this is gitignored - check how this fits your workflow or team use):

```
specs/001-feature/.ralph/
├── progress.json    # Task completion state + summary costs
├── costs.json       # Detailed per-task cost breakdown
├── tasks.json       # Parsed tasks cache
├── session.log      # Execution log
└── .stop            # Create this file for graceful stop
```

## Included Agents & Skills

Ralph ships with a set of Claude Code [agents](https://docs.anthropic.com/en/docs/claude-code/agents) and [skills](https://docs.anthropic.com/en/docs/claude-code/skills) that extend the loop and the spec-driven workflow around it. These are installed into your project's `.claude/` directory and auto-discovered by Claude Code.

### Featured

**`long-task-coordinator`** (Agent) - Orchestrates complex multi-step tasks autonomously with dependency management and progress tracking. Particularly useful **before** running `/speckit.tasks`: inject this agent to produce better task breakdowns for complex features, or when multiple features need to be implemented within a single spec. Inside loops, it helps Claude maintain focus across task boundaries.

**`autonomous-longtask-v2`** (Skill) - Session management and verification patterns for long-running loops. Provides context preservation strategies across session boundaries, task execution patterns, and loop-closing verification. Useful when Ralph sessions span many hours and context handoff between tasks becomes critical.

Both can be experimented with per spec - inject them via `ralph-global.md` or `ralph-spec.md` to steer behavior for specific features.

### All Included

| Name | Type | Purpose |
|------|------|---------|
| `long-task-coordinator` | Agent | Autonomous multi-step task orchestration with dependency tracking |
| `code-reviewer` | Agent | Code review before commits - catches quality and security issues in loops |
| `test-runner` | Agent | Test-focused agent that runs, diagnoses, and fixes test failures |
| `autonomous-longtask-v2` | Skill | Session management, task patterns, verification for long loops |
| `skill-creator` | Skill | Create new project-specific skills (based on [Anthropic's official skill creator](https://docs.anthropic.com/en/docs/claude-code/skills)) |
| `workspace-ralph-orchestrator` | Skill | Loop control and monitoring from within Claude Code (see [Monitoring](#monitoring--orchestration)) |

**Customization:** Agents like `test-runner` and `code-reviewer` are generic starting points. For best results, create project-specific versions (e.g., `my-app-playwright-runner`) that encode your project's test commands, file patterns, and conventions. The `skill-creator` skill helps with this.

## Contributing

- Open an issue first for larger changes or behavior changes
- Keep pull requests focused and small
- Avoid project-specific paths, secrets, or local environment assumptions
- Include a short validation note (what was tested)

## Credits

Based on:
- [Geoff Huntley's Ralph Wiggum technique](https://ghuntley.com/loop/) - The original autonomous loop methodology
- [The Ralph Playbook](https://github.com/ClaytonFarr/ralph-playbook) - Comprehensive Ralph documentation
- [Anthropic: Claude Code Best Practices](https://www.anthropic.com/engineering/claude-code-best-practices)
- [Parallel AI Coding with Git Worktrees](https://docs.agentinterviews.com/blog/parallel-ai-coding-with-gitworktrees/)

## License

MIT - see [LICENSE](LICENSE)

**Support:** [GitHub Issues](https://github.com/T-0-co/t-0-spec-kit-ralph/issues) | `team@t-0.co`

---

Made with 🦭 by [T-0](https://t-0.co)
