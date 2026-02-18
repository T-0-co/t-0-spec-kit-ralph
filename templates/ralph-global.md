# MANDATORY: Skill Usage

You MUST use skills instead of writing manual implementations. Skills are pre-built, tested patterns.

## Required Skills by Task Type

| When Task Involves | YOU MUST USE | Example |
|--------------------|--------------|---------|
| Starting/checking servers | Your server skill | `Skill(skill="your-server-skill")` |
| Testing API endpoints | Your API test skill | `Skill(skill="your-api-test-skill")` |
| Running E2E/Playwright tests | Your E2E skill | `Skill(skill="your-e2e-skill")` |
| Deploying to server | Your deployment skill | `Skill(skill="your-deployment-skill")` |
| Database migrations | Your migration skill | `Skill(skill="your-migration-skill")` |

> **CUSTOMIZE THIS FILE**: Replace the placeholder skill names above with your project's actual skills from `.claude/skills/`.

## BEFORE Running Any Tests

```typescript
// ALWAYS start servers first
Skill(skill="your-server-skill")
// Wait for servers to be ready, then run tests
```

## BEFORE Making Backend Changes

Check existing patterns in CLAUDE.md. Use skills for standard operations.

## Skill Invocation Syntax

```typescript
Skill(skill="skill-name")           // Basic invocation
Skill(skill="skill-name", args="x") // With arguments
```

## If No Skill Exists

Only write manual code if no relevant skill exists in `.claude/skills/`.

---

## Project-Specific Skills

List your project's available skills here:

```
# Example - replace with your actual skills:
# - my-app-docker-dev-server   - Start/stop Docker dev servers
# - my-app-api-test-runner     - Test API endpoints
# - my-app-playwright-runner   - Run E2E tests
# - my-app-deployment          - Deploy to production
```

Run `ls .claude/skills/` to see available skills in your project.
