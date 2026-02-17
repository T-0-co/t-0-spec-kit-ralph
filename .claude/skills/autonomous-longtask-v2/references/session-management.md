# Session Management Patterns

Effective session management is critical for long-running tasks that span multiple context windows or work sessions.

## Table of Contents

- [Session Naming](#session-naming)
- [Session Resumption](#session-resumption)
- [Session Picker](#session-picker)
- [Context Management](#context-management)
- [Session Handoff](#session-handoff)
- [Multi-Session Workflows](#multi-session-workflows)

---

## Session Naming

### Why Name Sessions

Named sessions are easier to find and resume. Instead of searching through "explain this function" or "fix the bug", you can directly resume "stripe-integration" or "auth-refactor".

### Using /rename

```
/rename stripe-integration
```

Name sessions when:
- Starting work on a distinct feature
- Beginning a multi-session task
- Switching to a different workstream

### Naming Conventions

| Pattern | Example | Use Case |
|---------|---------|----------|
| `feature-name` | `user-auth` | Feature development |
| `bug-issue-number` | `bug-1234` | Bug fixes |
| `refactor-area` | `refactor-api-layer` | Refactoring |
| `explore-topic` | `explore-caching` | Research/exploration |

---

## Session Resumption

### Command Line Options

```bash
# Resume most recent session in current directory
claude --continue

# Open session picker
claude --resume

# Resume specific named session
claude --resume stripe-integration

# Resume session linked to PR
claude --from-pr 123

# Fork a session (continue without modifying original)
claude --resume session-name --fork-session
```

### From Inside Claude Code

```
/resume              # Open session picker
/resume session-name # Resume specific session
```

### When to Use Each

| Command | Use Case |
|---------|----------|
| `--continue` | Quick return to recent work |
| `--resume` | Browse and select from history |
| `--resume <name>` | Known specific session |
| `--from-pr` | Continue PR-related work |

---

## Session Picker

### Opening the Picker

```bash
claude --resume
```

Or from inside Claude Code:
```
/resume
```

### Keyboard Shortcuts

| Key | Action |
|-----|--------|
| `↑` / `↓` | Navigate between sessions |
| `→` / `←` | Expand/collapse grouped sessions |
| `Enter` | Select and resume |
| `P` | Preview session content |
| `R` | Rename session |
| `/` | Search/filter sessions |
| `A` | Toggle current directory / all projects |
| `B` | Filter to current git branch |
| `Esc` | Exit picker |

### Session Display

Sessions show:
- Name or initial prompt
- Time since last activity
- Message count
- Git branch (if applicable)

Forked sessions are grouped under their root session.

---

## Context Management

### Auto-Compaction

Claude Code automatically compacts when context reaches ~95% capacity.

**What's preserved:**
- Code patterns and file states
- Key decisions made
- Recent conversation

**What's summarized:**
- Verbose tool outputs
- Exploration that didn't lead anywhere
- Repetitive content

### Configure Earlier Compaction

```bash
export CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=50
```

Set lower percentage to compact earlier, preserving more room for new context.

### Manual Compaction

```
/compact Focus on the API changes and ignore the exploration
```

Use when you want control over what gets preserved.

### When to Clear vs Continue

**Use `/clear` when:**
- Starting unrelated task
- Context is cluttered with irrelevant info
- Claude keeps making same mistakes (context pollution)
- After more than 2 corrections on same issue

**Continue session when:**
- Work is directly related to previous context
- You need Claude to remember decisions/code
- Mid-way through a multi-step task

---

## Session Handoff

### claude-progress.txt Pattern

Create/update at session boundaries:

```markdown
## Session 2026-02-02 14:30

### Completed
- UserService refactored to dependency injection
- All controller endpoints updated
- Unit tests passing (23/23)

### Current State
- Branch: refactor/user-service
- Last commit: abc123 "Refactor UserService to DI"
- Tests: All passing
- Build: Green

### Blockers
- None currently

### Next Session
1. Update frontend components for new API
2. Add integration tests
3. Update documentation

### Notes
- Used repository pattern, see UserRepository.ts
- Config moved to environment variables
```

### Initializer + Coding Agent Pattern

For very long tasks (8+ hours):

**Session 1 (Initializer):**
```
1. Create init.sh setup script
2. Create claude-progress.txt
3. Make initial git commit
4. Set up basic structure
```

**Sessions 2-N (Coding Agent):**
```
1. Read claude-progress.txt
2. Check git history for context
3. Continue incrementally
4. Update progress documentation
5. Commit working increments
```

---

## Multi-Session Workflows

### Feature Development Pattern

```
Session 1: Planning
- Explore codebase
- Design solution
- Create task breakdown
- Document in claude-progress.txt

Session 2-N: Implementation
- Read progress file
- Work through tasks
- Commit increments
- Update progress

Final Session: Polish
- Integration tests
- Documentation
- PR creation
```

### Bug Fix Pattern

```
Session 1: Investigation
- Reproduce issue
- Identify root cause
- Document findings

Session 2: Fix
- Implement solution
- Add regression test
- Verify fix
```

### Refactoring Pattern

```
Session 1: Analysis
- Map dependencies
- Plan migration order
- Create task list

Sessions 2-N: Migration
- Migrate one component at a time
- Keep tests green
- Update progress

Final Session: Cleanup
- Remove old code
- Update documentation
- Final verification
```

---

## Best Practices

### Before Ending a Session

1. Commit any working code
2. Update claude-progress.txt
3. Note any blockers or decisions
4. List concrete next steps
5. Ensure tests pass

### Starting a New Session

1. Read claude-progress.txt
2. Check git log for recent changes
3. Run tests to verify state
4. Review task list
5. Claim next task

### Session Hygiene

- Name sessions immediately when starting distinct work
- Use `/clear` between unrelated tasks
- Don't let sessions become catch-alls
- Treat sessions like git branches (one purpose)
