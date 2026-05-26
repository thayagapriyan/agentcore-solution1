# Iteration Plan

Small, additive items to build the AgentCore deployment incrementally. Each iteration follows **Design → Develop → Test → Deploy**, leaves the system working, and is forward-compatible with later iterations.

---

## Operating principles

| Principle | What it means in practice |
|-----------|---------------------------|
| **Additive only** | Never delete or rename a working feature in the same iteration that adds a new one. Deprecate, then remove in a later iteration. |
| **Forward-compatible** | New iteration must not require old iterations to change. Use env vars and optional config to keep older flows working. |
| **Always green** | Every iteration ends with a working `/ping` + `/invocations` and a passing smoke test, even if the feature inside is a stub. |
| **Reversible** | Every iteration has a documented rollback (Terraform target destroy, image tag revert, or env-var flip). |
| **One concern per iteration** | If you're tempted to bundle two changes, split them. Smaller diffs = easier review and rollback. |

---

## Iteration map (at a glance)

| # | Iteration | Delivers | Risk |
|---|-----------|----------|------|
| 0 | Repo skeleton | Folders, configs, lint, build | None |
| 1 | Hello HTTP server | Local Express on :8080 | None |
| 2 | Containerize | ARM64 Docker image runs locally | Low |
| 3 | ECR + IAM (no runtime) | Image pushed to ECR | Low |
| 4 | AgentCore Runtime live | End-to-end invoke works (stub response) | Medium |
| 5 | Add Bedrock model call | Real Claude responses (no tools) | Medium |
| 6 | Add Gateway (empty) | MCP endpoint exists, agent ignores it | Low |
| 7 | First tool via Gateway | One real tool callable from agent | Medium |
| 8 | Additional tools | One PR per tool | Low |
| 9 | Sessions + memory | Multi-turn conversations | Medium |
| 10 | Observability hardening | Custom spans, alarms, structured logs | Low |
| 11 | CI/CD pipeline | GitHub Actions auto-deploy | Medium |
| 12 | Production hardening | VPC, cost alarms, runbook | Medium |

Time guidance: each iteration is 2–6 hours of focused work for one engineer.

---

## Iteration 0 — Repo skeleton

> Goal: a buildable repo with no AWS calls.

**Design**
- Decide folder layout (matches [README.md § Repository layout](README.md)).
- Pick package manager (npm) and TypeScript version (5.4+).

**Develop**
- Create `package.json`, `tsconfig.json`, `.gitignore`, `.dockerignore`.
- Add `src/app.ts` with `console.log("boot")` only.
- Add ESLint + Prettier configs (optional but cheap).

**Test**
- `npm install` succeeds.
- `npm run build` produces `dist/app.js`.
- `node dist/app.js` prints "boot" and exits.

**Deploy**
- None. Commit to a `feat/iter-0-skeleton` branch and merge.

**Rollback**
- Revert the merge commit.

**Future-proofing**
- Keep dependencies minimal — no Strands, no Express yet. Adding them later won't break anything.

---

## Iteration 1 — Hello HTTP server

> Goal: AgentCore-shaped HTTP server, local only, no AWS.

**Design**
- Lock in the contract: `GET /ping` returns `{status:"ok"}`, `POST /invocations` returns `{result:"hello"}`.
- Pick port from `PORT` env, default 8080.

**Develop**
- Add Express dep.
- Implement `src/app.ts` with both routes.
- Hardcode the `/invocations` response — no model, no Strands.

**Test**
- `npm run dev` starts the server.
- `curl localhost:8080/ping` → 200.
- `curl -X POST localhost:8080/invocations -d '{"prompt":"x"}'` → `{result:"hello"}`.
- Add one Jest/vitest test for the route handler (optional).

**Deploy**
- None. Local only.

**Rollback**
- Delete the file.

**Future-proofing**
- Define the response *shape* now (`{result, sessionId, usage?}`) even though only `result` is populated. Later iterations fill the other fields without changing callers.

---

## Iteration 2 — Containerize

> Goal: ARM64 Docker image runs the hello server locally.

**Design**
- Multi-stage Dockerfile (build → runtime).
- Non-root user.
- Healthcheck calling `/ping`.

**Develop**
- Add `Dockerfile` and `.dockerignore` from [03-agent-code.md](03-agent-code.md).
- No Terraform yet.

**Test**
- `docker buildx build --platform linux/arm64 -t agent:local --load .` succeeds.
- `docker run --rm -p 8080:8080 agent:local`.
- `curl localhost:8080/ping` works against the container.
- `docker inspect agent:local | grep Architecture` shows `arm64`.

**Deploy**
- None. Local image only.

**Rollback**
- Delete the Dockerfile.

**Future-proofing**
- Don't bake any AWS region or model ID into the image. All config via env vars so the same image can ship to any region/runtime.

---

## Iteration 3 — ECR + IAM (Terraform, no runtime)

> Goal: image pushed to ECR, IAM execution role exists. Runtime not yet created.

**Design**
- ECR repo with lifecycle policy.
- IAM role with trust policy for `bedrock-agentcore.amazonaws.com`, but only ECR + Logs permissions for now.

**Develop**
- Add `infra/versions.tf`, `variables.tf`, `ecr.tf`, `iam.tf` from [04-terraform.md](04-terraform.md). **Omit** `runtime.tf` and `gateway.tf`.
- Add Terraform backend (S3 + DynamoDB lock).

**Test**
- `terraform init && terraform plan` clean.
- `terraform apply` creates ECR + role only.
- Push hello image: `docker push <ECR_URI>:latest`.
- `aws ecr describe-images` shows the image.

**Deploy**
- Apply Terraform in dev account.

**Rollback**
- `terraform destroy -target=aws_ecr_repository.agent` (clears the repo + role).

**Future-proofing**
- IAM role exists now but has minimal perms — later iterations add policies (Bedrock, Gateway) by **appending** new `aws_iam_role_policy` resources, never editing the existing one.

---

## Iteration 4 — AgentCore Runtime live (still hello)

> Goal: end-to-end invocation works against AWS, returning the hardcoded `"hello"`.

**Design**
- Wire the runtime to the ECR image from iter 3.
- No Gateway, no model call yet.

**Develop**
- Add `infra/runtime.tf` from [04-terraform.md § runtime.tf](04-terraform.md#runtimetf).
- Set `environment_variables = { LOG_LEVEL = "info" }` only.

**Test**
- `terraform apply` succeeds.
- `aws bedrock-agentcore invoke-agent-runtime --agent-runtime-arn $ARN --payload '{"prompt":"x"}' out.json`.
- `cat out.json` shows `{"result":"hello", ...}`.
- CloudWatch shows container started and got the request.

**Deploy**
- Terraform apply.

**Rollback**
- `terraform destroy -target=aws_bedrockagentcore_runtime.agent`.

**Future-proofing**
- This iteration proves the **plumbing** end-to-end — ECR → runtime → invocation → response. All later iterations only change what's inside `/invocations`, not the plumbing.

---

## Iteration 5 — Add Bedrock model call

> Goal: real Claude response, no tools yet.

**Design**
- Add Strands `Agent` with `BedrockModel` only.
- Add `bedrock:InvokeModel` policy to runtime role.
- System prompt: minimal — "You are a helpful assistant."

**Develop**
- Add Strands + Bedrock SDK deps in `package.json`.
- Implement `src/agent.ts` (model only, `tools: []`).
- Wire `app.ts` to call `agent.run(prompt)`.
- Append `iam.tf` with `bedrock_invoke` policy.

**Test**
- Local: `npm run dev`, curl `/invocations` with `{"prompt":"what is 2+2?"}` → coherent answer.
- Build + push new image tag.
- Update runtime: `terraform apply -var="image_tag=<new-sha>"`.
- Invoke and verify coherent Claude response.

**Deploy**
- Build → push → `terraform apply` with new `image_tag`.

**Rollback**
- `terraform apply -var="image_tag=<previous-sha>"`. Runtime hot-swaps back.

**Future-proofing**
- Read `MODEL_ID` from env (default to Sonnet). Lets you swap models per environment without code change.

---

## Iteration 6 — Add Gateway (empty)

> Goal: Gateway exists, agent receives its URL, but no tools registered yet.

**Design**
- Create Gateway in MCP protocol mode.
- Skip authorizer (or use IAM) for now — add JWT later if needed.

**Develop**
- Add `infra/gateway.tf` with `aws_bedrockagentcore_gateway` only (no targets).
- Append `gateway_invoke` IAM policy.
- Pass `AGENTCORE_GATEWAY_URL` env var to runtime.
- In `agent.ts`, **conditionally** connect to Gateway only if URL is set:
  ```typescript
  const tools = process.env.AGENTCORE_GATEWAY_URL
    ? await McpClient.connect({ url: process.env.AGENTCORE_GATEWAY_URL, transport: "streamable-http" })
    : [];
  ```

**Test**
- `terraform apply` — Gateway created.
- Invoke agent — same Claude responses as iter 5 (no tools available, so behavior is unchanged).
- Agent logs show "connected to MCP gateway, 0 tools loaded".

**Deploy**
- Apply Terraform → build/push image → apply with new tag.

**Rollback**
- `terraform destroy -target=aws_bedrockagentcore_gateway.tools`. Agent reverts to no-tools mode automatically thanks to the conditional.

**Future-proofing**
- The conditional Gateway connection means tools are **optional forever**. You can disable Gateway in any environment by not setting the env var.

---

## Iteration 7 — First tool via Gateway

> Goal: one working tool the agent can call.

**Design**
- Pick the simplest tool first (e.g., a single Lambda that returns canned data).
- Define the input schema once, in Terraform `inline_payload`.

**Develop**
- Deploy a trivial Lambda (`helloLambda` that returns `{ greeting: "hi from lambda" }`) or reuse an existing one.
- Add `aws_bedrockagentcore_gateway_target` resource.
- Update agent system prompt: "You have a tool `hello_tool`. Use it when asked to greet."

**Test**
- Invoke with `{"prompt":"greet me"}`.
- Verify response uses the tool's output.
- CloudWatch trace shows: `/invocations` → `InvokeModel` → `Gateway:hello_tool` → `Lambda` → back.

**Deploy**
- Apply Terraform → no image rebuild needed (agent code unchanged).

**Rollback**
- `terraform destroy -target=aws_bedrockagentcore_gateway_target.hello_tool`. Agent loses the tool, still responds (just without it).

**Future-proofing**
- Standardize the target schema pattern now — every future tool follows the same Terraform shape.

---

## Iteration 8 — Additional tools (one per sub-iteration)

> Goal: register each remaining tool. Each tool = its own iteration.

**Pattern per tool**
1. Define the Lambda (or reuse existing).
2. Add `aws_bedrockagentcore_gateway_target` block.
3. Add policy line for Gateway role to invoke that Lambda.
4. Test in isolation: prompt that exercises only this tool.
5. Test in combination: prompt that requires multiple tools chained.

**Forward-compatibility rule**
- Never modify an existing tool's input schema in place — add a new tool (`v2` suffix) and deprecate the old one after consumers migrate.

---

## Iteration 9 — Sessions + memory

> Goal: multi-turn conversations maintain state.

**Design**
- Decide: in-memory session map (fine for single-instance) vs. AgentCore Memory (multi-instance, persistent).
- Default: start with AgentCore Memory for forward compatibility.

**Develop**
- Add `aws_bedrockagentcore_memory` resource (or equivalent).
- Pass `MEMORY_ARN` env var to runtime.
- In `agent.ts`, configure Strands to use AgentCore Memory when the env is set.
- Wire `sessionId` from `req.body` → `agent.run(prompt, { sessionId })`.

**Test**
- Two-turn conversation via two `invoke-agent-runtime` calls with the same `sessionId`:
  - Turn 1: "My name is Priya."
  - Turn 2: "What's my name?" → expects "Priya".
- Different `sessionId` → no memory crossover.

**Deploy**
- Terraform apply → image rebuild with memory wiring.

**Rollback**
- Unset `MEMORY_ARN` env var → agent falls back to stateless. Conversations still work, just without memory.

---

## Iteration 10 — Observability hardening

> Goal: visible failures, custom spans, alarms.

**Design**
- Identify top 3 metrics to alarm on: error rate >5%, p99 latency >10s, token spend per hour.
- Pick log format: structured JSON.

**Develop**
- Add structured logger (pino) to agent code.
- Wrap tool calls in OpenTelemetry spans (Strands supports this out of the box).
- Add `aws_cloudwatch_metric_alarm` resources.
- Add `aws_cloudwatch_log_group` with retention (e.g. 30 days).

**Test**
- Force an error (bad prompt or pulled tool) → alarm fires within 5 min.
- View trace in Application Signals → custom spans visible.

**Deploy**
- Terraform apply + image rebuild.

**Rollback**
- Alarms: `terraform destroy -target=aws_cloudwatch_metric_alarm.*`. Doesn't affect agent function.

---

## Iteration 11 — CI/CD pipeline

> Goal: PR builds + main branch auto-deploys.

**Design**
- OIDC for AWS auth (no long-lived keys).
- Two workflows: `ci.yml` (on PR) and `deploy.yml` (on main).
- Manual `workflow_dispatch` for staged rollouts.

**Develop**
- Add `.github/workflows/ci.yml`: typecheck, lint, `terraform validate`.
- Add `.github/workflows/deploy.yml` from [05-deployment.md § CI/CD](05-deployment.md#cicd--github-actions-skeleton).
- Add OIDC role to Terraform.

**Test**
- Open a dummy PR → CI runs and passes.
- Merge to main → deploy runs end-to-end and the smoke test passes.

**Deploy**
- Merge the workflow files.

**Rollback**
- Disable workflows in GitHub settings (no AWS change).

**Future-proofing**
- Keep `terraform apply` and `docker push` as separate steps so each can fail independently. Add staging environment later by parameterizing on workflow input.

---

## Iteration 12 — Production hardening

> Goal: ready for real traffic.

**Items (each can be its own sub-iteration)**
- Move runtime into a VPC if downstream Lambdas need it.
- Add JWT authorizer to Gateway (Cognito or external IdP).
- Add cost alarms (Bedrock token spend, AgentCore runtime hours).
- Write runbook: how to invoke, common errors, rollback steps, on-call playbook.
- Pen-test the `/invocations` endpoint with malformed payloads.
- Add rate limiting (Gateway has built-in throttling — configure it).
- Document SLO: e.g. p99 < 5s, availability 99.5%.

---

## Tracking progress

Use this checklist in PRs / project boards:

```
- [ ] Iter 0  — Repo skeleton
- [ ] Iter 1  — Hello HTTP server
- [ ] Iter 2  — Containerize
- [ ] Iter 3  — ECR + IAM
- [ ] Iter 4  — AgentCore Runtime live (stub)
- [ ] Iter 5  — Bedrock model call
- [ ] Iter 6  — Gateway (empty)
- [ ] Iter 7  — First tool
- [ ] Iter 8a — Tool: <name>
- [ ] Iter 8b — Tool: <name>
- [ ] Iter 9  — Sessions + memory
- [ ] Iter 10 — Observability
- [ ] Iter 11 — CI/CD
- [ ] Iter 12 — Production hardening
```

---

## When to break the rules

Some valid reasons to bundle iterations or skip ahead:

- **Spike**: prototyping to learn a new API — throw away the spike, then follow iterations properly.
- **Tight coupling discovered late**: if iter 7 reveals that iter 4's design is wrong, redo iter 4 before continuing — don't pile on.
- **Hotfix**: production breakage may need a direct change. Document it, fold the learning into the next iteration.

The plan is a default, not a contract.
