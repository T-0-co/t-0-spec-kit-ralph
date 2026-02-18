---
name: autonomous-longtask
permissionMode: bypassPermissions
description: Guide für lange, autonome Entwicklungsaufgaben mit Claude Code. Optimierte Patterns für Multi-Session-Tasks, Sub-Agents, Parallelisierung und Loop-Closing.
---

# Autonomous Long-Task Development

Dieses Skill optimiert Claude Code für lange, autonome Entwicklungsaufgaben - von mehrstündigen Feature-Implementierungen bis zu Multi-Session-Refactorings.

## Wann diesen Skill nutzen

- **Komplexe Features**: Implementierungen die mehrere Dateien/Services betreffen
- **Multi-Step Workflows**: Tasks mit 5+ abhängigen Schritten
- **Long-Running Tasks**: Aufgaben die >30 Min dauern
- **Multi-Session Tasks**: Arbeit die über Context-Grenzen hinausgeht

---

## Core Principles

### 1. Loop Closing (Test-Driven)

**Jede Code-Änderung muss einen Feedback-Loop schließen:**

```
1. Test schreiben (was soll passieren)
2. Code implementieren
3. Test ausführen → Loop geschlossen
4. Refactor falls nötig
5. Test erneut → Sicherheit
```

**Anti-Pattern (Open Loop):**
```
"Implementiere Feature X"
→ Code geschrieben, keine Verifikation
→ Bugs später entdeckt
```

**Best Practice (Closed Loop):**
```
"Implementiere Feature X mit E2E Test.
Führe den Test nach Implementation aus."
→ Sofortige Verifikation
```

### 2. Incremental Progress mit Checkpoints

**Niemals alles auf einmal:**

```
❌ Versuchen das komplette Feature zu "one-shotten"
   → Context läuft aus mitten in der Implementierung
   → Nächste Session erbt Chaos

✓ Kleine, getestete Inkremente
   → Jedes Inkrement funktioniert standalone
   → Klare Übergabe zwischen Sessions
```

**Checkpoint-Pattern:**
- Nutze `/rewind` oder `Esc Esc` für Rollbacks
- Committe nach jedem funktionierenden Inkrement
- Dokumentiere State in `STATUS.md` oder `claude-progress.txt`

### 3. Context-Window Management

**Claude Opus 4 kann 200K Tokens, aber:**

- Sub-Agents haben eigene Context Windows (isoliert)
- Lange Sessions fragmentieren den Context
- `claude-progress.txt` für Session-Handoffs nutzen

---

## Sub-Agents für Parallelisierung

### Was sind Sub-Agents?

Lightweight Claude-Instanzen mit eigenem Context Window. Nur relevante Ergebnisse kommen zurück zum Orchestrator.

### Verfügbare Agent-Typen

| Agent | Zweck | Tools |
|-------|-------|-------|
| `general-purpose` | Komplexe Multi-Step Tasks | Alle |
| `Explore` | Codebase-Exploration, Pattern-Search | Glob, Grep, Read, Bash |
| `Plan` | Implementation Planning | Glob, Grep, Read |

### Wann Sub-Agents nutzen

**DO:**
- Unbekannte Codebase-Teile erkunden
- Patterns über viele Dateien suchen
- Unabhängige Tasks parallelisieren (max 10 parallel)

**DON'T:**
- Spezifische bekannte Datei lesen → Read direkt
- In 2-3 Dateien suchen → Read direkt
- Klassen-Definition finden → Glob direkt

### Parallel Workflow Pattern

```
"Implementiere Stripe Integration parallel:

Sub-Agent 1 (Backend): API Endpoint erstellen
Sub-Agent 2 (Frontend): Payment Form Component
Sub-Agent 3 (Tests): Integration Tests schreiben

Starte alle drei parallel mit Task tool.
Warte auf Completion, dann integrieren."
```

**Git Worktrees für echte Parallelität:**
```bash
# Worktree pro Task für isolierte Entwicklung
git worktree add ../feature-a feature/a
git worktree add ../feature-b feature/b
# Separate Claude Sessions in jedem Worktree
```

---

## Multi-Session Task Patterns

### Session Handoff mit claude-progress.txt

**Am Ende jeder Session:**

```markdown
## Session 2025-12-06 14:30

### Completed
- UserService refactored to dependency injection
- All controller endpoints updated
- Unit tests passing (23/23)

### Current State
- Branch: refactor/user-service
- Last commit: abc123
- Tests: ✓ Passing

### Blockers
- None

### Next Session
1. Frontend updates for new API structure
2. Integration tests
3. Documentation
```

### Initializer + Coding Agent Pattern (Anthropic)

Für sehr lange Tasks (>8h):

```
Session 1 (Initializer):
- init.sh Script erstellen
- claude-progress.txt anlegen
- Initial Git Commit
- Grundstruktur aufsetzen

Sessions 2-N (Coding Agent):
- claude-progress.txt lesen
- Git History verstehen
- Inkrementell weitermachen
- Progress dokumentieren
```

---

## Template Prompts

### Long-Running Feature Implementation

```
"Implementiere [FEATURE] mit vollständiger Loop-Closing.

Requirements:
- [Req 1]
- [Req 2]

Approach (track mit TodoWrite):
1. [Step 1] → Test schreiben + implementieren
2. [Step 2] → Test schreiben + implementieren
...

Constraints:
- Jedes Inkrement muss testbar sein
- Committe nach jedem funktionierenden Schritt
- Dokumentiere in STATUS.md falls komplex

Token-Budget: Nutze volle 200K, stoppe NICHT früh.
Bei Context-Grenze: STATUS.md für Handoff updaten.
Parallelisiere unabhängige Tasks mit Sub-Agents."
```

### Multi-Session Refactoring

```
"Refactoring Part [N] von [TOTAL].

Previous Sessions:
- Siehe claude-progress.txt
- Git log für bisherige Änderungen

This Session Goals:
- [Goal 1]
- [Goal 2]

Am Ende dieser Session:
- claude-progress.txt updaten
- Alle Tests müssen grün sein
- Klare Next Steps dokumentieren

Falls Context knapp wird:
- Sauber abschließen (keine halben Implementierungen)
- Handoff-Dokument schreiben
- Nächste Session kann nahtlos weitermachen"
```

### Bug Investigation

```
"Untersuche und fixe Bug: [DESCRIPTION]

Beobachtetes Verhalten:
- [Was passiert]
- [Wann es passiert]
- [Error Messages]

Investigation Steps:
1. Lokal reproduzieren
2. Logs prüfen
3. Root Cause identifizieren
4. Fix implementieren
5. Regression Test hinzufügen (Loop Closing!)
6. Verifizieren

Dokumentiere Findings in STATUS.md falls komplex."
```

### Parallel Feature Development

```
"Implementiere diese 3 unabhängigen Änderungen parallel:

1. [Feature A] - Backend
2. [Feature B] - Frontend
3. [Feature C] - Tests

Nutze Task Tool mit 3 Sub-Agents.
Jeder Agent arbeitet isoliert.
Am Ende: Integration + E2E Test."
```

---

## Autonomy Levels

### High Autonomy (Default für Long Tasks)

```
"Implementiere Feature X.
Triff alle Implementierungsentscheidungen selbst basierend auf Best Practices.
Stoppe NICHT wegen Token-Budget.
Erstelle Tests und Docs während du arbeitest."
```

### Guided Autonomy (Bei kritischen Entscheidungen)

```
"Implementiere Feature X.
Frage mich VOR Entscheidungen zu:
- Datenbankschema-Änderungen
- Externe API Auswahl
- Breaking Changes

Bei allem anderen: Mach selbstständig weiter."
```

---

## Common Failure Modes

| Problem | Lösung |
|---------|--------|
| Claude stoppt zu früh | "Stoppe NICHT wegen Token-Budget" explizit sagen |
| Zu viele Rückfragen | Mehr Kontext upfront, Autonomy Level setzen |
| Code-Style passt nicht | "Folge Pattern in [FILE]" referenzieren |
| Task zu komplex | In Inkremente brechen, TodoWrite nutzen |
| Context läuft aus | claude-progress.txt + saubere Commits |
| One-shotting fails | Explizit inkrementelles Vorgehen fordern |

---

## Testing Strategy für Long Tasks

### Test Pyramid

```
          /\
         /E2E\ ← Playwright (kritische Flows)
        /-----\
       / API   \ ← Integration Tests
      /---------\
     /   Unit    \ ← Schnellstes Feedback
    /--------------\
```

### Playwright Best Practices

```typescript
// Serial Mode für abhängige Tests
test.describe.configure({ mode: 'serial' });

// Authenticated Contexts wiederverwenden
const ctx = await createAuthenticatedContext(...);

// Cleanup vor und nach Tests
await purgeTestData();
// ... test ...
await cleanupTestData();

// Traces für Debugging
use: {
  trace: 'retain-on-failure',
  screenshot: 'only-on-failure',
  video: 'retain-on-failure'
}
```

---

## Token & Cost Considerations

- **Single Agent**: ~50K-100K Tokens pro Session
- **Parallel Agents**: 3-4x höherer Token-Verbrauch
- **Trade-off**: Höhere Velocity vs. höhere Kosten

**Empfehlung:**
- Für schnelle Tasks: Single Agent
- Für komplexe/lange Tasks: Sub-Agents rechtfertigen Cost
- Claude Max Plan für heavy-duty Nutzung

---

## Quick Reference

```
START:
1. TodoWrite mit Task-Breakdown erstellen
2. Autonomy Level definieren
3. Loop-Closing Pattern etablieren

WÄHREND:
- Jedes Inkrement testen
- Nach funktionierenden Steps committen
- Sub-Agents für parallele Arbeit

ENDE / HANDOFF:
- claude-progress.txt updaten
- Tests grün
- Klare Next Steps
```

---

## Sources

Basiert auf:
- [Anthropic: Effective harnesses for long-running agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents)
- [Anthropic: Claude Code Best Practices](https://www.anthropic.com/engineering/claude-code-best-practices)
- [Anthropic: Enabling Claude Code to work more autonomously](https://www.anthropic.com/news/enabling-claude-code-to-work-more-autonomously)
- [Parallel AI Coding with Git Worktrees](https://docs.agentinterviews.com/blog/parallel-ai-coding-with-gitworktrees/)
- [Claude Code Subagent Deep Dive](https://cuong.io/blog/2025/06/24-claude-code-subagent-deep-dive)
