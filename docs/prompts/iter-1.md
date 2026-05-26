# Iter 1 — Hello HTTP Server

**Date**: 2026-05-26
**Branch**: `feat/iter-1-http-server`
**Iteration plan reference**: [docs/iteration-plan.md § Iteration 1](../iteration-plan.md)

---

## Goal

AgentCore-shaped HTTP server running locally on port 8080 with `GET /ping` and `POST /invocations` routes, no AWS calls.

---

## Prompts used

Verbatim (or close paraphrase) of the prompts sent to Claude during this iteration. Order matters — they tell the story.

1. **Prompt**: `/iter-start 1 "http server"`
   **Why**: Scaffold the branch and prompt log for iteration 1.

2. **Prompt**: `@"C:\Priyan\VSC\AI\strands-solution1" ready to go`
   **Why**: Referenced the sibling project before writing code, to avoid duplicating work already done. strands-solution1 turned out to be Lambda-based (no Express), so nothing to port — wrote from scratch.

---

## Decisions made

Non-obvious choices made during this iteration, with reasoning. Things a future reader would want to know.

- **Decision**: `"dev": "tsc && node dist/app.js"` (no `tsx` or `ts-node`)
  **Alternatives considered**: adding `tsx` as a dev dep for hot-reload
  **Why**: CLAUDE.md mandates minimal deps until a later iteration asks for them. `tsc` is already in devDeps; reusing it keeps the dep count low.

- **Decision**: Response shape `{result: string}` with room for `sessionId?` and `usage?` (not included yet)
  **Alternatives considered**: returning bare string
  **Why**: Iteration plan explicitly calls for defining the shape now so later iterations can fill fields without changing callers.

---

## Files created / modified

| File | Action | Notes |
|------|--------|-------|
| `docs/prompts/iter-1.md` | added | This prompt log |
| `package.json` | modified | Added `express` dep, `@types/express` devDep, `dev` script |
| `src/app.ts` | modified | Replaced `console.log("boot")` with Express server |

---

## Tests

Per the iteration plan's Test phase. Record actual results, not expected.

- [x] `npm run build` → clean compile, no errors
- [x] `node dist/app.js` → `listening on :8080`
- [x] `curl localhost:8080/ping` → `{"status":"ok"}` (200)
- [x] `curl -X POST localhost:8080/invocations -H "Content-Type: application/json" -d '{"prompt":"x"}'` → `{"result":"hello"}` (200)

---

## Forward-compatibility check

How does this iteration leave room for future iterations? Anything that should NOT be hardened or removed because a later iteration depends on it staying flexible.

- Response shape defined as `{result, sessionId?, usage?}` — later iterations fill in `sessionId` and `usage` without changing callers.
- Port read from `PORT` env var — container and runtime can override without code change.

---

## Open questions / follow-ups

Things that came up but weren't in scope for this iteration. Move to a future iteration or a separate ticket.

- [ ] Optional: add one Jest/vitest test for the route handler (iter 1 plan says "optional").

---

## Rollback

How to undo this iteration if needed.

- Delete `src/app.ts` and revert `package.json` to remove Express.
