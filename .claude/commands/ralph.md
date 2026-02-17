---
description: Run Ralph Wiggum Loop on a spec to execute tasks autonomously
---

# /ralph - Autonomous Task Execution

## User Input

```text
$ARGUMENTS
```

## Overview

Ralph Wiggum Loop executes tasks from `tasks.md` with fresh Claude context per task and build/test verification between iterations.

## Usage

The user can invoke this command with optional arguments:

```
/ralph                    # Run on auto-detected spec
/ralph specs/001-feature/ # Run on specific spec
/ralph --dry-run          # Preview only
/ralph --resume           # Resume after fix
```

## Execution

1. **Locate spec directory**
   - If path provided in `$ARGUMENTS`, use that
   - Otherwise, look for `tasks.md` in current directory or `specs/*/tasks.md`

2. **Validate prerequisites**
   - Ensure `tasks.md` exists
   - Check for Claude CLI availability
   - Verify git repository (for commits)

3. **Execute Ralph**
   ```bash
   # Prefer project-local wrapper, then installed binary, then .specify path
   RALPH_BIN="./ralph"
   if [[ ! -x "$RALPH_BIN" ]] && command -v ralph &> /dev/null; then
       RALPH_BIN="ralph"
   elif [[ ! -x "$RALPH_BIN" ]] && [[ -x "./.specify/ralph/bin/ralph" ]]; then
       RALPH_BIN="./.specify/ralph/bin/ralph"
   fi

   # All command arguments are passed through to ralph.sh unchanged
   # Example: /ralph --resume --worktree specs/001-feature/

   # Run with arguments
   $RALPH_BIN $ARGUMENTS
   ```

4. **Monitor progress**
   - Watch `.ralph/session.log` for real-time progress
   - Check `.ralph/progress.json` for state

## Options

| Option | Description |
|--------|-------------|
| `--dry-run` | Preview tasks without executing |
| `--resume` | Resume from last state after fix |
| `--phase N` | Start from specific phase |
| `--budget N` | Stop if cost exceeds $N |
| `--ui` | Enable terminal UI |
| `--slack` | Enable Slack notifications |

## Notes

- Ralph runs EXTERNAL to Claude sessions to get fresh context per task
- Each task gets minimal, focused context from spec files
- Build/test verification happens after each task
- Auto-commits on success, blocks on failure
- Resume capability for fixing blockers

## See Also

- `/speckit.tasks` - Generate tasks.md from spec
- `/speckit.implement` - Manual task implementation (without Ralph loop)
