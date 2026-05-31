# Iter 2 — Containerize

**Date**: 2026-05-31
**Branch**: `feat/iter-2-containerize`
**Iteration plan reference**: [docs/iteration-plan.md § Iteration 2](../iteration-plan.md)

---

## Goal

An ARM64 Docker image that runs the hello HTTP server locally — multi-stage build, non-root user, `/ping` healthcheck. No Terraform, no AWS calls.

---

## Prompts used

Verbatim (or close paraphrase) of the prompts sent to Claude during this iteration. Order matters — they tell the story.

1. **Prompt**: `understand this project and work on next iteration`
   **Why**: Orient on project state, identify Iteration 2 (Containerize) as next, and scaffold it.

2. **Prompt**: `/iter-start 2 "containerize"`
   **Why**: Scaffold the branch and prompt log for iteration 2.

> Tip: if a prompt was a follow-up correction ("no don't do X, do Y"), include it — the corrections are usually more instructive than the original prompt.

---

## Decisions made

Non-obvious choices made during this iteration, with reasoning. Things a future reader would want to know.

- **Decision**: Node-based `HEALTHCHECK` (`node -e "fetch(...)"`) instead of the `wget -qO- .../ping` shown in [docs/03-agent-code.md](../03-agent-code.md).
  **Alternatives considered**: (a) keep `wget` and `apt-get install wget` in the runtime stage; (b) use `curl`.
  **Why**: `node:20-bookworm-slim` ships `node` but **not** `wget` or `curl` — the doc's healthcheck made the container report `unhealthy` (verified: `command -v wget` → `NO_WGET`). Node 20 has a global `fetch`, so the check needs zero extra packages and keeps the image slim, honoring CLAUDE.md's minimal-deps rule. **Doc discrepancy flagged** — `docs/03-agent-code.md` Dockerfile should be updated in a docs pass.

- **Decision**: Used the canonical Dockerfile from [docs/03-agent-code.md](../03-agent-code.md) verbatim except for the healthcheck.
  **Alternatives considered**: writing a leaner single-purpose Dockerfile.
  **Why**: The doc is the project's locked reference; matching it keeps iter 3+ (ECR push) aligned with documented expectations.

---

## Files created / modified

| File | Action | Notes |
|------|--------|-------|
| `docs/prompts/iter-2.md` | added | This prompt log |
| `Dockerfile` | added | Multi-stage ARM64 build |

---

## Tests

Per the iteration plan's Test phase. Record actual results, not expected.

- [x] `docker buildx build --platform linux/arm64 -t agent:local --load .` → build DONE, `npm ci` 124 pkgs / 0 vulnerabilities, image `agent:local` created
- [x] `docker run -d -p 8080:8080 agent:local` → server starts, `listening on :8080`
- [x] `curl localhost:8080/ping` → `{"status":"ok"}` (200)
- [x] `curl -X POST localhost:8080/invocations -d '{"prompt":"x"}'` → `{"result":"hello"}` (200)
- [x] `docker image inspect agent:local --format '{{.Architecture}}/{{.Os}}'` → `arm64/linux`
- [x] `docker inspect ... .State.Health.Status` → `healthy` (exit=0) within ~10s (after switching wget → node healthcheck)

---

## Forward-compatibility check

How does this iteration leave room for future iterations? Anything that should NOT be hardened or removed because a later iteration depends on it staying flexible.

- No AWS region, model ID, or account ID baked into the image — all config via env vars so the same image ships to any region/runtime (iter 3+).
- `PORT` read from env; defaults to 8080.

---

## Open questions / follow-ups

Things that came up but weren't in scope for this iteration. Move to a future iteration or a separate ticket.

- [ ] Update `docs/03-agent-code.md` Dockerfile to use the node-based healthcheck (wget is not in `node:20-bookworm-slim`).

---

## Rollback

How to undo this iteration if needed.

- Delete the `Dockerfile`.
