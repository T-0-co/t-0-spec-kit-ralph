# Verification Patterns

Loop-closing is the most important principle for autonomous long tasks. Every code change must be verified.

## Table of Contents

- [Test Pyramid](#test-pyramid)
- [Loop-Closing Patterns](#loop-closing-patterns)
- [Playwright E2E Configuration](#playwright-e2e-configuration)
- [Test-Driven Development](#test-driven-development)
- [Verification Strategies](#verification-strategies)
- [Common Anti-Patterns](#common-anti-patterns)

---

## Test Pyramid

```
              /\
             /E2E\ ← Playwright (critical user flows)
            /-----\
           /  API  \ ← Integration tests (service boundaries)
          /---------\
         /   Unit    \ ← Fastest feedback (isolated logic)
        /--------------\
```

### When to Use Each Level

| Level | Purpose | Speed | Confidence |
|-------|---------|-------|------------|
| Unit | Isolated logic, pure functions | Fast | Local |
| API/Integration | Service boundaries, data flow | Medium | Cross-component |
| E2E | Critical user journeys | Slow | End-to-end |

### Recommended Distribution

- **70% Unit tests**: Fast, focused, easy to maintain
- **20% Integration tests**: Service interactions
- **10% E2E tests**: Critical paths only

---

## Loop-Closing Patterns

### Basic Loop

```
1. Write test (define expected behavior)
2. Run test (verify it fails for right reason)
3. Implement code
4. Run test (verify it passes)
5. Refactor if needed
6. Run test (verify still passes)
```

### Verification Checklist

Before marking a task complete:

- [ ] Test exists for the change
- [ ] Test was run after implementation
- [ ] Test passed
- [ ] Related tests still pass
- [ ] No regressions introduced

### Loop Types by Task

| Task Type | Verification Loop |
|-----------|-------------------|
| New feature | Unit test → Implementation → Integration test |
| Bug fix | Failing test → Fix → Regression test |
| Refactoring | Run existing tests → Refactor → Re-run tests |
| API change | Contract test → Implementation → Integration test |
| UI change | Screenshot/E2E → Implementation → Visual verify |

---

## Playwright E2E Configuration

### Recommended Configuration

```typescript
// playwright.config.ts
export default defineConfig({
  use: {
    // Capture on failure for debugging
    trace: 'retain-on-failure',
    screenshot: 'only-on-failure',
    video: 'retain-on-failure',

    // Stable selectors
    testIdAttribute: 'data-testid',
  },

  // Retry flaky tests once
  retries: process.env.CI ? 1 : 0,

  // Parallel by default
  workers: process.env.CI ? 4 : undefined,
});
```

### Serial Mode for Dependent Tests

```typescript
test.describe.configure({ mode: 'serial' });

test.describe('User flow', () => {
  test('login', async ({ page }) => { ... });
  test('navigate to profile', async ({ page }) => { ... });
  test('update settings', async ({ page }) => { ... });
});
```

### Authenticated Context Pattern

```typescript
// Create authenticated context once
async function createAuthenticatedContext(browser: Browser) {
  const context = await browser.newContext();
  const page = await context.newPage();

  // Login
  await page.goto('/login');
  await page.fill('[data-testid="email"]', 'test@example.com');
  await page.fill('[data-testid="password"]', 'password');
  await page.click('[data-testid="login-button"]');
  await page.waitForURL('/dashboard');

  // Save state
  await context.storageState({ path: '.auth/user.json' });
  return context;
}

// Reuse in tests
test.use({ storageState: '.auth/user.json' });
```

### Test Data Management

```typescript
test.beforeEach(async ({ page }) => {
  // Clean state before each test
  await purgeTestData();
});

test.afterEach(async ({ page }) => {
  // Clean up after test
  await cleanupTestData();
});
```

### Debugging Failures

```bash
# View trace
npx playwright show-trace trace.zip

# Run with headed browser
npx playwright test --headed

# Debug mode
npx playwright test --debug
```

---

## Test-Driven Development

### TDD Cycle

```
RED → GREEN → REFACTOR
 │      │        │
 │      │        └── Improve code, keep test green
 │      └── Minimal code to pass test
 └── Write failing test first
```

### TDD with Claude Code

```
"Implement [feature] using TDD.

1. Write a failing test for [specific behavior]
2. Show me the test output (should fail)
3. Implement minimal code to pass
4. Show me the test output (should pass)
5. Refactor if needed
6. Repeat for next behavior"
```

### When TDD Helps Most

- Clear input/output requirements
- Complex logic with edge cases
- Bug fixes (regression test first)
- API development

### When to Skip TDD

- Exploratory prototyping
- UI layout/styling
- One-off scripts

---

## Verification Strategies

### Visual Verification

Use Chrome extension for UI changes:

```
"Implement the new dashboard layout.
Take a screenshot after implementation.
Compare with the design mockup.
List differences and fix them."
```

### Output Verification

For data processing:

```
"Process the CSV file.
Show me the first 5 rows of output.
Verify the transformation is correct.
Handle edge cases: empty rows, special characters."
```

### API Verification

```
"Implement the /users endpoint.
Test with curl:
- GET /users (list)
- POST /users (create)
- GET /users/:id (read)
- PUT /users/:id (update)
- DELETE /users/:id (delete)
Verify each response matches spec."
```

### Integration Verification

```
"Connect the frontend to the new API.
1. Verify API call succeeds
2. Verify data displays correctly
3. Verify error handling works
4. Check loading states"
```

---

## Common Anti-Patterns

### Open Loop (No Verification)

```
❌ "Implement feature X"
   → Code written
   → No tests run
   → Bugs discovered later
```

### Assumed Success

```
❌ "The code should work because..."
   → No actual execution
   → Logic errors missed
```

### Test After Everything

```
❌ Build entire feature
   → Write all tests at end
   → Many failures to debug
   → Hard to isolate issues
```

### Ignoring Failures

```
❌ Test fails
   → "That's probably fine"
   → Move on
   → Bug ships
```

### Correct Patterns

```
✅ Write test → Run → Implement → Run → Verify

✅ Test fails → Investigate → Fix → Re-run → Confirm

✅ Incremental: Test each small change before moving on
```

---

## Verification Commands

### Quick Verification

```bash
# Run specific test
npm test -- --grep "feature name"

# Run affected tests only
npm test -- --changed

# Type check
npm run typecheck

# Lint
npm run lint
```

### Full Verification

```bash
# All tests
npm test

# With coverage
npm test -- --coverage

# E2E tests
npm run test:e2e
```

### CI Verification

```bash
# Simulate CI locally
npm run ci:check
# Usually: lint + typecheck + test + build
```

---

## Loop-Closing Prompt Templates

### For Feature Implementation

```
"Implement [feature].
After each component:
1. Write test
2. Run test (show output)
3. Fix if needed
4. Commit when green"
```

### For Bug Fix

```
"Fix bug: [description]
1. Write failing test that reproduces bug
2. Show test output (should fail)
3. Implement fix
4. Run test (should pass)
5. Run related tests (no regressions)"
```

### For Refactoring

```
"Refactor [component].
1. Run existing tests (baseline)
2. Make changes
3. Run tests after each change
4. Keep all tests green throughout"
```
