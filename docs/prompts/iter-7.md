# Iter 7 — First tool via Gateway

> Copy this file to `iter-N.md` at the start of each iteration. Fill it in as you go.

**Date**: 2026-06-06
**Branch**: `feat/iter-7-first-tool-via-gateway`
**Iteration plan reference**: [docs/iteration-plan.md § Iteration 7](../iteration-plan.md)

---

## Goal

Register one working tool the agent can call: deploy a trivial Lambda returning canned data, expose it as an `aws_bedrockagentcore_gateway_target` on the existing (empty) gateway, and verify the agent invokes it end-to-end (`/invocations` → `InvokeModel` → `Gateway` → `Lambda` → back) — no agent-code rebuild needed.

---

## Prompts used

Verbatim (or close paraphrase) of the prompts sent to Claude during this iteration. Order matters — they tell the story.

1. **Prompt**: `1. fix this Two known doc-debt items flagged (not yet fixed) 2. proceed with next iter`
   **Why**: clear the iter-4/iter-5 doc debt, then advance to iter 7.

2. **Prompt**: `done proceed tier 7`
   **Why**: doc-debt committed; start the iter-7 scaffold.

---

## Decisions made

Non-obvious choices made during this iteration, with reasoning. Things a future reader would want to know.

- **Decision**: Infra-only iteration — no agent-code change, no Docker rebuild.
  **Alternatives considered**: Also nudging the system prompt ("you have hello_tool") to make tool use more reliable.
  **Why**: The shipped iter-6 agent already auto-discovers gateway tools via `listTools()`, so the tool is callable without code changes. Keeps iter-7 a pure, fast, low-risk Terraform change. The model reliably calls the tool when the prompt asks for the tool's exact output.

- **Decision**: Trivial inline Lambda (Node 20, ARM64) zipped at plan time via `hashicorp/archive`, returning a canned `{ greeting: "hi from lambda" }`.
  **Alternatives considered**: A separate `src/`-style Lambda source dir with a build step; reusing an existing function.
  **Why**: The iteration's whole point is the *simplest* first tool. Inline source = no extra packaging. Real tools get proper packaging in iter 8.

- **Decision**: Gateway tool name = `hello_tool` (in `inline_payload.name`), but the **target resource name** = `hello-tool`.
  **Alternatives considered**: Naming both `hello_tool`.
  **Why**: The target `name` attribute must match `^([0-9a-zA-Z][-]?){1,100}$` (hyphens OK, underscores NOT) — same rule as the gateway. `inline_payload.name` has no such constraint, so the agent-facing tool keeps the conventional `hello_tool`.

- **Decision (mid-iteration pivot)**: Switched the gateway from `authorizer_type = "AWS_IAM"` (iter 6) to `"NONE"`.
  **Alternatives considered**: (a) Stand up a `CUSTOM_JWT` authorizer (Cognito + token wiring); (b) add SigV4 signing to the `McpClient` transport.
  **Why**: Discovered that the Strands SDK `McpClient` transport makes **unsigned** HTTPS calls — it supports OAuth/JWT (`auth`/`authProvider`) and static `headers`, but has **no SigV4 option** (SigV4 helpers exist only for Bedrock and A2A, not MCP). So the iter-6 `AWS_IAM` inbound auth left the agent unable to authenticate to the gateway → `listTools()` returned empty → `continueOnError:true` degraded it silently to "0 tools loaded". `NONE` removes the inbound auth layer so the agent's unsigned MCP requests pass; the API accepted `NONE` for a Gateway. JWT auth is deferred to the production-hardening iteration. **Note:** changing `authorizer_type` *forces gateway replacement* (new URL, target recreated) — the new URL flows into the runtime env automatically, so nothing manual breaks.

- **Decision**: Added a `TOOLS_REV` runtime env var to force a fresh container when the tool set changes.
  **Alternatives considered**: Relying on the gateway target alone to make the tool appear.
  **Why**: The agent caches the gateway tool list per container lifetime (boot-time `listTools()` + a cached `McpClient`). Creating/changing a gateway target does NOT restart the container, so the live (pre-target) container kept reporting 0 tools. Bumping an env var creates a new runtime version → fresh container → re-discovery, without rebuilding the image. (The `NONE`-auth gateway replacement also bumps the runtime, but `TOOLS_REV` is the general mechanism for future tool changes.)

---

## Files created / modified

| File | Action | Notes |
|------|--------|-------|
| `infra/lambda.tf` | added | Inline hello-tool Lambda (Node20/arm64) + log-only role + archive zip |
| `infra/gateway_target.tf` | added | `aws_bedrockagentcore_gateway_target` (MCP/Lambda, zero-arg schema) + gateway-role `lambda:InvokeFunction` policy |
| `infra/versions.tf` | modified | Added `hashicorp/archive` provider (>= 2.4.0) |
| `infra/gateway.tf` | modified | `authorizer_type` AWS_IAM → NONE (forces gateway replacement); description tidy |
| `infra/runtime.tf` | modified | Added `TOOLS_REV` env var to force fresh container on tool-set changes |
| `infra/outputs.tf` | modified | Added `hello_tool_lambda_arn`, `hello_tool_target_id` |
| `.gitignore` | modified | Ignore `*.tfplan` and `infra/.build/` (archive output) |

---

## Tests

Per the iteration plan's Test phase. Record actual results, not expected.

- [x] `terraform fmt && validate` → clean (after fixing target `name` hyphen rule)
- [x] `terraform plan` (pinned `-var=image_tag=iter6`) → tool resources: **5 add, 0 change, 0 destroy** (note: default `image_tag=latest` would try to revert the runtime to a now-missing `:latest` tag — see follow-ups)
- [x] `terraform apply` (tool) → 5 added; gateway target `hello-tool` status **READY**
- [x] Direct `aws lambda invoke` hello-tool → `{"greeting":"hi from lambda"}`, StatusCode 200
- [x] Live invoke `"greet me"` **before** NONE switch → generic greeting; CloudWatch boot log `gateway: connected, 0 tools loaded` → diagnosed AWS_IAM/McpClient SigV4 incompatibility
- [x] `terraform apply` (NONE auth) → 2 add, 2 change, 2 destroy; gateway replaced (new URL `...-lloka4bsyz...`); runtime READY
- [x] Fresh-container boot log → `gateway: connected, 1 tools loaded`
- [x] Live invoke `"Call your hello_tool and reply with exactly the greeting..."` → `{"result":"hi from lambda"}`
- [x] Lambda actually executed: CloudWatch `AWS/Lambda Invocations` Sum = 1, 2 REPORT log lines in window (not hallucinated)
- [x] Always-green: `"what is 2+2?"` (non-tool) → `"2 + 2 = 4..."`, 200

---

## Forward-compatibility check

How does this iteration leave room for future iterations? Anything that should NOT be hardened or removed because a later iteration depends on it staying flexible.

- **Tool target pattern is standardized** — iter 8 adds each new tool by copying the `lambda.tf` + `gateway_target.tf` shape (target + `lambda:InvokeFunction` policy), no edits to existing resources.
- **`TOOLS_REV`** is the reusable lever to refresh the container whenever the tool set changes — bump it in the same apply that adds a tool.
- **Gateway auth is NONE for now** — deliberately not hardened. JWT (CUSTOM_JWT) is the iter-12 production-hardening task; when added, the agent will need a token via `McpClient` `headers`/`auth` (the SDK-supported path), NOT SigV4.
- Agent code untouched, so tools remain optional forever (unset `AGENTCORE_GATEWAY_URL` → 0 tools, agent still works).

---

## Open questions / follow-ups

Things that came up but weren't in scope for this iteration. Move to a future iteration or a separate ticket.

- [ ] **`:latest` ECR tag no longer exists** (expired by the keep-10 lifecycle policy after the iter-6 push). The live runtime runs `:iter6`, but `var.image_tag` defaults to `latest`, so a plain `terraform apply` tries to point the runtime at a missing tag. **Every apply until the next image push must pass `-var="image_tag=iter6"`.** Changelog rollback notes that assume `latest` exists are stale. Fix options: re-tag the current image as `latest`, or change the `image_tag` default to `iter6`. Decide in iter 8 / CI iteration.
- [ ] **`gateway_invoke` IAM policy is now dead weight** — with NONE auth the runtime no longer needs `bedrock-agentcore:InvokeGateway`. Left in place (additive/harmless) but could be removed when auth is revisited.
- [ ] JWT inbound auth for the gateway — deferred to iter 12 (production hardening).

---

## Rollback

How to undo this iteration if needed.

- Remove the tool: `terraform destroy -var="image_tag=iter6" -target=aws_bedrockagentcore_gateway_target.hello_tool -target=aws_lambda_function.hello_tool -target=aws_iam_role.hello_tool -target=aws_iam_role_policy.gateway_lambda` — the agent loses the tool but still responds (0 tools).
- Revert gateway auth to AWS_IAM: restore `authorizer_type = "AWS_IAM"` in `gateway.tf` and apply (forces another gateway replacement). Note this re-breaks tool loading until a SigV4/JWT client is added — only do this if abandoning tools.
- Full iteration revert: `git revert` the iter-7 commit, then `terraform apply -var="image_tag=iter6"` (recreates the iter-6 AWS_IAM gateway, removes the tool resources).
