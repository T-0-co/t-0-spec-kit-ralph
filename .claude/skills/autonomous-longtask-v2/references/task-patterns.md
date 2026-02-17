# Task System Patterns

The Tasks system (`TaskCreate`, `TaskUpdate`, `TaskList`, `TaskGet`) replaces the deprecated `TodoWrite` tool. Tasks persist across sessions and support dependency management.

## Table of Contents

- [TaskCreate](#taskcreate)
- [TaskUpdate](#taskupdate)
- [TaskList](#tasklist)
- [TaskGet](#taskget)
- [Dependency Patterns](#dependency-patterns)
- [Multi-Agent Coordination](#multi-agent-coordination)
- [Pipeline Patterns](#pipeline-patterns)

---

## TaskCreate

Creates a new task with pending status.

### Parameters

| Parameter | Required | Description |
|-----------|----------|-------------|
| `subject` | Yes | Brief title in imperative form ("Implement X", "Fix Y") |
| `description` | Yes | Detailed description of what needs to be done |
| `activeForm` | Recommended | Present continuous form for spinner ("Implementing X") |
| `metadata` | No | Arbitrary key-value pairs for categorization |

### Examples

**Basic task:**
```
TaskCreate({
  subject: "Implement user authentication",
  description: "Add login/logout functionality with JWT tokens",
  activeForm: "Implementing authentication"
})
```

**Task with metadata:**
```
TaskCreate({
  subject: "Add API rate limiting",
  description: "Implement rate limiting middleware for /api/* endpoints",
  activeForm: "Adding rate limiting",
  metadata: {
    feature: "security",
    priority: "high",
    phase: 2
  }
})
```

### Naming Conventions

| Field | Form | Example |
|-------|------|---------|
| `subject` | Imperative | "Run tests", "Implement feature" |
| `activeForm` | Present continuous | "Running tests", "Implementing feature" |

---

## TaskUpdate

Modifies an existing task's status, dependencies, or metadata.

### Parameters

| Parameter | Description |
|-----------|-------------|
| `taskId` | Task ID to update (required) |
| `status` | New status: `pending`, `in_progress`, `completed`, `deleted` |
| `subject` | New title |
| `description` | New description |
| `activeForm` | New spinner text |
| `owner` | Agent ID claiming the task |
| `addBlockedBy` | Task IDs that must complete before this one |
| `addBlocks` | Task IDs that cannot start until this one completes |
| `metadata` | Key-value pairs to merge (set key to null to delete) |

### Status Workflow

```
pending ──────────► in_progress ──────────► completed
    │                    │
    │                    ▼
    └──────────────► deleted
```

### Examples

**Start working on a task:**
```
TaskUpdate({
  taskId: "1",
  status: "in_progress"
})
```

**Complete a task:**
```
TaskUpdate({
  taskId: "1",
  status: "completed"
})
```

**Set up dependencies:**
```
TaskUpdate({
  taskId: "3",
  addBlockedBy: ["1", "2"]
})
```

**Claim a task (multi-agent):**
```
TaskUpdate({
  taskId: "1",
  status: "in_progress",
  owner: "agent-123"
})
```

---

## TaskList

Returns all tasks with summary information.

### Output Fields

| Field | Description |
|-------|-------------|
| `id` | Task identifier |
| `subject` | Brief title |
| `status` | Current status |
| `owner` | Assigned agent (if any) |
| `blockedBy` | List of blocking task IDs |

### Finding Available Work

A task is "available" when:
1. Status is `pending`
2. No owner assigned
3. `blockedBy` list is empty

```
TaskList()
→ Find tasks where status="pending" AND owner=null AND blockedBy=[]
→ Pick lowest ID task (earlier tasks set context)
→ TaskUpdate to claim it (status="in_progress")
```

---

## TaskGet

Retrieves full details for a specific task.

### Usage

```
TaskGet({ taskId: "1" })
```

### Output

- Full `subject` and `description`
- Current `status`
- `blocks` and `blockedBy` relationships
- `metadata` key-value pairs
- `owner` assignment

### When to Use

- Before starting work (get full requirements)
- Understanding dependency relationships
- Checking acceptance criteria

---

## Dependency Patterns

### Linear Pipeline

```
Task 1: Design API ─────► Task 2: Implement ─────► Task 3: Test
```

Setup:
```
TaskCreate({ subject: "Design API", ... })           # Task 1
TaskCreate({ subject: "Implement API", ... })        # Task 2
TaskCreate({ subject: "Test API", ... })             # Task 3

TaskUpdate({ taskId: "2", addBlockedBy: ["1"] })
TaskUpdate({ taskId: "3", addBlockedBy: ["2"] })
```

When Task 1 completes, Task 2 auto-unblocks.

### Parallel with Join

```
Task 1: Backend ──────┐
                      ├──► Task 3: Integration
Task 2: Frontend ─────┘
```

Setup:
```
TaskCreate({ subject: "Build backend", ... })        # Task 1
TaskCreate({ subject: "Build frontend", ... })       # Task 2
TaskCreate({ subject: "Integrate", ... })            # Task 3

TaskUpdate({ taskId: "3", addBlockedBy: ["1", "2"] })
```

Task 3 unblocks only when BOTH Task 1 and Task 2 complete.

### Fan-Out

```
                  ┌──► Task 2: Unit tests
Task 1: Code ─────┼──► Task 3: Integration tests
                  └──► Task 4: E2E tests
```

Setup:
```
TaskCreate({ subject: "Implement feature", ... })    # Task 1
TaskCreate({ subject: "Unit tests", ... })           # Task 2
TaskCreate({ subject: "Integration tests", ... })   # Task 3
TaskCreate({ subject: "E2E tests", ... })            # Task 4

TaskUpdate({ taskId: "2", addBlockedBy: ["1"] })
TaskUpdate({ taskId: "3", addBlockedBy: ["1"] })
TaskUpdate({ taskId: "4", addBlockedBy: ["1"] })
```

---

## Multi-Agent Coordination

### Task Claiming Pattern

When multiple agents work on tasks:

```
1. Agent calls TaskList()
2. Agent finds available task (pending, no owner, not blocked)
3. Agent calls TaskUpdate({ taskId, status: "in_progress", owner: "agent-id" })
4. Agent works on task
5. Agent calls TaskUpdate({ taskId, status: "completed" })
6. Blocked tasks auto-unblock
```

### Heartbeat Pattern (Advanced)

For crash recovery:

```
1. Agent sets owner and last_heartbeat in metadata
2. Agent periodically updates last_heartbeat
3. Orchestrator checks for stale heartbeats (>5 min)
4. Stale tasks get owner cleared, status reset to pending
5. Another agent can claim the task
```

---

## Pipeline Patterns

### Spec-Driven Development

```
1. TaskCreate: "Write spec"
2. TaskCreate: "Review spec" (blockedBy: 1)
3. TaskCreate: "Implement" (blockedBy: 2)
4. TaskCreate: "Test" (blockedBy: 3)
5. TaskCreate: "Document" (blockedBy: 4)
```

### Incremental Feature Delivery

```
Phase 1 (MVP):
- Task 1: Core functionality
- Task 2: Basic tests (blockedBy: 1)
- Task 3: Deploy MVP (blockedBy: 2)

Phase 2 (Enhancement):
- Task 4: Advanced features (blockedBy: 3)
- Task 5: Comprehensive tests (blockedBy: 4)
- Task 6: Production deploy (blockedBy: 5)
```

### Bug Fix Pipeline

```
1. TaskCreate: "Reproduce bug"
2. TaskCreate: "Write failing test" (blockedBy: 1)
3. TaskCreate: "Implement fix" (blockedBy: 2)
4. TaskCreate: "Verify fix" (blockedBy: 3)
5. TaskCreate: "Add regression test" (blockedBy: 4)
```

---

## Storage

Tasks are stored in `~/.claude/tasks/{sessionId}/*.json`.

- Tasks persist within a session
- Use `claude --resume` to continue with existing tasks
- Tasks from different sessions are isolated
