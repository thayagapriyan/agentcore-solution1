# Iter 0 — Repo skeleton (+ planning docs)

**Date**: 2026-05-25 to 2026-05-26
**Branch**: `main` (no remote yet — first content in the repo)
**Iteration plan reference**: [docs/iteration-plan.md § Iteration 0](../iteration-plan.md)

This log covers the **planning + Iter 0** burst, since they all happened in one continuous Claude Code session before any commits existed.

---

## Goal

Three things bundled into one session:
1. Plan how to deploy a Strands agent to Bedrock AgentCore (research + decision).
2. Capture that plan as durable documentation (`docs/` set).
3. Ship Iter 0 — a buildable repo skeleton with no AWS calls.

---

## Prompts used

1. **Prompt**: *"what should i do if need to deploy this project or any new agent project into bedrock agent core?"*
   **Why**: Open-ended scoping question. Wanted Claude's read on the gap between the existing `strands-solution1` (legacy Bedrock Agents) and AgentCore Runtime, before committing to any code.

2. **Prompt**: *"okay first add necessary .md files for this work . i need typescript , terraform, nodejs, strands and necesary tech"*
   **Why**: Lock the plan in writing before writing any code. Tech stack scoped explicitly so Claude wouldn't drift into Python/CDK.

3. **Correction**: *"can you do this work inside agentcore-solution1 project folder"*
   **Why**: Claude started writing into the existing `strands-solution1` repo. The intent was a fresh sibling project. Correction redirected output to the empty `agentcore-solution1` repo.

4. **Prompt**: *"okay can you divide all these work as small items, we will go through those items iteratively like usual software development, design develop test deploy. every iteration should not break anything and should be able to adopt all future changes"*
   **Why**: Converted the static docs into an **executable** plan — 12 iterations, each with explicit Design/Develop/Test/Deploy/Rollback. Forward-compatibility was an explicit requirement.

5. **Prompt**: *"okay, now go ahead with iteration 0"*
   **Why**: Kick off execution. Trusts the plan from prompt 4; no further scoping needed.

6. **Prompt**: *"what is the best way to track claude changelog with prompt..."*
   **Why**: Process question, not code. Wanted a system to preserve the *why* of changes alongside git's *what*.

7. **Prompt**: *"go ahead with your recommendation"*
   **Why**: Adopted Claude's recommended `CHANGELOG.md` + `docs/prompts/` + structured commits combo.

---

## Decisions made

- **Decision**: Fresh project in `agentcore-solution1`, not in-place migration of `strands-solution1`.
  **Alternatives**: In-place rewrite, or sibling subfolder inside the existing repo.
  **Why**: Keeps the legacy reference intact for the migration doc; lets the new project start clean without Lambda/zip baggage.

- **Decision**: `"type": "module"` + `NodeNext` from Iter 0, even though Iter 0 has no imports.
  **Alternatives**: CommonJS now, migrate later.
  **Why**: Strands SDK and `@modelcontextprotocol/sdk` are ESM-first. Picking the right module system once avoids a painful flip in Iter 5.

- **Decision**: No ESLint/Prettier in Iter 0.
  **Alternatives**: Add now (plan said "optional but cheap").
  **Why**: Truly minimal start. Style tooling is easy to bolt on once there's >1 source file.

- **Decision**: One CHANGELOG entry per **logical** unit (Docs / Plan / Iter / Meta), not per commit.
  **Alternatives**: One changelog entry per commit.
  **Why**: Commit count is a noisy proxy for change. A reader cares about "what shipped in Iter 3", not "the 7 commits that made up Iter 3".

---

## Files created / modified

### Docs phase (2026-05-25)
| File | Action |
|------|--------|
| `docs/README.md` | added |
| `docs/01-prerequisites.md` | added |
| `docs/02-architecture.md` | added |
| `docs/03-agent-code.md` | added |
| `docs/04-terraform.md` | added |
| `docs/05-deployment.md` | added |
| `docs/06-migration.md` | added |

### Plan phase (2026-05-26)
| File | Action |
|------|--------|
| `docs/iteration-plan.md` | added |
| `docs/README.md` | modified (added iteration-plan link) |

### Iter 0 build (2026-05-26)
| File | Action | Notes |
|------|--------|-------|
| `package.json` | added | Node 20+, TS 5.4, `type: module`, only TS + rimraf as deps |
| `tsconfig.json` | added | ES2022, NodeNext, strict |
| `.gitignore` | added | Includes Terraform + AWS exclusions for future iterations |
| `.dockerignore` | added | Excludes docs/, infra/, etc. for future Iter 2 |
| `src/app.ts` | added | Single line: `console.log("boot");` |

### Meta phase (2026-05-26)
| File | Action |
|------|--------|
| `CHANGELOG.md` | added |
| `docs/prompts/_template.md` | added |
| `docs/prompts/iter-0.md` | added (this file) |

---

## Tests

Iter 0 acceptance criteria from the iteration plan:

- [x] `npm install` → `added 45 packages, and audited 46 packages in 3s` / `found 0 vulnerabilities`
- [x] `npm run build` → `dist/app.js` exists
- [x] `node dist/app.js` → prints `boot`

---

## Forward-compatibility check

- `"type": "module"` + NodeNext = ESM-ready for Strands SDK (Iter 5) and `@modelcontextprotocol/sdk` (Iter 6+).
- `.gitignore` already includes `.terraform/`, `*.tfstate`, `.env` — Iter 3 (ECR + IAM Terraform) won't need to touch it.
- `.dockerignore` already excludes `infra/`, `docs/`, `.git`, `node_modules`, `dist` — Iter 2 (containerize) can use it as-is.
- No AWS region, model ID, or account ID baked into any file. All future config will land in env vars and Terraform variables.
- No ESLint/Prettier config locks us into a style — can add either later without conflict.

---

## Open questions / follow-ups

- [ ] Decide on test framework before Iter 1 (vitest vs. node:test). Lean: `node:test` to keep deps minimal.
- [ ] Decide on logger before Iter 5 (`pino` vs. plain `console`). Plan says pino in Iter 10; might want it earlier.
- [ ] Set up git remote (GitHub repo) before Iter 11 (CI/CD).
- [ ] Decide on AWS account strategy (single account multi-env, or separate accounts per env) before Iter 3.

---

## Rollback

```powershell
# Delete the Iter 0 files
Remove-Item package.json, tsconfig.json, .gitignore, .dockerignore
Remove-Item -Recurse src, node_modules, dist
```

Docs and plan can stay regardless — they don't depend on the code.
