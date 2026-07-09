<!-- AI-IAP:START - Do not edit this section manually -->
# [Project Name] — CLAUDE.md

## Hard Rules (violations cause bugs)
- Follow all applicable rules and rule precedence.
- Memory Protocol is MANDATORY: load matching `docs/memory/` files BEFORE each task, update them AFTER (see Context Memory System).
- Ask 2-5 targeted questions if outcomes or constraints are unclear.
- Validate all external input before use (type, format, bounds).
- Never log or store secrets; redact sensitive values in logs.
- Use code library patterns instead of inventing new ones.
- Do not introduce fixed versions; read from project config files.
- Prefer smallest change that satisfies requirements.
- Keep outputs concise and unambiguous across AI tools.

---

## Initial Setup — Auto-Discovery & Questions

**TRIGGER:** If any section below still contains `<!-- AUTO-FILLED -->` or `<!-- PENDING -->` comments, the initial setup has NOT been completed. Run this process before any other work.

### Step 1: Auto-Discovery (no questions needed)

Analyze the codebase automatically to fill in what can be derived from files:

- **Tech stack:** Read `package.json`, `composer.json`, `Cargo.toml`, `go.mod`, `requirements.txt`, `Gemfile`, `*.csproj`, etc.
- **Directory structure:** Run `ls` / `find` to map the project layout
- **Build commands:** Check `package.json` scripts, `Makefile`, `docker-compose.yml`, CI/CD configs
- **Existing conventions:** Check for `.editorconfig`, `eslint.config.*`, `prettier.config.*`, `phpstan.neon`, `tsconfig.json`
- **Architecture patterns:** Scan directory structure for known patterns (MVC, DDD, feature-first, etc.)
- **Existing documentation:** Check for `README.md`, `ARCHITECTURE.md`, `CONTRIBUTING.md`, `docs/`
- **Git history:** Read recent commits for commit message conventions

### Step 2: Ask Targeted Questions (only what can't be auto-discovered)

After auto-discovery, ask the user ONLY what's missing. Ask one question at a time, use multiple choice where possible.

**Questions to ask (skip if already answered by auto-discovery):**

1. **Project description:** "What does this project do in one sentence?"
2. **UI language:** "What language is the UI in?" (A) English (B) German (C) Other: ___
3. **Architecture specifics:** "Are there architectural patterns I should know about that aren't obvious from the code?" (e.g., multi-tenancy, CQRS, event sourcing)
4. **Authentication:** "How does authentication work?" (if not obvious from code)
5. **Compliance/regulations:** "Are there legal or compliance requirements?" (e.g., GDPR, HIPAA, PCI, industry-specific)
6. **Deployment:** "How is the project deployed?" (A) Docker (B) Cloud (AWS/GCP/Azure) (C) VPS (D) Serverless (E) Other
7. **Dev environment setup:** "What commands do I need to run to get the project running locally?" (if not in README)
8. **Key conventions not in config:** "Are there coding conventions that aren't enforced by linters?" (e.g., naming patterns, file organization rules)
9. **Known pain points:** "Are there areas of the codebase that need special attention or are fragile?"

### Step 3: Fill In CLAUDE.md

Using auto-discovered data + user answers, fill in ALL `<!-- AUTO-FILLED -->` sections below. Remove sections that don't apply. Remove all `<!-- AUTO-FILLED -->` and `<!-- PENDING -->` comments. Then commit the updated CLAUDE.md.

### Step 4: Build Initial Context Memory

If the project has enough complexity (3+ features, multiple entities, etc.), create the `docs/memory/` system as described in the Context Memory System section below.

### Step 5: Delete This Section

After setup is complete, **delete the entire "Initial Setup — Auto-Discovery & Questions" section** from this file. It is only needed once and should not remain in the final CLAUDE.md.

---

## Self-Maintenance — Keep CLAUDE.md & Memory Up to Date

**IMPORTANT:** This CLAUDE.md is a living document. It MUST be updated as the project evolves.

### Update CLAUDE.md when
- New tech stack is added (e.g. new framework, new database)
- New architecture decisions are made (extend ADR table)
- New conventions are established (coding rules, naming, etc.)
- New modules/features change the project scope
- Build/deploy commands change
- New directories or structural changes are introduced

### Context Memory
- Governed entirely by the **Memory Protocol** in the Context Memory System section — no separate trigger list; the file table defines when to load AND when to update.

---

## Workflow & Quality Assurance

### Planning
- For tasks with 3+ steps or architecture decisions: use Plan Mode before writing code.
- If an implementation is going in the wrong direction: stop immediately and re-plan — don't push through.
- Clarify specifications upfront to reduce ambiguity.

### Verification
- Never complete a task without verification: run tests, check logs, demonstrate correctness.
- For relevant changes: verify diff against previous behavior.
- Simple fixes don't need elaborate verification — effort proportional to complexity.

### Bug Fixing
- On bug reports: analyze and fix independently — use logs, error messages, and tests as starting points.
- Find the root cause. No temporary workarounds. Don't expect hand-holding from the user.
- Fix failing CI tests independently.

### Learning Loop
- After corrections from the user: capture the learning in `docs/memory/` so the same mistake is not repeated. Store only stable, repeatable patterns — not one-off decisions.

### Core Principles
- **Simplicity First:** Every change as simple as possible. Touch minimal code.
- **Minimal Impact:** Only change what's necessary. Don't introduce new bugs.
- **Root Cause:** Find causes, don't treat symptoms.

---

## Context Memory System

`docs/memory/` holds structured project knowledge: decisions, context, gotchas.

### Memory Protocol (MANDATORY — no exceptions)

1. **BEFORE each task:** Load the memory file(s) whose "When to load" matches the task — never all, never none (if none matches, say so and proceed). If `docs/memory/` is missing and the project is complex enough, build it first.
2. **AFTER each significant change:** Update the file whose scope matches what changed (same mapping as "When to load"). Feature added/removed/changed → also update the `features.md` index.
3. A task is **NOT complete** until step 2 is done. Treat a skipped memory update like a failing test.

### File Structure

| File | Content | When to load |
|------|---------|-------------|
| `README.md` | Index with loading rules | Always (it's short) |
| `architecture-decisions.md` | ADRs with reasoning and context | For architecture/design questions |
| `entity-model.md` | Entity relationships, tenant-awareness, specifics | For entity/DB changes |
| `frontend-patterns.md` | Established frontend patterns and conventions | For frontend work |
| `backend-patterns.md` | Backend patterns (services, processors, etc.) | For backend work |
| `deployment.md` | Server, env files, CI/CD, gotchas | For deploy/infra topics |
| `module-status.md` | Status and specifics per module/feature | For feature-specific work |
| `features.md` | Feature index — short description + link per feature | To find the right feature file |
| `features/<name>.md` | Per-feature detail (decisions, critical info, gotchas) | When working on that specific feature |
| `bugs-and-fixes.md` | Root cause analyses of solved bugs | For bug fixing |

### Feature Memory

Each feature gets its own file under `docs/memory/features/`. The index `docs/memory/features.md` links to them.

**Index file (`features.md`):**
```markdown
| Feature | Description | File |
|---------|-------------|------|
| Authentication | Login, registration, password reset, 2FA | [auth.md](features/auth.md) |
| User Management | Team members, roles, permissions | [users.md](features/users.md) |
```

**Feature file (`features/<name>.md`)** contains:
- Entities, views, controllers involved
- Architecture decisions specific to this feature
- Critical business rules and compliance requirements
- Known gotchas and edge cases
- Integration points with other features

Only load the specific feature file when working on that feature — never all of them.

**When features change:**
- **New feature added:** Create `features/<name>.md` with entities, decisions, gotchas. Add entry to `features.md` index.
- **Feature removed:** Delete the feature file. Remove entry from `features.md` index.
- **Feature significantly changed:** Update the feature file with new decisions, entities, or gotchas.

### Content Rules

- **Format:** Fact-based, bullet points with concrete file paths/values — no prose
- **No duplication:** Don't store anything derivable from code or git — only decisions, context, gotchas
- **Not everything:** Only create memory files that are relevant to the project. A small frontend project doesn't need `deployment.md`

---

## Project Overview

<!-- AUTO-FILLED from discovery + user answers -->

| Layer | Stack | Directory |
|-------|-------|-----------|
| Backend | | |
| Frontend | | |
| Infra | | |

---

## Quick Start

<!-- AUTO-FILLED from package.json scripts, Makefile, docker-compose, README -->

```bash
# Setup
# Start dev server
# Run tests
```

---

## Language & Locale

<!-- AUTO-FILLED from user answer -->

- **UI Language:** English
- **Code Language:** English (variables, functions, types)
- **API Fields:** English

---

## Architecture

<!-- AUTO-FILLED from code analysis + user answers -->

---

## Conventions

<!-- AUTO-FILLED from linter configs, .editorconfig, code patterns + user answers -->

---

## Architecture Decisions (ADRs)

<!-- PENDING — filled during initial setup and extended over time -->

| ADR | Decision | Reasoning |
|-----|----------|-----------|
| 001 | | |

---

## Build & Verification

<!-- AUTO-FILLED from package.json scripts, Makefile, CI configs -->

```bash
# Type-Check
# Build
# Tests
```

---

## Change Guidelines

<!-- AUTO-FILLED based on project patterns -->

1. **New Entity:** ...
2. **New UI Component:** ...
3. **New View/Route:** ...
4. **New Feature:** ...
<!-- AI-IAP:END -->
