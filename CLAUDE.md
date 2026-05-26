# agentcore-solution1 — Claude project guide

> **Read this file at the start of every session.** It defines how this project works and the conventions you must follow.

---

## Mission

Deploy a TypeScript Strands agent to **Amazon Bedrock AgentCore Runtime**. Forward-compatible with future agent projects.

---

## Tech stack (locked)

- **Node.js 20+** (ARM64 target — AgentCore requirement)
- **TypeScript 5.4+** with `"type": "module"` and `NodeNext` resolution
- **Strands Agents SDK** for the agent framework
- **Express** for the HTTP entrypoint on port `8080`
- **Docker buildx** for ARM64 container builds
- **Amazon ECR + Bedrock AgentCore Runtime + Gateway**
- **Terraform 1.6+** with AWS provider `>= 5.70.0`

Do not introduce alternatives without asking (no Python, no CDK, no Lambda packaging, no CommonJS).

---

## How we work — iteration model

This project is built iteratively. The roadmap lives in [docs/iteration-plan.md](docs/iteration-plan.md) — 12 iterations, each with **Design → Develop → Test → Deploy → Rollback** phases.

**Always at the start of an iteration**: re-read the relevant section of [docs/iteration-plan.md](docs/iteration-plan.md) before writing any code.

**Operating principles** (enforced):
- **Additive only** — never delete or rename a working feature in the same iteration that adds a new one.
- **Forward-compatible** — new iterations must not require old ones to change. Use optional env vars and feature flags.
- **Always green** — every iteration ends with `/ping` returning 200 and `/invocations` returning a valid response, even if the body is a stub.
- **Reversible** — every iteration has a documented rollback (Terraform target destroy, image tag revert, env var flip).
- **One concern per iteration** — if tempted to bundle, split.

---

## Tracking convention (mandatory)

**Every iteration produces three artifacts in lockstep:**

1. **[CHANGELOG.md](CHANGELOG.md)** — append a new entry per iteration. Never edit past entries; append follow-up entries instead. Format is shown at the top of CHANGELOG.md itself.
2. **[docs/prompts/iter-N.md](docs/prompts/)** — verbatim prompts used, decisions made (with alternatives), files touched, **actual** test results, forward-compatibility notes, rollback. Template: [docs/prompts/_template.md](docs/prompts/_template.md).
3. **Structured git commit** — message format:
   ```
   iter-N: <title>

   Prompts: docs/prompts/iter-N.md
   Iteration: N
   Tests: <one-line summary>
   ```

Use the slash commands to keep this on rails:
- **`/iter-start N "title"`** — scaffolds branch + `iter-N.md`
- **`/iter-end`** — finalizes the log, appends CHANGELOG, drafts the commit message

Branch name: `feat/iter-N-<slug>`.

---

## Conventions you must follow

- **No ESLint / Prettier** yet (intentional — keep deps minimal until a later iteration asks for them).
- **ESM-first**: `"type": "module"` + NodeNext. No CommonJS.
- **ARM64 only** for Docker images. Always build with `--platform linux/arm64`.
- **No hardcoded secrets, regions, account IDs, or model IDs** — read everything from env vars or Terraform variables.
- **Don't run** `terraform apply`, `terraform destroy`, `docker push`, `git push`, or `git commit` **without confirming with the user**. Apply pre-approvals from `.claude/settings.json` are for *safe, idempotent* commands only.
- **No `--no-verify`**, no `--force` on git operations, no skipping hooks — ever, unless the user explicitly says so.
- **Don't add comments** that just describe what code does. Only comment when the *why* is non-obvious.
- **Don't create new markdown docs** without being asked. The docs in `docs/` are deliberate and curated.

---

## Repository layout

```
agentcore-solution1/
├── CLAUDE.md                    ← you are here
├── AGENTS.md                    ← pointer to this file (tool-agnostic)
├── CHANGELOG.md                 ← human-readable history
├── README.md                    ← (not yet — added in a later iteration)
├── package.json, tsconfig.json
├── .gitignore, .dockerignore
├── .editorconfig, .nvmrc
├── .claude/
│   ├── settings.json            ← shared permissions
│   ├── commands/                ← /iter-start, /iter-end
├── .vscode/                     ← editor recommendations
├── src/                         ← agent code (grows per iteration)
├── infra/                       ← Terraform (added in Iter 3)
└── docs/
    ├── README.md                ← doc set entry point
    ├── 01..06-*.md              ← deployment guides
    ├── iteration-plan.md        ← 12-iteration roadmap
    └── prompts/                 ← prompt archive (one per iteration)
```

---

## Key documents (read these before code)

| Doc | When to read |
|-----|--------------|
| [docs/iteration-plan.md](docs/iteration-plan.md) | At the start of **every** iteration |
| [docs/README.md](docs/README.md) | First-time orientation |
| [docs/03-agent-code.md](docs/03-agent-code.md) | Iter 1–5 (agent code work) |
| [docs/04-terraform.md](docs/04-terraform.md) | Iter 3–7 (infrastructure work) |
| [docs/05-deployment.md](docs/05-deployment.md) | Iter 4+ (any deploy step) |
| [docs/06-migration.md](docs/06-migration.md) | Only if working on `strands-solution1` migration |

---

## When in doubt

- If a request seems to violate one of these conventions, **ask** before proceeding.
- If a convention seems wrong, **say so** — but don't silently break it.
- If a doc is out of date relative to the code, **flag it** rather than working around it.
