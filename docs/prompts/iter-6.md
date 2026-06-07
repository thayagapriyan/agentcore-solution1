# Iter 6 — Add Gateway (empty)

**Date**: 2026-06-03
**Branch**: `feat/iter-6-add-gateway-empty`
**Iteration plan reference**: [docs/iteration-plan.md § Iteration 6](../iteration-plan.md)

---

## Goal

Create an AgentCore Gateway (MCP protocol, no tool targets yet), pass its URL to the runtime via `AGENTCORE_GATEWAY_URL`, and have the agent conditionally connect — so behavior is unchanged (0 tools) but the plumbing for tools exists.

---

## Prompts used

1. **Prompt**: `goa head with next iter`
   **Why**: kick off iteration 6 via `/iter-start`.

2. **Decisions via AskUserQuestion**: Gateway auth = **least friction (AWS_IAM)**; scope = **full deploy end-to-end**.
   **Why**: the plan leaves auth mode and deploy depth to the operator.

3. **Prompt**: `Yes, push then apply`
   **Why**: authorize the ECR push + `terraform apply` (Gateway creation).

---

## Decisions made

- **Decision**: `authorizer_type = "AWS_IAM"` (no `authorizer_configuration` block).
  **Alternatives considered**: `CUSTOM_JWT` + Cognito (rejected — pulls iter-12 hardening forward, violates one-concern-per-iteration); `NONE` (rejected — leaves the MCP endpoint unauthenticated).
  **Why**: verified via the `create_gateway` API docs that `authorizerType` accepts `CUSTOM_JWT | AWS_IAM | NONE | AUTHENTICATE_ONLY`, and `authorizerConfiguration` is required **only** for `CUSTOM_JWT`. AWS_IAM reuses the runtime's existing IAM identity — zero extra infra.

- **Decision**: Real `McpClient` usage is `new McpClient({ url, continueOnError: true })` passed in the Agent's `tools` array.
  **Alternatives considered**: the doc's `await McpClient.connect({ url, transport })` returning a tools array — that API does not exist in `@strands-agents/sdk@1.4.0`.
  **Why**: `ToolList = (Tool | McpClient | Agent | ToolList)[]` — the agent accepts an `McpClient` instance directly and manages its connection/tool discovery.

- **Decision**: `continueOnError: true` on the MCP client; one shared client reused across per-request agents; one-time startup probe (`logGatewayStatus`) logs connection + tool count.
  **Why**: a gateway hiccup must never break `/invocations` (always-green). Verified locally: an unreachable gateway URL logs a warning and the request still succeeds with 0 tools.

- **Decision**: Gateway name = `${var.agent_name}-gw` (hyphenated).
  **Why**: gateway names must match `^([0-9a-zA-Z][-]?){1,100}$` — hyphens allowed, **underscores not** (the exact opposite of the runtime name, which disallows hyphens). Caught at plan time.

- **Decision**: `gateway_invoke` policy grants `bedrock-agentcore:InvokeGateway` on the gateway ARN (+ `/*`); Gateway gets its own role (same `agentcore` trust) with no permissions yet.
  **Why**: AWS_IAM inbound auth means the runtime signs calls to the gateway. The gateway role stays empty until iter 7 adds `lambda:InvokeFunction` for a real target.

- **Decision**: Image tag `iter6`; `latest` left untouched as rollback target.

---

## Files created / modified

| File | Action | Notes |
|------|--------|-------|
| `infra/gateway.tf` | added | Gateway role + `aws_bedrockagentcore_gateway` (MCP, AWS_IAM, no targets) |
| `infra/iam.tf` | modified | appended `gateway_invoke` policy on the runtime role |
| `infra/runtime.tf` | modified | appended `AGENTCORE_GATEWAY_URL` env + `gateway_invoke` dependency |
| `infra/outputs.tf` | modified | added `gateway_url`, `gateway_id` outputs |
| `src/agent.ts` | modified | conditional shared `McpClient` (continueOnError), `logGatewayStatus` probe |
| `src/app.ts` | modified | call `logGatewayStatus()` after `listen` |

---

## Tests

- [x] `npm run build` → clean compile.
- [x] `terraform fmt` / `validate` → clean / valid.
- [x] Local, `AGENTCORE_GATEWAY_URL` **unset** → log `gateway: not configured … 0 tools`; `/ping` 200; `/invocations` → `{"result":"ok", …}` (iter-5 behavior preserved).
- [x] Local, `AGENTCORE_GATEWAY_URL` set to an **unreachable** URL → `MCP server failed to connect, continuing (continueOnError)`; `/invocations` still → `{"result":"ok", …}` (0 tools, request unbroken).
- [x] `terraform plan` → **3 to add, 1 to change, 0 to destroy** (gateway role, gateway, `gateway_invoke`; runtime env update).
- [x] `docker push :iter6` → digest `sha256:cdefb91bb011bb1f0e5ff8b8a2975da469df419b760d7b3d431c4fd279af614b`.
- [x] `terraform apply -var=image_tag=iter6` → 3 added, 1 changed; outputs `gateway_id=agentcore-solution1-gw-tkmu8umbyq`, `gateway_url=https://…/mcp`; runtime version 4, status `READY`.
- [x] Live `invoke-agent-runtime` → `statusCode 200`, `{"result":"2+2 equals 4.", …}` (behavior unchanged).
- [x] CloudWatch (live runtime) → `gateway: connected, 0 tools loaded`.

---

## Forward-compatibility check

- Gateway connection is conditional on `AGENTCORE_GATEWAY_URL` → tools stay optional forever; unset the env var to disable Gateway in any environment.
- `gateway.tf` adds the Gateway only (no targets) → iter 7 appends `aws_bedrockagentcore_gateway_target` without restructuring.
- Gateway role exists but has no permissions yet → iter 7 appends `lambda:InvokeFunction` by adding a policy, never editing existing ones.
- `environment_variables` gained `AGENTCORE_GATEWAY_URL` (key appended, block not restructured).
- `latest` ECR tag preserved → image-revert rollback stays available.

---

## Open questions / follow-ups

- [ ] **AWS_IAM MCP auth**: the runtime connected cleanly to the empty AWS_IAM gateway (0 tools). Iter 7 must validate that actual *tool invocation* over MCP authenticates correctly under AWS_IAM (SigV4); if not, revisit JWT/OAuth for the data plane.
- [ ] **Docs drift**: `docs/04-terraform.md` `gateway.tf` section still shows a `CUSTOM_JWT`/Cognito example and a `gateway_target` shape that is unverified. Update once iter 7 proves the target wiring.
- [ ] **Node version**: AWS SDK v3 node>=22 warning still applies (carried from iter 5).
- [ ] **Stale images**: `:iter5` (pre-fix) and now intermediate tags remain in ECR; rely on the lifecycle policy or prune.

---

## Rollback

- `terraform destroy -target=aws_bedrockagentcore_gateway.tools` — agent auto-reverts to no-tools mode (conditional connection). Also `-target=aws_iam_role_policy.gateway_invoke` and `-target=aws_iam_role.gateway` to drop the role/policy.
- Or flip: unset `AGENTCORE_GATEWAY_URL` on the runtime (the `getGatewayClient` guard then yields 0 tools).
- Image revert: `terraform apply -var="image_tag=iter5b"`.
