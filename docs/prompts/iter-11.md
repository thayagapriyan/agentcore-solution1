# Iter 11 — CI/CD pipeline

**Date**: 2026-06-06
**Branch**: `feat/iter-11-ci-cd-pipeline`
**Iteration plan reference**: [docs/iteration-plan.md § Iteration 11](../iteration-plan.md)

---

## Goal

PRs run automated checks (typecheck + `terraform validate`) and merges to `main`
auto-build the ARM64 image, push to ECR, `terraform apply` the new image tag, and
smoke-test the deployed runtime — all via GitHub Actions using OIDC (no long-lived
AWS keys).

---

## Prompts used

1. **Prompt**: `proceed to next iter` → (redirected) `ignore iter 10, move it to last; proceed to iteration 11 ci/cd`
   **Why**: Start the CI/CD iteration, deferring observability hardening.

2. **Prompt**: answers to design questions — repo derived from git remote
   (`thayagapriyan/agentcore-solution1`), build/push-then-apply ordering, OIDC role
   added as new `infra/cicd.tf`.
   **Why**: Lock the three decisions that aren't derivable from the repo.

---

## Decisions made

- **Decision**: OIDC trust scoped to `repo:thayagapriyan/agentcore-solution1:*`.
  **Alternatives considered**: a Terraform variable with no default.
  **Why**: The git remote already pins the repo; hardcoding (via a defaulted var)
  keeps `terraform apply` argument-free, matching the rest of the infra.

- **Decision**: Single full `terraform apply -var="image_tag=<sha>"` in deploy.yml,
  after build+push.
  **Alternatives considered**: in-workflow two-phase targeted apply.
  **Why**: ECR repo + runtime already exist from prior iterations, so the image is
  present before apply runs. Simpler YAML; the two-phase dance is only needed for a
  cold account (documented as a one-time local bootstrap).

- **Decision**: CI "lint" step is `tsc --noEmit` + `terraform fmt -check` +
  `terraform validate`. No ESLint.
  **Alternatives considered**: adding ESLint now.
  **Why**: CLAUDE.md keeps lint deps out until an iteration explicitly asks; iter 11
  doesn't.

- **Decision**: OIDC role's first apply is bootstrapped by a dedicated in-CI
  `bootstrap.yml` (manual dispatch, temporary keys), not a local terraform run.
  **Why**: The deploy workflow assumes the role to run; the role can't create itself
  from inside the workflow on the first run (chicken-and-egg). Keeping it in-CI means
  no local tooling is required.

- **Decision**: The GitHub OIDC provider is consumed via a `data` source, not owned
  by this stack.
  **Why**: It already exists account-wide (one per issuer URL) and is shared across
  projects; `CreateOpenIDConnectProvider` returned 409 EntityAlreadyExists. Owning it
  would risk a `terraform destroy` here removing a provider other repos depend on.

- **Decision**: `bootstrap.yml` PRINTS the role ARN with copy-paste instructions
  rather than auto-setting the `AWS_ROLE_ARN` Actions variable.
  **Alternatives considered**: `administration: write` on GITHUB_TOKEN (often still
  403 by repo policy); a fine-grained PAT secret (adds a secret to manage).
  **Why**: The default GITHUB_TOKEN can't write Actions variables (403 Resource not
  accessible by integration). The ARN is stable, so a one-time manual paste is
  reliable and avoids introducing another secret.

- **Decision**: Workflows pin Terraform `1.15.4` (the user's local version).
  **Alternatives considered**: `1.6.6` (the doc skeleton's value).
  **Why**: The S3 backend uses `use_lockfile`, which requires Terraform >= 1.10;
  1.6.6 failed init with "Unsupported argument".

---

## Files created / modified

| File | Action | Notes |
|------|--------|-------|
| `.github/workflows/ci.yml` | added | PR checks: typecheck, terraform fmt/validate |
| `.github/workflows/deploy.yml` | added | main + workflow_dispatch: build→push→apply→smoke |
| `infra/cicd.tf` | added | OIDC provider + GitHub Actions deploy role (additive) |
| `infra/variables.tf` | modified | add `github_repo` var (defaulted to the remote) |
| `infra/outputs.tf` | modified | output the deploy role ARN for the workflow `vars` |

---

## Tests

Per the iteration plan's Test phase. Record actual results, not expected.

- [x] `npx tsc --noEmit` → exit 0 (clean)
- [x] `terraform fmt -check -recursive` (in infra/) → exit 0 (no reformatting needed)
- [x] `terraform init -backend=false && terraform validate` → "Success! The
      configuration is valid." (full config including cicd.tf)
- [x] Run "Bootstrap OIDC" workflow → deploy role created; role ARN printed and set
      as the AWS_ROLE_ARN Actions variable; bootstrap secrets deleted.
- [x] Deploy workflow (OIDC, no keys) → build/push ARM64 → `terraform apply` → smoke
      test PASSED. invoke-agent-runtime returned statusCode 200 with a valid `result`
      field; agent answered coherently and listed its real tools (add-tool,
      hello-tool). Sample:
      `{"result":"I don't have a \"ping\" tool ... add-tool ... hello-tool ...","sessionId":"b8fd7cc5-..."}`

Fixes required along the way (each surfaced by a failed run, then corrected):
- Terraform version: workflows pinned 1.6.6 but the S3 backend uses `use_lockfile`
  (needs >= 1.10) → bumped all three workflows to 1.15.4.
- OIDC provider already existed account-wide (409) → switched to a `data` source.
- GITHUB_TOKEN can't write Actions variables (403) → bootstrap now prints the ARN
  with copy-paste instructions instead of auto-setting it.
- Deploy role lacked `iam:ListOpenIDConnectProviders` (the data source resolves by
  URL via List) → added a List-on-`*` statement alongside the scoped Get.

---

## Forward-compatibility check

- Workflows read region/repo/role-arn from GitHub Actions `vars`, not hardcoded — a
  staging environment later only needs a second var set / environment.
- `deploy.yml` keeps build/push and `terraform apply` as separate steps so each can
  fail independently (per plan's future-proofing note).
- `infra/cicd.tf` is additive; destroying it disables CI/CD without touching the
  runtime.

---

## Open questions / follow-ups

- [ ] Exercise `ci.yml` via a real PR — it's validated locally (tsc/fmt/validate all
      pass) but the deploy path landed via direct pushes to main, so the PR-triggered
      CI workflow hasn't run on GitHub yet.
- [ ] Staging environment + `workflow_dispatch` input for staged rollouts (iter 12).
- [ ] Bedrock model-access must be granted in the deploy account for the smoke test
      to return a real answer (pre-existing requirement, not new here).

---

## Rollback

- Disable both workflows in GitHub → Settings → Actions (no AWS change).
- `terraform -chdir=infra destroy -target=aws_iam_role.github_deploy` removes the
  deploy role. Do NOT destroy the OIDC provider — it's a shared, account-wide
  singleton consumed via a data source (other repos may depend on it).
- Delete `.github/workflows/*.yml` to remove the pipeline entirely.
