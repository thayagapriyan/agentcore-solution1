# Iter 3 — ECR + IAM

**Date**: 2026-05-31
**Branch**: `feat/iter-3-ecr-iam`
**Iteration plan reference**: [docs/iteration-plan.md § Iteration 3](../iteration-plan.md)

---

## Goal

Stand up the first Terraform infrastructure — an ECR repository (with lifecycle policy) and the AgentCore execution IAM role (trust policy + minimal ECR/Logs permissions only). Push the iter-2 hello image to ECR. **No** runtime, **no** gateway yet.

---

## Prompts used

Verbatim (or close paraphrase) of the prompts sent to Claude during this iteration. Order matters — they tell the story.

1. **Prompt**: `go ahead and start next iteration`
   **Why**: Begin Iteration 3 (ECR + IAM).

2. **Prompt**: `/iter-start 3 "ecr-iam"`
   **Why**: Scaffold the branch and prompt log for iteration 3.

> Tip: if a prompt was a follow-up correction ("no don't do X, do Y"), include it — the corrections are usually more instructive than the original prompt.

---

## Decisions made

Non-obvious choices made during this iteration, with reasoning. Things a future reader would want to know.

- **Decision**: S3-native state locking (`use_lockfile = true`) instead of the DynamoDB lock table shown in [docs/04-terraform.md](../04-terraform.md).
  **Alternatives considered**: bootstrap a `terraform-locks` DynamoDB table (doc's approach).
  **Why**: Terraform 1.10+ (we have 1.15.4) locks via an S3 object — no DynamoDB to create or pay for. Doc uses the older pattern; flagged for a docs pass.

- **Decision**: Reuse the existing `warewise-tfstate-224193574799` bucket (us-east-1, versioned) with key `agentcore-solution1/terraform.tfstate`.
  **Alternatives considered**: bootstrap a dedicated bucket.
  **Why**: One state bucket / separate key per project is standard; the bucket already exists and is versioned. No bootstrap step needed.

- **Decision**: Resources in `us-east-1`; `agent_name = "agentcore-solution1"`.
  **Alternatives considered**: us-east-2 (CLI default); name `inventory-agent` (doc default).
  **Why**: Account already shows prior AgentCore use in us-east-1 (existing runtime bucket), de-risking iter 4. Name matches the project.

- **Decision**: `iam.tf` includes only `ecr_pull` + `logs` policies this iteration.
  **Alternatives considered**: copy the doc's full `iam.tf` (bedrock/gateway/xray policies).
  **Why**: Plan mandates "ECR + Logs only"; Bedrock (iter 5), Gateway (iter 6/7), X-Ray (iter 10) get **appended** later so the role grows additively. Also omitted `runtime.tf` and `gateway.tf` entirely.

---

## Files created / modified

| File | Action | Notes |
|------|--------|-------|
| `docs/prompts/iter-3.md` | added | This prompt log |
| `infra/versions.tf` | added | provider + backend |
| `infra/variables.tf` | added | input variables |
| `infra/ecr.tf` | added | ECR repo + lifecycle policy |
| `infra/iam.tf` | added | execution role + minimal ECR/Logs policy |
| `infra/outputs.tf` | added | ECR repo URL output |

---

## Tests

Per the iteration plan's Test phase. Record actual results, not expected.

- [x] `terraform init` → backend "s3" configured, AWS provider v6.47.0 installed, success
- [x] `terraform validate` → `Success! The configuration is valid.`
- [x] `terraform fmt -check -recursive` → clean
- [x] `terraform plan` → `Plan: 5 to add, 0 to change, 0 to destroy` (ECR repo + lifecycle, role, ecr_pull, logs)
- [x] `terraform apply -auto-approve` → `Apply complete! Resources: 5 added, 0 changed, 0 destroyed.`
      Outputs: `ecr_repository_url = 224193574799.dkr.ecr.us-east-1.amazonaws.com/agentcore-solution1`, `agent_runtime_role_arn = arn:aws:iam::224193574799:role/agentcore-solution1-runtime-role`
- [x] `aws ecr get-login-password | docker login ...` → `Login Succeeded`
- [x] `docker tag agent:local <ECR_URI>:latest && docker push <ECR_URI>:latest` → pushed, `digest: sha256:f3f9548d...`
- [x] `aws ecr describe-images --repository-name agentcore-solution1` → image present, tag `latest`
- [x] manifest inspect → OCI image index containing `linux/arm64` (+ `unknown/unknown` buildx attestation manifest)

---

## Forward-compatibility check

How does this iteration leave room for future iterations? Anything that should NOT be hardened or removed because a later iteration depends on it staying flexible.

- IAM role created now with **minimal** perms (ECR pull + Logs). Later iterations (5: Bedrock, 6/7: Gateway) **append** new `aws_iam_role_policy` resources — never edit the existing role inline.
- `runtime.tf` and `gateway.tf` deliberately omitted this iteration.
- All values (region, agent_name, image_tag, model_id) are variables — no hardcoded account IDs or regions.

---

## Open questions / follow-ups

Things that came up but weren't in scope for this iteration. Move to a future iteration or a separate ticket.

- [ ] **Iter 4 watch-out**: the pushed `latest` is an OCI image *index* (buildx default attestations add an `unknown/unknown` manifest). If AgentCore Runtime rejects the index, rebuild with `docker buildx build --provenance=false --sbom=false` to push a plain single-arch arm64 manifest.
- [ ] ECR scan status showed `None` right after push despite `scan_on_push = true` — re-check that scanning completes (basic scanning may lag, or enhanced scanning isn't enabled).
- [ ] Docs pass: update `docs/04-terraform.md` to (a) S3-native locking and (b) note the minimal-IAM split for iter 3 vs later policy appends.
- [ ] `.gitignore` ignores `.terraform.lock.hcl`; consider committing it for reproducible provider versions (left as-is this iteration to avoid scope creep).

---

## Rollback

How to undo this iteration if needed.

- `terraform destroy -target=aws_ecr_repository.agent` (clears the repo + role), or `terraform destroy` for everything in `infra/`.
