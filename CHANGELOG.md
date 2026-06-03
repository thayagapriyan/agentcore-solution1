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

## [Iter 1] — 2026-05-26 — Hello HTTP server

- Added: `express` dependency, `@types/express` devDep, `dev` script in `package.json`
- Modified: `src/app.ts` — Express server with `GET /ping` and `POST /invocations` (stub `{result:"hello"}`)
- Added: `docs/prompts/iter-1.md`
- Tests:
  - `npm run build` → clean compile, no errors
  - `node dist/app.js` → `listening on :8080`
  - `curl localhost:8080/ping` → `{"status":"ok"}` (200)
  - `curl -X POST localhost:8080/invocations -d '{"prompt":"x"}'` → `{"result":"hello"}` (200)
- Prompt log: [docs/prompts/iter-1.md](docs/prompts/iter-1.md)
- Rollback: delete `src/app.ts`, revert `package.json` to remove Express
- Forward-compatibility: response shape `{result, sessionId?, usage?}` defined now; port reads from `PORT` env var

## [Iter 2] — 2026-05-31 — Containerize

- Added: `Dockerfile` — multi-stage ARM64 build (`node:20-bookworm-slim`), non-root `agent` user (uid 1001), `/ping` healthcheck. `.dockerignore` already present from earlier.
- Added: `docs/prompts/iter-2.md`
- Changed: healthcheck uses a node-based `fetch` probe instead of the `wget` shown in `docs/03-agent-code.md` — the slim base image ships neither `wget` nor `curl`, so `wget` left the container `unhealthy`. Doc flagged for a follow-up fix.
- Tests:
  - `docker buildx build --platform linux/arm64 -t agent:local --load .` → build succeeded, 0 vulnerabilities
  - `docker image inspect agent:local --format '{{.Architecture}}/{{.Os}}'` → `arm64/linux`
  - `curl localhost:8080/ping` → `{"status":"ok"}` (200)
  - `curl -X POST localhost:8080/invocations -d '{"prompt":"x"}'` → `{"result":"hello"}` (200)
  - `docker exec ... whoami` → `agent` (non-root)
  - healthcheck → `healthy` within ~10s
- Prompt log: [docs/prompts/iter-2.md](docs/prompts/iter-2.md)
- Rollback: delete the `Dockerfile` (no AWS resources touched)
- Forward-compatibility: no region/model/account baked into the image — all config via env vars; `PORT` overridable

## [Iter 3] — 2026-05-31 — ECR + IAM

- Added: `infra/versions.tf` (S3 backend, S3-native lock, AWS provider >= 5.70), `infra/variables.tf`, `infra/ecr.tf` (repo + lifecycle), `infra/iam.tf` (execution role + minimal `ecr_pull`/`logs` policies), `infra/outputs.tf`
- Added: `docs/prompts/iter-3.md`
- Deliberately omitted: `runtime.tf`, `gateway.tf` (later iterations)
- Infra (us-east-1, acct 224193574799): ECR repo `agentcore-solution1`, IAM role `agentcore-solution1-runtime-role`. State in `warewise-tfstate-224193574799` key `agentcore-solution1/terraform.tfstate`.
- Pushed hello image → `224193574799.dkr.ecr.us-east-1.amazonaws.com/agentcore-solution1:latest` (`linux/arm64`, digest `sha256:f3f9548d…`)
- Tests:
  - `terraform init/validate/fmt` → backend OK, valid, clean
  - `terraform plan` → 5 to add, 0 change, 0 destroy
  - `terraform apply` → 5 added
  - `docker push` + `aws ecr describe-images` → image present, tag `latest`, arm64
- Prompt log: [docs/prompts/iter-3.md](docs/prompts/iter-3.md)
- Rollback: `terraform destroy` (or `-target=aws_ecr_repository.agent`)
- Forward-compatibility: IAM role has minimal perms now — Bedrock/Gateway/X-Ray policies get appended in later iterations, never edited in place; all values are variables (no hardcoded account/region in code)

---

> **Convention**: append new entries at the **bottom** of the iteration list. Never edit a past entry — add a follow-up entry instead. Past commits stay immutable; the changelog reflects that.
