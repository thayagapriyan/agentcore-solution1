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

## [Iter 4] — 2026-06-03 — AgentCore Runtime live

- Added: `infra/runtime.tf` (`aws_bedrockagentcore_agent_runtime` wired to the iter-3 ECR image — PUBLIC network, HTTP protocol, `LOG_LEVEL=info`, depends on existing `ecr_pull`/`logs` policies). `infra/outputs.tf` — `agent_runtime_arn` + `agent_runtime_id`.
- Added: `docs/prompts/iter-4.md`
- Infra (us-east-1, acct 224193574799): runtime `agentcore_solution1-Gkn5Bz50bd`, ARN `arn:aws:bedrock-agentcore:us-east-1:224193574799:runtime/agentcore_solution1-Gkn5Bz50bd`. DEFAULT endpoint auto-created (no `_endpoint` resource needed).
- Note: `docs/04-terraform.md` is out of date — uses the non-existent `aws_bedrockagentcore_runtime` with top-level `container_configuration`; real provider (6.47.0) uses `aws_bedrockagentcore_agent_runtime` with nested `agent_runtime_artifact`. Flagged for a follow-up fix.
- Tests:
  - `terraform validate` → valid; `terraform plan` → 1 to add, 0 change, 0 destroy
  - `terraform apply` → 1 added; runtime + DEFAULT endpoint both `READY`
  - `invoke-agent-runtime --payload '{"prompt":"x"}'` → `statusCode: 200`, `out.json` → `{"result":"hello"}`
  - CloudWatch `/aws/bedrock-agentcore/runtimes/...-DEFAULT` → `listening on :8080` (container started)
- Prompt log: [docs/prompts/iter-4.md](docs/prompts/iter-4.md)
- Rollback: `terraform destroy -target=aws_bedrockagentcore_agent_runtime.agent`
- Forward-compatibility: env vars minimal (`LOG_LEVEL` only) so iter 5/6 append `MODEL_ID`/`AGENTCORE_GATEWAY_URL` without restructuring; plumbing (ECR→runtime→invoke→response) is proven once here — later iterations change only what's inside `/invocations`

## [Iter 5] — 2026-06-03 — Add Bedrock model call

- Added: `src/agent.ts` (Strands `Agent` + `BedrockModel`, `tools: []`, per-request agent / reused model client); deps `@strands-agents/sdk`, `zod`, `@modelcontextprotocol/sdk`, `@opentelemetry/api`; `.npmrc` (`legacy-peer-deps=true`)
- Changed: `src/app.ts` — `/invocations` now calls `agent.invoke()` and returns `result.toString()`; parses any-content-type bodies (`express.json({ type: () => true })`); 400-guards missing prompt; echoes `sessionId`. `Dockerfile` — `COPY` includes `.npmrc`. `infra/iam.tf` — appended `bedrock_invoke` policy. `infra/variables.tf` — added `model_id`. `infra/runtime.tf` — appended `MODEL_ID` env + `bedrock_invoke` dependency.
- Docs fix: corrected `docs/03-agent-code.md` (real package `@strands-agents/sdk`, `agent.invoke`/`result.toString()` API, `.npmrc`, node-fetch healthcheck) and `docs/04-terraform.md` (real resource `aws_bedrockagentcore_agent_runtime` with nested `agent_runtime_artifact`, outputs).
- Model: default `MODEL_ID=global.anthropic.claude-haiku-4-5-20251001-v1:0` (Haiku 4.5 is inference-profile-only); overridable via env / `model_id` var.
- Tests:
  - `npm run build` → clean compile
  - Local: `/ping` → 200; `/invocations {"prompt":"what is 2+2?"}` → `"2+2 equals 4."`; `{}` → 400; body without JSON content-type → parsed (the fix)
  - ARM64 container (`:iter5b`, creds injected) → `/ping` ok, prompt → `"Paris"`
  - `terraform fmt/validate` clean; `plan` → 1 add, 1 change, 0 destroy
  - `docker push :iter5b` → digest `sha256:7929ed58…`; `terraform apply` → runtime v3 `READY`
  - Live `invoke-agent-runtime` → `statusCode 200`, coherent Claude response
- Prompt log: [docs/prompts/iter-5.md](docs/prompts/iter-5.md)
- Rollback: `terraform apply -var="image_tag=latest"` (reverts to iter-4 hello image; `latest` left untouched); optionally `terraform destroy -target=aws_iam_role_policy.bedrock_invoke`
- Forward-compatibility: `MODEL_ID` env-driven (swap models, no code change); `tools: []` explicit for iter 6/7; `bedrock_invoke` is a new policy resource (existing ones untouched); `sessionId` echoed for the session iteration; `latest` tag preserved for image-revert rollback

## [Iter 6] — 2026-06-03 — Add Gateway (empty)

- Added: `infra/gateway.tf` — Gateway execution role + `aws_bedrockagentcore_gateway` (MCP protocol, `AWS_IAM` inbound auth, **no targets yet**). `src/agent.ts` — conditional shared `McpClient` (`continueOnError: true`) included in the agent's `tools` only when `AGENTCORE_GATEWAY_URL` is set, plus a one-time `logGatewayStatus` probe.
- Changed: `infra/iam.tf` — appended `gateway_invoke` policy (`bedrock-agentcore:InvokeGateway` on the gateway ARN). `infra/runtime.tf` — appended `AGENTCORE_GATEWAY_URL` env + `gateway_invoke` dependency. `infra/outputs.tf` — added `gateway_url`/`gateway_id`. `src/app.ts` — call `logGatewayStatus()` after `listen`.
- Auth: `AWS_IAM` (verified `authorizerType` ∈ `CUSTOM_JWT|AWS_IAM|NONE|AUTHENTICATE_ONLY`; `authorizerConfiguration` only required for `CUSTOM_JWT`) — least friction, no Cognito; JWT deferred.
- Infra (us-east-1, acct 224193574799): gateway `agentcore-solution1-gw-tkmu8umbyq`, url `https://agentcore-solution1-gw-tkmu8umbyq.gateway.bedrock-agentcore.us-east-1.amazonaws.com/mcp`. Runtime → version 4. Image `:iter6`.
- Tests:
  - `npm run build` clean; `terraform fmt/validate` clean
  - Local (gateway unset) → `not configured, 0 tools`; `/ping` 200; `/invocations` ok
  - Local (gateway URL unreachable) → `continueOnError` warning; `/invocations` still ok (0 tools)
  - `terraform plan` → 3 add, 1 change, 0 destroy; `apply` → gateway created, runtime v4 `READY`
  - `docker push :iter6` → digest `sha256:cdefb91b…`
  - Live `invoke-agent-runtime` → 200, `{"result":"2+2 equals 4."}` (behavior unchanged)
  - CloudWatch (live) → `gateway: connected, 0 tools loaded`
- Prompt log: [docs/prompts/iter-6.md](docs/prompts/iter-6.md)
- Rollback: `terraform destroy -target=aws_bedrockagentcore_gateway.tools` (agent auto-reverts to no-tools via the conditional); or unset `AGENTCORE_GATEWAY_URL`; image revert `terraform apply -var="image_tag=iter5b"`
- Forward-compatibility: Gateway connection is conditional (tools optional forever); gateway has no targets and its role no perms yet → iter 7 appends a target + `lambda:InvokeFunction` without editing existing resources; env block gained a key, not restructured; `latest`/`iter5b` tags preserved for rollback

## [Docs follow-up] — 2026-06-06 — Sync deployment docs to shipped iter-6 code

- Changed: `docs/03-agent-code.md` — `src/agent.ts` now shows the shipped iter-6 factory (conditional `McpClient` gateway tools + `logGatewayStatus` probe) instead of the iter-5 model-only stub; `src/app.ts` shows the `logGatewayStatus()` boot call; "tools not shown" note replaced with an iter-7 forward note.
- Changed: `docs/04-terraform.md` — corrected to match shipped infra: `variables.tf` defaults (`agent_name=agentcore-solution1`, Haiku 4.5 inference-profile `model_id`); `iam.tf` `bedrock_invoke` (three ARNs: foundation-model + inference-profile + application-inference-profile), `logs` split out from a bundled `observability` (X-Ray deferred to iter 10), `gateway_invoke` (`gateway_arn` + `/*`); `gateway.tf` (empty gateway, `authorizer_type="AWS_IAM"`, no JWT/target — Lambda target moved to a labeled iter-7 block); `runtime.tf` (`AGENTCORE_GATEWAY_URL` env wired, `gateway_invoke` in `depends_on`); `outputs.tf` (added `agent_runtime_role_arn`, `gateway_id`); cost table authorizer row → `AWS_IAM`.
- These resolve the two doc-debt items flagged in the Iter 4 and Iter 5 entries.
- Tests: N/A (docs only); cross-checked each block against the live `infra/*.tf` and `src/*.ts`.
- Rollback: `git revert` this commit (docs only — no code or AWS impact).

## [Iter 7] — 2026-06-06 — First tool via Gateway

- Added: `infra/lambda.tf` (inline hello-tool Lambda — Node 20, ARM64, returns `{greeting:"hi from lambda"}` + log-only role + `archive_file` zip); `infra/gateway_target.tf` (`aws_bedrockagentcore_gateway_target` MCP/Lambda, zero-arg `hello_tool` schema, gateway-IAM-role auth + appended `gateway_lambda` `lambda:InvokeFunction` policy).
- Changed: `infra/versions.tf` (added `hashicorp/archive` provider); `infra/runtime.tf` (added `TOOLS_REV` env var to force a fresh container when the tool set changes); `infra/outputs.tf` (added `hello_tool_lambda_arn`, `hello_tool_target_id`); `.gitignore` (ignore `*.tfplan`, `infra/.build/`).
- **Gateway auth pivot**: `infra/gateway.tf` `authorizer_type` AWS_IAM → **NONE**. The Strands SDK `McpClient` transport makes unsigned MCP calls (supports OAuth/JWT/static-headers, no SigV4), so the iter-6 AWS_IAM gateway left the agent loading 0 tools. NONE removes the inbound auth layer (API accepted it); JWT deferred to iter 12. Changing `authorizer_type` forces gateway replacement → new URL `...-lloka4bsyz...` (flows into the runtime env automatically). Infra-only — no agent code change, no Docker rebuild.
- Infra (us-east-1, acct 224193574799): Lambda `agentcore-solution1-hello-tool`; gateway target `hello-tool` (id `NQUICMUMNY`, READY); gateway replaced → `agentcore-solution1-gw-lloka4bsyz`; runtime pinned to `:iter6`, new version, READY.
- Tests:
  - `terraform fmt -check`/`validate` → clean (target `name` needs a hyphen, not underscore)
  - `terraform plan` (tool, `-var=image_tag=iter6`) → 5 add, 0 change, 0 destroy; `apply` → target READY
  - direct `aws lambda invoke` → `{"greeting":"hi from lambda"}` (200)
  - `apply` (NONE auth) → 2 add, 2 change, 2 destroy; gateway replaced, runtime READY
  - fresh-container boot log → `gateway: connected, 1 tools loaded`
  - live invoke "call your hello_tool and reply with exactly the greeting…" → `{"result":"hi from lambda"}`
  - Lambda genuinely executed: CloudWatch `AWS/Lambda Invocations` Sum=1 (not hallucinated)
  - always-green: `"what is 2+2?"` (non-tool) → `"2 + 2 = 4…"`, 200
- Prompt log: [docs/prompts/iter-7.md](docs/prompts/iter-7.md)
- Rollback: `terraform destroy -var="image_tag=iter6" -target=aws_bedrockagentcore_gateway_target.hello_tool -target=aws_lambda_function.hello_tool -target=aws_iam_role.hello_tool -target=aws_iam_role_policy.gateway_lambda` (agent loses the tool, still responds with 0 tools); full revert: `git revert` the commit + `terraform apply -var="image_tag=iter6"`.
- Forward-compatibility: tool target pattern standardized for iter 8 (copy `lambda.tf` + `gateway_target.tf`, append-only); `TOOLS_REV` is the reusable container-refresh lever; gateway auth deliberately left at NONE (JWT is iter 12, and must use `McpClient` headers/auth — NOT SigV4); agent code untouched so tools stay optional forever.
- Known follow-ups (see prompt log): `:latest` ECR tag expired (keep-10 lifecycle) → every apply must pass `-var="image_tag=iter6"` until next image push; `gateway_invoke` IAM policy is now dead weight under NONE auth (harmless, left additive).

## [Meta] — 2026-06-06 — Untrack terraform build artifact

- Changed: `git rm --cached infra/.build/hello_tool.zip` — the `archive_file` zip was committed in iter-7 before the `.gitignore` rule existed; tracked files bypass gitignore, so it kept causing churn. Now untracked (file stays on disk, regenerated by `terraform plan`).
- Tests: N/A (repo hygiene); `git ls-files` confirms `.build/` no longer tracked.
- Rollback: `git revert` the chore commit.

## [Iter 8a] — 2026-06-06 — Tool with input (add two numbers)

- Added: `add-tool` Lambda (`infra/lambda.tf` — Node 20, ARM64, sums `a`+`b` with Number-coercion + NaN guard, own log-only role + archive zip); `add-tool` gateway target (`infra/gateway_target.tf` — first tool with a real `input_schema`: two required `number` properties `a`/`b`) + `gateway_lambda_add` `lambda:InvokeFunction` policy.
- Changed: `infra/runtime.tf` (`TOOLS_REV` → `iter8a-add-tool`, forces fresh container); `infra/outputs.tf` (added `add_tool_lambda_arn`, `add_tool_target_id`).
- Additive only — iter-7 hello_tool resources untouched; each tool keeps its own role + invoke policy for independent rollback. Infra-only, no Docker rebuild.
- Infra (us-east-1, acct 224193574799): Lambda `agentcore-solution1-add-tool`; gateway target `add-tool` (id `QVI5MNMCJV`) on gateway `...-gw-lloka4bsyz`; runtime new version, READY.
- Tests:
  - `terraform fmt`/`validate` → clean; `plan` (`-var=image_tag=iter6`) → 5 add, 2 change, 0 destroy
  - `archive_file` determinism check → two rebuilds → identical hash (the hello_tool in-place diff was a harmless one-time re-upload, not recurring)
  - `apply` → 5 added, 2 changed; runtime READY
  - direct `aws lambda invoke {"a":17,"b":25}` → `{"sum":42}`
  - isolation: `"add 17 and 25"` → `{"result":"42"}`
  - boot log → `gateway: connected, 2 tools loaded`
  - chain: `"greet me, then add 100 and 23"` → both tools called → `"Hi from lambda! 👋 … 100 + 23 = 123"`
  - add-tool Lambda genuinely executed: 3 CloudWatch REPORT lines (not hallucinated)
  - always-green: `"capital of France?"` (non-tool) → `"Paris"`, 200
- Prompt log: [docs/prompts/iter-8a.md](docs/prompts/iter-8a.md)
- Rollback: `terraform destroy -var="image_tag=iter6" -target=aws_bedrockagentcore_gateway_target.add_tool -target=aws_lambda_function.add_tool -target=aws_iam_role.add_tool -target=aws_iam_role_policy.gateway_lambda_add` (agent drops to 1 tool, still works); full revert: `git revert` + `terraform apply -var="image_tag=iter6"`.
- Forward-compatibility: establishes the input-taking tool template (`input_schema { property { name/type/required } }`) for all future tools; per-tool isolation lets iter 8b/8c append without editing 8a; never edit a tool's schema in place (add `v2`, deprecate); `TOOLS_REV` stays the refresh lever; agent code untouched so tools stay optional/auto-discovered.
- Known follow-ups (carried from iter-7): `:latest` ECR tag still gone (apply needs `-var="image_tag=iter6"`); dead `gateway_invoke` policy under NONE auth.

---

> **Convention**: append new entries at the **bottom** of the iteration list. Never edit a past entry — add a follow-up entry instead. Past commits stay immutable; the changelog reflects that.
