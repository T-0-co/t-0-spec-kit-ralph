---
name: autonomous-longtask-v2
description: Guide for long, autonomous development tasks with Claude Code. Optimized patterns for multi-session tasks, Tasks system, sub-agents, parallelization, and loop-closing. Use for complex features (multiple files/services), multi-step workflows (5+ dependent steps), long-running tasks (>30 min), or multi-session work that spans context limits.
permissionMode: bypassPermissions
---

# Autonomous Long-Task Development

This skill optimizes Claude Code for long, autonomous development tasks—from multi-hour feature implementations to multi-session refactorings.

## Core Principles

### 1. Loop Closing (Test-Driven)

Every code change must close a feedback loop:

```
1. Write test (define expected behavior)
2. Implement code
3. Run test → loop closed
4. Refactor if needed
5. Re-run test → confidence
```

**Anti-pattern (Open Loop):**
```
"Implement feature X"
→ Code written, no verification
→ Bugs discovered later
```

**Best Practice (Closed Loop):**
```
"Implement feature X with tests.
Run tests after implementation."
→ Immediate verification
```

### 2. Incremental Progress with Checkpoints

Never attempt to "one-shot" complex features:

```
❌ Implement entire feature at once
   → Context runs out mid-implementation
   → Next session inherits chaos

✅ Small, tested increments
   → Each increment works standalone
   → Clean handoff between sessions
```

**Checkpoint patterns:**
- Use `/rewind` or `Esc Esc` for rollbacks
- Commit after each working increment
- Document state in `claude-progress.txt` for session handoffs

### 3. Context Management

Claude has 200K tokens, but:
- Subagents have isolated context windows
- Long sessions fragment context
- Use `claude-progress.txt` for session handoffs
- `/compact <focus>` for manual compaction

---

## Task System

Use `TaskCreate`/`TaskUpdate` for persistent progress tracking (replaces deprecated TodoWrite).

### Quick Start

```
1. TaskCreate: Create task with subject, description, activeForm
2. TaskUpdate: Set dependencies with addBlockedBy
3. TaskUpdate: Mark in_progress when starting
4. TaskUpdate: Mark completed when done
5. TaskList: Find next available work
```

### Task Workflow

```
pending → in_progress → completed
         ↑
    (start work)
```

Tasks persist across sessions and auto-unblock when dependencies complete.

**For detailed patterns:** See [references/task-patterns.md](references/task-patterns.md)

---

## Subagents & Parallelization

Subagents are lightweight Claude instances with isolated context. Only relevant results return to the orchestrator.

### Available Agent Types

| Agent | Purpose | Tools |
|-------|---------|-------|
| `general-purpose` | Complex multi-step tasks | All |
| `Explore` | Codebase exploration, pattern search | Glob, Grep, Read (no Edit/Write) |
| `Plan` | Implementation planning | Glob, Grep, Read (no Edit/Write) |
| `Bash` | Git operations, command execution | Bash only |

### When to Use Subagents

**DO:**
- Explore unfamiliar codebase areas
- Search patterns across many files
- Parallelize independent tasks (max 10 parallel)
- Isolate high-volume operations (tests, logs)

**DON'T:**
- Read specific known file → Use `Read` directly
- Search in 2-3 files → Use `Read` directly
- Find class definition → Use `Glob` directly

### Parallel Patterns

**Background subagents:**
```
"Implement Stripe integration parallel:

Subagent 1 (Backend): Create API endpoint
Subagent 2 (Frontend): Payment form component
Subagent 3 (Tests): Integration tests

Start all three with Task tool (run_in_background: true).
Wait for completion, then integrate."
```

**Git worktrees for true parallelism:**
```bash
git worktree add ../feature-a feature/a
git worktree add ../feature-b feature/b
# Separate Claude sessions in each worktree
```

### Custom Subagents

Create custom agents in `.claude/agents/`:
- `long-task-coordinator.md` - orchestrates multi-step work
- `test-runner.md` - runs and fixes tests
- `code-reviewer.md` - reviews before commit

---

## Session Management

### Naming Sessions

Use `/rename` to give sessions descriptive names:
```
/rename stripe-integration
```

### Resuming Work

```bash
claude --continue    # Resume most recent session
claude --resume      # Session picker
claude --from-pr 123 # Resume PR-linked session
```

### Session Picker Shortcuts

| Key | Action |
|-----|--------|
| `↑/↓` | Navigate sessions |
| `P` | Preview session |
| `R` | Rename session |
| `B` | Filter by branch |
| `/` | Search |

### Context Management

- Auto-compaction triggers at ~95% capacity
- Configure earlier: `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=50`
- Manual: `/compact Focus on API changes`
- Clear between unrelated tasks: `/clear`

**For detailed patterns:** See [references/session-management.md](references/session-management.md)

---

## Template Prompts

### Long-Running Feature Implementation

```
"Implement [FEATURE] with complete loop-closing.

Requirements:
- [Req 1]
- [Req 2]

Approach:
1. Create tasks with TaskCreate for each major step
2. Set dependencies with TaskUpdate (addBlockedBy)
3. Work through tasks: test → implement → verify

Constraints:
- Each increment must be testable
- Commit after each working step
- Update claude-progress.txt if context fills

Token-Budget: Use full 200K, do NOT stop early.
At context limit: Update claude-progress.txt for handoff.
Parallelize independent tasks with subagents."
```

### Multi-Session Refactoring

```
"Refactoring Part [N] of [TOTAL].

Previous Sessions:
- See claude-progress.txt
- Git log for prior changes

This Session Goals:
- [Goal 1]
- [Goal 2]

At session end:
- Update claude-progress.txt
- All tests must pass
- Document clear next steps

If context runs low:
- Finish cleanly (no half implementations)
- Write handoff document
- Next session continues seamlessly"
```

### Bug Investigation

```
"Investigate and fix bug: [DESCRIPTION]

Observed behavior:
- [What happens]
- [When it happens]
- [Error messages]

Investigation Steps:
1. Reproduce locally
2. Check logs
3. Identify root cause
4. Implement fix
5. Add regression test (loop closing!)
6. Verify

Document findings in claude-progress.txt if complex."
```

---

## Autonomy Levels

### High Autonomy (Default for Long Tasks)

```
"Implement feature X.
Make all implementation decisions based on best practices.
Do NOT stop due to token budget.
Create tests and docs as you work."
```

### Guided Autonomy (For Critical Decisions)

```
"Implement feature X.
Ask me BEFORE decisions about:
- Database schema changes
- External API selection
- Breaking changes

For everything else: Proceed autonomously."
```

---

## Common Failure Modes

| Problem | Solution |
|---------|----------|
| Claude stops too early | Say "Do NOT stop due to token budget" explicitly |
| Too many clarifying questions | More context upfront, set autonomy level |
| Code style mismatch | "Follow pattern in [FILE]" |
| Task too complex | Break into increments, use TaskCreate |
| Context runs out | claude-progress.txt + clean commits |
| One-shotting fails | Explicitly require incremental approach |
| Lost progress between sessions | Use Tasks system (persists), not mental tracking |

---

## Verification Patterns

### Test Pyramid

```
          /\
         /E2E\ ← Playwright (critical flows)
        /-----\
       / API   \ ← Integration tests
      /---------\
     /   Unit    \ ← Fastest feedback
    /--------------\
```

### Loop-Closing Checklist

1. Test exists for the change
2. Test ran after implementation
3. Test passed (or failure was addressed)
4. Commit includes both code and test

**For detailed patterns:** See [references/verification-patterns.md](references/verification-patterns.md)

---

## Token & Cost Considerations

- **Single agent**: ~50K-100K tokens per session
- **Parallel agents**: 3-4x higher token consumption
- **Trade-off**: Higher velocity vs. higher cost

**Recommendations:**
- Quick tasks: Single agent
- Complex/long tasks: Subagents justify cost
- Claude Max Plan for heavy-duty usage

---

## Quick Reference

```
START:
1. TaskCreate with task breakdown
2. Define autonomy level
3. Establish loop-closing pattern

DURING:
- Test each increment
- Commit after working steps
- Subagents for parallel work
- TaskUpdate status as you progress

END / HANDOFF:
- Update claude-progress.txt
- All tests green
- Clear next steps documented
- TaskUpdate: mark completed
```

---

## Sources

Based on:
- [Claude Code Best Practices](https://code.claude.com/docs/en/best-practices)
- [Common Workflows](https://code.claude.com/docs/en/common-workflows)
- [Create Custom Subagents](https://code.claude.com/docs/en/sub-agents)
- [Enabling Claude Code to Work Autonomously](https://www.anthropic.com/news/enabling-claude-code-to-work-more-autonomously)
