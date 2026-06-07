# Iter 8a — Tool with input - add two numbers

> Copy this file to `iter-N.md` at the start of each iteration. Fill it in as you go.

**Date**: 2026-06-06
**Branch**: `feat/iter-8a-tool-with-input-add-two-numbers`
**Iteration plan reference**: [docs/iteration-plan.md § Iteration 8](../iteration-plan.md)

---

## Goal

Add a second gateway tool that takes real input arguments — an `add` tool (sum two numbers) — following the standardized iter-7 pattern (Lambda + `aws_bedrockagentcore_gateway_target` + gateway-role invoke policy). Exercises the `tool_schema.inline_payload.input_schema { property { ... } }` path that hello_tool's zero-arg schema did not, proving the schema shape for input-taking tools. Test the tool in isolation and chained with hello_tool.

---

## Prompts used

Verbatim (or close paraphrase) of the prompts sent to Claude during this iteration. Order matters — they tell the story.

1. **Prompt**: `verify current stage of this project and proceed to next iter`
   **Why**: confirm iter-7 landed, then advance to iter 8.

2. **Prompt** (decisions): clean up the committed build artifact first; make the iter-8a tool one that takes an input.
   **Why**: repo hygiene + exercise the input_schema path not covered by the zero-arg hello_tool.

---

## Decisions made

Non-obvious choices made during this iteration, with reasoning. Things a future reader would want to know.

- **Decision**: Tool `add` (sum two numbers) with an `input_schema` of two required `number` properties (`a`, `b`).
  **Alternatives considered**: A no-arg "current time" tool; a single-string tool.
  **Why**: The point of iter-8a is to exercise the `inline_payload.input_schema { property { ... } }` path that hello_tool's zero-arg schema didn't. `add` is the smallest tool that needs two typed, required inputs.

- **Decision**: The add Lambda coerces inputs with `Number(...)` and guards `NaN`.
  **Alternatives considered**: Trusting the gateway to pass numeric JSON types.
  **Why**: The MCP/gateway may serialize tool args as strings; coercion makes `"17"` and `17` both work, and the NaN guard returns a clean error object instead of `null`/`NaN`.

- **Decision**: Each tool gets its own log-only IAM role + its own `lambda:InvokeFunction` gateway policy (didn't share with hello_tool).
  **Alternatives considered**: One shared Lambda role; one combined gateway policy listing both ARNs.
  **Why**: Keeps every tool independently destroyable (rollback granularity) and strictly additive — the iter-7 resources are untouched, matching the iteration-plan "one PR per tool, never edit existing" rule.

- **Decision**: Bumped `TOOLS_REV` (`iter7-hello-tool` → `iter8a-add-tool`) to force a fresh container.
  **Why**: Same reason as iter-7 — the agent caches the gateway tool list per container lifetime, so a new target isn't seen until the container restarts. The env-var bump creates a new runtime version without a Docker rebuild.

- **Non-issue investigated**: the plan showed `aws_lambda_function.hello_tool will be updated in-place` (source_code_hash change) even though hello_tool's source was untouched. Verified `archive_file` is **deterministic** (two rebuilds → identical hash `4vHkLA...`); the one-time diff was the deployed iter-7 zip's bytes vs. the current build. Harmless re-upload of identical code; does not recur.

---

## Files created / modified

| File | Action | Notes |
|------|--------|-------|
| `infra/lambda.tf` | modified | Appended `add_tool` Lambda (Node20/arm64, sums a+b) + own log-only role + archive zip |
| `infra/gateway_target.tf` | modified | Appended `add-tool` target (input_schema with two required number properties) + `gateway_lambda_add` invoke policy |
| `infra/runtime.tf` | modified | Bumped `TOOLS_REV` to `iter8a-add-tool` (force fresh container) |
| `infra/outputs.tf` | modified | Added `add_tool_lambda_arn`, `add_tool_target_id` |

---

## Tests

Per the iteration plan's Test phase. Record actual results, not expected.

- [x] `terraform fmt`/`validate` → clean
- [x] `terraform plan` (`-var=image_tag=iter6`) → 5 add, 2 change, 0 destroy (change = TOOLS_REV runtime bump + harmless hello_tool code re-upload)
- [x] `archive_file` determinism check → two rebuilds produce identical hash (`DETERMINISTIC`)
- [x] `terraform apply` → 5 added, 2 changed; add-tool target id `QVI5MNMCJV`, runtime READY
- [x] direct `aws lambda invoke {"a":17,"b":25}` → `{"sum":42}`, 200
- [x] **isolation**: invoke `"Use your add tool to add 17 and 25..."` → `{"result":"42"}`
- [x] fresh-container boot log → `gateway: connected, 2 tools loaded`
- [x] **combination/chain**: invoke `"greet me using hello tool, then add 100 and 23..."` → both tools called: `"Hi from lambda! 👋 ... 100 + 23 = 123"`
- [x] add-tool Lambda genuinely executed: 3 CloudWatch REPORT lines (direct + isolation + chain), not hallucinated
- [x] always-green: `"capital of France?"` (non-tool) → `"Paris"`, 200

---

## Forward-compatibility check

How does this iteration leave room for future iterations? Anything that should NOT be hardened or removed because a later iteration depends on it staying flexible.

- **Input-taking tool template established** — future tools copy the `add` shape (`input_schema { property { name/type/required } }`); zero-arg tools copy `hello_tool`.
- Per-tool isolation (own role + own invoke policy) preserved — iter 8b/8c append without touching 8a.
- Per the plan's forward-compat rule: never edit a tool's input schema in place — add a `v2`-suffixed tool and deprecate the old one.
- `TOOLS_REV` remains the standard container-refresh lever for every tool-set change.
- Agent code still untouched → tools stay optional and auto-discovered.

---

## Open questions / follow-ups

Things that came up but weren't in scope for this iteration. Move to a future iteration or a separate ticket.

- [ ] (carried from iter-7) `:latest` ECR tag is gone — every apply still needs `-var="image_tag=iter6"` until the next image push. Worth fixing in the CI iteration (re-tag, or default `image_tag` to `iter6`).
- [ ] (carried from iter-7) `gateway_invoke` IAM policy on the runtime role is dead weight under NONE auth — could be pruned when auth is revisited (iter 12).

---

## Rollback

How to undo this iteration if needed.

- Remove just the add tool: `terraform destroy -var="image_tag=iter6" -target=aws_bedrockagentcore_gateway_target.add_tool -target=aws_lambda_function.add_tool -target=aws_iam_role.add_tool -target=aws_iam_role_policy.gateway_lambda_add` — agent drops to 1 tool (hello_tool), still works.
- Full iteration revert: `git revert` the iter-8a commit, then `terraform apply -var="image_tag=iter6"` (removes add-tool resources; reverts `TOOLS_REV`).
