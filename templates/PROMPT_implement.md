# Ralph Task Implementation Prompt

This template is used by Ralph to generate context for each task execution.

## Task: {{TASK_ID}}

**Phase**: {{PHASE_NUM}} - {{PHASE_NAME}}
**Description**: {{TASK_DESCRIPTION}}
{{#if USER_STORY}}
**User Story**: {{USER_STORY}}
{{/if}}

---

## Project Context

Working directory: `{{PROJECT_ROOT}}`
Spec directory: `{{SPEC_DIR}}`

### Specification Summary

```markdown
{{SPEC_SUMMARY}}
```

### Technical Plan

```markdown
{{PLAN_SUMMARY}}
```

{{#if DATA_MODEL}}
### Data Model

```markdown
{{DATA_MODEL}}
```
{{/if}}

{{#if CONTRACTS}}
### API Contracts

```yaml
{{CONTRACTS}}
```
{{/if}}

---

## Completed Tasks in This Session

{{#each COMPLETED_TASKS}}
- [x] {{this.id}}: {{this.description}}
{{/each}}

---

## Execution Instructions

1. **Focus ONLY on task {{TASK_ID}}**
   - Do not modify unrelated files
   - Do not refactor code not directly involved

2. **Follow existing patterns**
   - Check similar implementations in the codebase
   - Match code style and conventions

3. **Test your changes**
   - If tests exist, run them
   - If adding new functionality, consider adding tests

4. **Output format**
   - Clearly indicate success or failure
   - List files modified
   - Report any blockers or issues

---

## Begin Implementation

Implement task **{{TASK_ID}}** now:

> {{TASK_DESCRIPTION}}

---

## Expected Output

After completion, provide:

1. **Status**: SUCCESS or FAILURE
2. **Files Modified**: List of changed files
3. **Summary**: Brief description of what was done
4. **Issues**: Any problems encountered (if FAILURE)

Example:
```
STATUS: SUCCESS
FILES:
  - src/services/auth.ts (modified)
  - src/middleware/jwt.ts (created)
SUMMARY: Implemented JWT authentication middleware with refresh token support
```
