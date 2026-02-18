<!--
Sync Impact Report
==================
Version change: 0.0.0 → 1.0.0 (MAJOR - initial constitution)
Modified principles: N/A (new document)
Added sections:
  - Core Principles (I-VI)
  - Compliance & Security Requirements
  - Development Workflow
  - Governance
Removed sections: N/A
Templates requiring updates:
  - .specify/templates/plan-template.md ✅ compatible (has Constitution Check section)
  - .specify/templates/spec-template.md ✅ compatible (no changes needed)
  - .specify/templates/tasks-template.md ✅ compatible (no changes needed)
Follow-up TODOs: None
-->

# ARMARD CRM Constitution

## Core Principles

### I. Compliance-First (NON-NEGOTIABLE)

All features MUST comply with German regulatory requirements:

- **GoBD**: 10-year invoice retention, immutable audit trail, no deletion of sent invoices
- **GDPR**: Data portability on request, right to rectification, archive (not delete) linked records
- **Tax Law**: DATEV export capability, proper VAT handling (19%/7% rates), sequential invoice numbering

Violations of compliance requirements are CRITICAL blockers. No feature ships without compliance verification.

### II. Self-Hosted First

The system MUST operate without external cloud dependencies:

- All services run on self-managed infrastructure (Docker Compose)
- No SaaS dependencies for core functionality (auth, storage, PDF generation)
- External integrations (future: Stripe, Shopify) are additive, never required
- Offline-capable where feasible; graceful degradation when network unavailable

### III. Type Safety End-to-End

TypeScript strict mode is mandatory across all packages:

- Shared types between frontend and backend via monorepo packages
- Zod schemas for runtime validation at system boundaries
- No `any` types without explicit justification in code comments
- API contracts defined in OpenAPI with generated types

### IV. Loop-Closing Development

Every code change MUST close a feedback loop before commit:

- Write test (or verification step) → Implement → Verify → Commit
- Atomic commits: one task = one commit, all tests passing
- No batching multiple tasks into single commits
- Each commit leaves the system in a working state
- Use `claude-progress.txt` for session handoffs if context exhausted

### V. Design Excellence (2026 Signature)

UI MUST meet modern design standards, not generic templates:

- **Dark mode first**: Black background, light text, monochrome base
- **Typography**: Rotis font family, kinetic animations on state changes
- **Spatial Glass UI**: Layered translucent panels with depth
- **Command Palette (⌘K)**: Keyboard-first power-user navigation
- **Bento Grid**: Dashboard uses asymmetric card layouts
- **Physics-based motion**: Spring animations via Framer Motion, not linear easing

Design decisions MUST reference concrete CSS values, not "vibes". Anti-pattern: generic gradients, overused shadows, "AI slop" aesthetics.

### VI. Mobile-Responsive

All features MUST work on mobile devices (375px minimum):

- Touch-friendly targets (minimum 44px)
- Responsive layouts that adapt, not just shrink
- PDF download/viewing functional on mobile browsers
- Critical workflows testable at mobile viewport in Playwright

## Compliance & Security Requirements

### Data Handling

| Requirement | Implementation | Verification |
|-------------|----------------|--------------|
| 10-year retention | AuditLog table (append-only, no DELETE) | Schema constraint + policy test |
| Audit trail | All entity changes logged with user, timestamp, before/after state | Middleware automatic logging |
| Invoice immutability | Sent invoices cannot be modified, only cancelled via credit note | Service-layer validation |
| Customer archival | Soft delete (is_archived flag) preserves invoice references | FK constraint + API validation |

### Security Baseline

- Authentication: Session-based (Better Auth), secure cookie settings
- Password storage: Bcrypt hashing (handled by auth library)
- Input validation: Zod schemas at API boundaries
- SQL injection: Parameterized queries via Drizzle ORM
- XSS: React's default escaping, no dangerouslySetInnerHTML without sanitization
- CSRF: SameSite cookies, origin validation
- Rate limiting: Applied to auth endpoints

## Development Workflow

### Git Discipline

```
feat(scope): description

Task: #XX from tasks.md
- What was implemented
- What was tested

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
```

**Commit types**: `feat`, `fix`, `test`, `refactor`, `docs`, `chore`

**Rules**:
- Never batch multiple tasks
- Never commit failing tests
- Never skip pre-commit hooks without explicit justification
- Reference task ID in every commit

### Quality Gates

Before any PR merge or milestone completion:

1. **Functionality**: All acceptance scenarios from spec.md pass
2. **Tests**: Unit >80% on business logic, E2E for critical flows
3. **Design**: Visual matches spec (dark mode, Rotis, responsive)
4. **Performance**: <200ms page load, <1s PDF generation
5. **Security**: No new vulnerabilities introduced

### Autonomous Execution

For long-running implementation tasks:

- Use Task tool with parallel sub-agents where independent
- Write `claude-progress.txt` before context exhaustion
- Commit frequently to preserve progress
- Continue until ALL tasks marked `[X]` in tasks.md

## Governance

This constitution supersedes conflicting guidance in other documents. Amendments require:

1. Explicit documentation of the change and rationale
2. Version bump following semantic versioning:
   - MAJOR: Principle removal or incompatible redefinition
   - MINOR: New principle or material expansion
   - PATCH: Clarifications, typos, non-semantic refinements
3. Sync Impact Report listing affected templates and artifacts
4. Migration plan if existing code violates new principles

All implementation work MUST verify compliance with this constitution. The Constitution Check section in plan.md gates Phase 0 research.

**Version**: 1.0.0 | **Ratified**: 2026-02-01 | **Last Amended**: 2026-02-01
