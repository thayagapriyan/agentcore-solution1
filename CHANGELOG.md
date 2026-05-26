# Changelog

Human-readable history of changes to this project, organized by iteration. See [docs/iteration-plan.md](docs/iteration-plan.md) for the iteration roadmap and [docs/prompts/](docs/prompts/) for the prompts and decisions behind each iteration.

Format:
```
## [Iter N] — YYYY-MM-DD — <title>
- Added / Changed / Removed: <files or features>
- Tests: <what was verified>
- Prompt log: docs/prompts/iter-N.md
- Rollback: <how to undo>
```

---

## [Docs] — 2026-05-25 — AgentCore deployment documentation

- Added: `docs/README.md`, `docs/01-prerequisites.md`, `docs/02-architecture.md`, `docs/03-agent-code.md`, `docs/04-terraform.md`, `docs/05-deployment.md`, `docs/06-migration.md`
- Tests: N/A (docs only)
- Prompt log: [docs/prompts/iter-0.md](docs/prompts/iter-0.md)
- Rollback: delete `docs/` folder

## [Plan] — 2026-05-26 — Iteration plan

- Added: `docs/iteration-plan.md` (12 iterations, each with Design / Develop / Test / Deploy / Rollback)
- Tests: N/A (docs only)
- Prompt log: [docs/prompts/iter-0.md](docs/prompts/iter-0.md)
- Rollback: delete `docs/iteration-plan.md`

## [Iter 0] — 2026-05-26 — Repo skeleton

- Added: `package.json`, `tsconfig.json`, `.gitignore`, `.dockerignore`, `src/app.ts`
- Tech: Node 20+, TypeScript 5.4, ES2022, NodeNext modules, `"type": "module"`
- Tests:
  - `npm install` → 45 packages, 0 vulnerabilities
  - `npm run build` → `dist/app.js` produced
  - `node dist/app.js` → prints `boot`
- Prompt log: [docs/prompts/iter-0.md](docs/prompts/iter-0.md)
- Rollback: `git revert <commit>` or delete the 5 files added
- Forward-compatibility: `type: module` + NodeNext chosen so Iter 1 (Express) and Iter 5 (Strands ESM) drop in without churn

## [Meta] — 2026-05-26 — Changelog + prompt-archive system

- Added: `CHANGELOG.md`, `docs/prompts/_template.md`, `docs/prompts/iter-0.md`
- Tests: N/A (process docs)
- Rollback: delete the 3 files

## [Meta] — 2026-05-26 — Claude persistent-context system

- Added:
  - `CLAUDE.md` — project guide (mission, stack, conventions, tracking)
  - `AGENTS.md` — tool-agnostic pointer to CLAUDE.md
  - `.claude/settings.json` — pre-approved safe commands (npm, tsc, terraform plan/validate, read-only AWS, read-only docker, safe git)
  - `.claude/settings.local.json.example` — template for personal overrides
  - `.claude/commands/iter-start.md` — `/iter-start N "title"` slash command
  - `.claude/commands/iter-end.md` — `/iter-end` slash command
  - `.editorconfig` — LF, UTF-8, 2-space, final newline
  - `.nvmrc` — Node 20 pin
  - `.vscode/settings.json` + `.vscode/extensions.json`
- Changed: `.gitignore` — exclude `.claude/settings.local.json` (keep shared settings + example committed)
- Tests: N/A (config files; verified via inspection)
- Rollback: delete the new files + revert the `.gitignore` line
- Forward-compatibility: hooks, custom skills, and subagents intentionally deferred — easy to add to `.claude/` later without touching what's there

---

> **Convention**: append new entries at the **bottom** of the iteration list. Never edit a past entry — add a follow-up entry instead. Past commits stay immutable; the changelog reflects that.
