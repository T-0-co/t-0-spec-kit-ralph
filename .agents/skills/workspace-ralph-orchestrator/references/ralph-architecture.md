# Ralph Architecture

Ralph Wiggum Loop - Autonomous task execution with fresh Claude context per task.

## Components

### lib/ralph.sh
Main orchestrator. Loops through tasks, invokes Claude Code per task, handles retries.

### lib/task-parser.sh  
Parses `tasks.md` into JSON. Extracts task ID, phase, description, parallel flag, user story.

### lib/progress-tracker.sh
Persists state to `.ralph/progress.json`. Tracks completed/failed tasks, cost, timestamps.

### lib/context-builder.sh
Builds minimal context prompt per task. Includes spec.md, plan.md, data-model.md snippets.

### lib/build-detector.sh
Auto-detects tech stack (node/python/rust/go/docker) and sets BUILD_CMD, TEST_CMD, LINT_CMD.

## State Files

```
specs/<name>/.ralph/
├── progress.json    # Current state, completed tasks, cost
└── session.log      # Timestamped activity log
```

## Task Format (tasks.md)

```markdown
## Phase 1: Setup

- [ ] T001 [P] [US1] Task description here
- [x] T002 Another task (completed)
```

- `[P]` = Parallel execution allowed
- `[US1]` = User Story reference
- `[x]` = Completed

## Execution Flow

1. Parse tasks.md → JSON
2. Find next incomplete task
3. Build context prompt
4. Invoke Claude Code with 30min timeout
5. On success: mark complete, commit, push
6. On failure: retry up to 3x, then block
7. Repeat until all tasks done
