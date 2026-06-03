# Iter 4 — AgentCore Runtime live

> Copy this file to `iter-N.md` at the start of each iteration. Fill it in as you go.

**Date**: 2026-06-03
**Branch**: `feat/iter-4-agentcore-runtime-live`
**Iteration plan reference**: [docs/iteration-plan.md § Iteration 4](../iteration-plan.md)

---

## Goal

Wire the AgentCore Runtime to the ECR image from iter 3 so an end-to-end `invoke-agent-runtime` call returns the hardcoded `{"result":"hello"}` — proving the full plumbing (ECR → runtime → invocation → response) with no Gateway and no model call.

---

## Prompts used

Verbatim (or close paraphrase) of the prompts sent to Claude during this iteration. Order matters — they tell the story.

1. **Prompt**: `okay, can we go next iteration`
   **Why**: kick off iteration 4 per the iteration plan.

---

## Decisions made

Non-obvious choices made during this iteration, with reasoning. Things a future reader would want to know.

- **Decision**: Used resource `aws_bedrockagentcore_agent_runtime`, not `aws_bedrockagentcore_runtime` as written in `docs/04-terraform.md`.
  **Alternatives considered**: Following the doc verbatim.
  **Why**: The installed AWS provider (6.47.0) has no `aws_bedrockagentcore_runtime`; the real resource is `aws_bedrockagentcore_agent_runtime`. The doc predates the provider's resource layout and is flagged for a follow-up fix. Verified against `terraform providers schema -json`.

- **Decision**: Container goes under a nested `agent_runtime_artifact { container_configuration { container_uri } }` block; runtime named via `agent_runtime_name`; no separate endpoint resource.
  **Alternatives considered**: Top-level `container_configuration` + `name` + an `aws_bedrockagentcore_agent_runtime_endpoint` resource (as the doc's shape implies).
  **Why**: That matches the actual provider schema. A DEFAULT endpoint is auto-created on runtime creation, so `invoke-agent-runtime --agent-runtime-arn` works without managing an endpoint resource.

- **Decision**: Sanitized the runtime name with `replace(var.agent_name, "-", "_")` → `agentcore_solution1`.
  **Alternatives considered**: Passing `var.agent_name` ("agentcore-solution1") directly.
  **Why**: AgentCore runtime names allow only alphanumerics + underscore; the hyphen in `agent_name` would be rejected. `agent_name` stays unchanged so ECR repo / IAM role names from iter 3 are untouched (additive).

- **Decision**: `environment_variables = { LOG_LEVEL = "info" }` only; `depends_on` the existing `ecr_pull` + `logs` policies.
  **Alternatives considered**: Pre-adding `MODEL_ID` / `AGENTCORE_GATEWAY_URL` from the doc.
  **Why**: Iter 4 is plumbing only. Those keys arrive additively in iter 5/6 without restructuring this block.

- **Decision**: Do NOT manage the DEFAULT endpoint with `aws_bedrockagentcore_agent_runtime_endpoint`.
  **Alternatives considered**: Adding an explicit endpoint resource named `DEFAULT` (tried it).
  **Why**: A DEFAULT endpoint IS auto-created with the runtime — the resource returned `409 ConflictException: An endpoint with the specified name already exists`. The first invoke failed only because the runtime was still initializing (image pull + container start); once status went `READY` the same invoke returned 200. So no endpoint resource is needed.

---

## Files created / modified

| File | Action | Notes |
|------|--------|-------|
| `infra/runtime.tf` | added | `aws_bedrockagentcore_agent_runtime` wired to iter-3 ECR image, PUBLIC network, HTTP protocol, `LOG_LEVEL=info` |
| `infra/outputs.tf` | modified | added `agent_runtime_arn` + `agent_runtime_id` outputs |

---

## Tests

Per the iteration plan's Test phase. Record actual results, not expected.

- [x] `terraform fmt && terraform validate` → `Success! The configuration is valid.`
- [x] `terraform plan` → `1 to add, 0 to change, 0 to destroy`
- [x] `terraform apply` → `Apply complete! Resources: 1 added`. ARN `arn:aws:bedrock-agentcore:us-east-1:224193574799:runtime/agentcore_solution1-Gkn5Bz50bd`, id `agentcore_solution1-Gkn5Bz50bd`.
- [x] `aws bedrock-agentcore-control get-agent-runtime-endpoint ... --endpoint-name DEFAULT` → `{status: READY, liveVersion: 1}` (auto-created endpoint)
- [x] `aws bedrock-agentcore invoke-agent-runtime --region us-east-1 --cli-binary-format raw-in-base64-out --agent-runtime-arn $ARN --payload '{"prompt":"x"}' out.json` → `statusCode: 200`
- [x] `cat out.json` → `{"result":"hello"}`
- [x] CloudWatch `/aws/bedrock-agentcore/runtimes/agentcore_solution1-Gkn5Bz50bd-DEFAULT` → `listening on :8080` (container started across replicas). The iter-1 hello server logs no per-request line; request receipt is proven by the data-plane 200 + correct body.

---

## Forward-compatibility check

How does this iteration leave room for future iterations? Anything that should NOT be hardened or removed because a later iteration depends on it staying flexible.

- Environment variables kept minimal (`LOG_LEVEL` only) so iter 5 (model) and iter 6 (gateway) can append `MODEL_ID` / `AGENTCORE_GATEWAY_URL` without restructuring.
- `image_tag` should be a variable so future iterations hot-swap images via `-var="image_tag=<sha>"`.

---

## Open questions / follow-ups

Things that came up but weren't in scope for this iteration. Move to a future iteration or a separate ticket.

- [ ] **Fix `docs/04-terraform.md`** — its `runtime.tf` uses the non-existent `aws_bedrockagentcore_runtime` with a top-level `container_configuration`, `name`, and a `runtime_endpoint` output. The real provider (6.47.0) uses `aws_bedrockagentcore_agent_runtime` with `agent_runtime_name` and a nested `agent_runtime_artifact { container_configuration { container_uri } }`. Same doc also wires `MODEL_ID`/`AGENTCORE_GATEWAY_URL` env vars that don't belong until iter 5/6.
- [ ] Runtime/endpoint/everything lives in **us-east-1**, but the workstation's AWS CLI default region is **us-east-2** — control-plane calls silently returned empty until `--region us-east-1` was passed. Consider pinning region in tooling/docs.
- [ ] Git Bash mangles leading-slash log-group names; needed `MSYS_NO_PATHCONV=1` for `aws logs` calls on Windows.

---

## Rollback

How to undo this iteration if needed.

- `terraform destroy -target=aws_bedrockagentcore_agent_runtime.agent`
