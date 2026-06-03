# Iter 5 — Add Bedrock model call

**Date**: 2026-06-03
**Branch**: `feat/iter-5-add-bedrock-model-call`
**Iteration plan reference**: [docs/iteration-plan.md § Iteration 5](../iteration-plan.md)

---

## Goal

Replace the hardcoded `/invocations` stub with a real Claude response by wiring a Strands `Agent` backed by `BedrockModel` (no tools yet), and grant the runtime role `bedrock:InvokeModel`.

---

## Prompts used

1. **Prompt**: `can we start next iteration?`
   **Why**: kick off iteration 5 via `/iter-start`.

2. **Decisions surfaced via AskUserQuestion**: default model = **Claude Haiku 4.5**; scope = **full deploy end-to-end** (pausing at each AWS-mutating step).
   **Why**: lock the two open choices the plan leaves to the operator before writing code.

3. **Prompt**: `Yes, push then apply`
   **Why**: authorize the ECR push + `terraform apply` deploy steps.

---

## Decisions made

- **Decision**: Use `@strands-agents/sdk@^1.4.0` (real package), not `@aws/strands-agents@^0.4.0` from the docs.
  **Alternatives considered**: the doc's package name (404 on npm).
  **Why**: `@aws/strands-agents` does not exist. The published TS SDK is `@strands-agents/sdk`. Its API also differs from the doc: `agent.invoke(prompt)` → `AgentResult`, `result.toString()` for text; `BedrockModel`/`Agent` import from the package root.

- **Decision**: Default `MODEL_ID = global.anthropic.claude-haiku-4-5-20251001-v1:0`.
  **Alternatives considered**: bare `anthropic.claude-haiku-4-5-20251001-v1:0` (rejected — Haiku 4.5 is `INFERENCE_PROFILE`-only, no on-demand throughput); `us.` profile (works, but `global.` gives broader routing).
  **Why**: confirmed via `aws bedrock list-foundation-models` / `list-inference-profiles`.

- **Decision**: `app.use(express.json({ type: () => true }))` — parse every body as JSON.
  **Alternatives considered**: default `express.json()` (gates on `application/json`).
  **Why**: the first live invoke returned **400**. AgentCore forwards the payload without a JSON `Content-Type`, so the default parser left `req.body` empty → "prompt is required". Reproduced locally with `curl --data` (defaults to `x-www-form-urlencoded`) and confirmed the fix.

- **Decision**: Fresh `Agent` per request; reuse one `BedrockModel`.
  **Why**: `Agent` carries conversation `messages` + an invocation lock; a shared instance would bleed state across requests and reject concurrency. Sessions arrive in iter 9.

- **Decision**: `.npmrc` with `legacy-peer-deps=true`, also `COPY`'d into the Docker build.
  **Alternatives considered**: bump Express to 5 (rejected — additive-only; our trivial Express usage works on 4, and the SDK's `express@^5.1.0` peer is **optional**).
  **Why**: the SDK's optional peers (`@a2a-js/sdk`, `express@^5`) trip npm's strict peer resolver. The flag keeps Express 4 locked and makes both local installs and the in-container `npm ci` resolve identically.

- **Decision**: IAM grants `bedrock:InvokeModel` **and** `bedrock:InvokeModelWithResponseStream` on foundation-model + inference-profile ARNs.
  **Why**: Strands uses the Converse**Stream** API, and the inference profile fans out to anthropic foundation models across regions.

- **Decision**: Image tag `iter5b`; `latest` left untouched as the rollback target.
  **Why**: `iter5` was the pre-content-type-fix build (returned 400 live). `iter5b` is the working image.

---

## Files created / modified

| File | Action | Notes |
|------|--------|-------|
| `src/agent.ts` | added | Strands `Agent` factory, `BedrockModel`, `tools: []`, `MODEL_ID` env default |
| `src/app.ts` | modified | `/invocations` calls `agent.invoke`; parse-all-bodies; 400 guard; `sessionId` echo |
| `package.json` / `package-lock.json` | modified | + `@strands-agents/sdk`, `zod`, `@modelcontextprotocol/sdk`, `@opentelemetry/api` |
| `.npmrc` | added | `legacy-peer-deps=true` |
| `Dockerfile` | modified | `COPY` now includes `.npmrc` so in-container `npm ci` matches local |
| `infra/iam.tf` | modified | appended `aws_iam_role_policy.bedrock_invoke` (existing policies untouched) |
| `infra/variables.tf` | modified | added `model_id` variable |
| `infra/runtime.tf` | modified | appended `MODEL_ID` env + `bedrock_invoke` to `depends_on` |

---

## Tests

- [x] `npm run build` → clean compile.
- [x] Local `node dist/app.js`:
  - `GET /ping` → `{"status":"ok"}` (200)
  - `POST /invocations {"prompt":"what is 2+2?..."}` → `{"result":"2+2 equals 4.", ...}`
  - `POST /invocations {}` → **400** (`prompt is required`)
  - `sessionId` echoed when supplied (`abc-123`)
  - body without JSON `Content-Type` → parsed → `{"result":"works", ...}` (the fix)
- [x] ARM64 container (`:iter5b`, AWS creds injected) → `/ping` ok, `POST /invocations` → `{"result":"Paris", ...}`
- [x] `terraform fmt -check` clean, `terraform validate` valid, `terraform plan` → **1 to add, 1 to change, 0 to destroy**
- [x] `docker push :iter5b` → digest `sha256:7929ed58e5acb2f708b61ae7813fb5da8c3797b585d3cb54b270ecd3ad7ec2f7`
- [x] `terraform apply -var=image_tag=iter5b` → runtime version 3, status `READY`
- [x] Live `invoke-agent-runtime` → `statusCode: 200`, coherent Claude response ("Amazon Bedrock AgentCore is a service that enables developers to build and deploy autonomous agents…")

---

## Forward-compatibility check

- `MODEL_ID` read from env (code default + Terraform `model_id` var) → swap models per environment with no code change.
- `tools: []` left explicit; iter 6/7 populate it without changing the agent's shape.
- `bedrock_invoke` is a **new** `aws_iam_role_policy` resource — existing `ecr_pull`/`logs` policies untouched (additive).
- `environment_variables` gained a key (`MODEL_ID`); the block was not restructured, so iter 6 can append `AGENTCORE_GATEWAY_URL` the same way.
- `sessionId` already echoed in the response → iter 9 wires it to real session state without changing callers.
- `latest` ECR tag preserved → image-tag-revert rollback stays available.

---

## Open questions / follow-ups

- [ ] **Docs drift**: `docs/03-agent-code.md` uses the non-existent `@aws/strands-agents` and an outdated API (`McpClient.connect` returning tools, async `createAgent`, `agent.run`). Update to `@strands-agents/sdk` + `agent.invoke` / `result.toString()`.
- [ ] **Node version**: AWS SDK v3 warns it will require `node >=22` after Jan 2027; the base image / `.nvmrc` are pinned to node 20 (CLAUDE.md stack). Plan a base-image bump.
- [ ] **Stale image**: the pre-fix `:iter5` image is still in ECR. Prune it (or let the lifecycle policy age it out).

---

## Rollback

- `terraform apply -var="image_tag=latest"` — runtime hot-swaps back to the iter-4 hello image.
- To also drop the new permission: `terraform destroy -target=aws_iam_role_policy.bedrock_invoke`.
- Code revert: restore the `{result:'hello'}` stub in `src/app.ts` and delete `src/agent.ts`.
