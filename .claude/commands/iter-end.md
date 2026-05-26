---
description: Finalize the current iteration — verify prompt log, append CHANGELOG, draft commit
allowed-tools: Bash, Read, Edit, Write
---

Finalize the current iteration.

## Steps (do these in order)

1. **Determine current iteration.**
   - Run `git rev-parse --abbrev-ref HEAD` to get the branch name.
   - Parse `feat/iter-<N>-<slug>`. If the branch doesn't match, stop and ask the user for the iteration number.

2. **Verify the prompt log is complete.** Open `docs/prompts/iter-<N>.md`. Check that every section has real content (not placeholder text):
   - Goal
   - Prompts used (at least one prompt logged)
   - Decisions made (or explicitly marked "none")
   - Files created / modified (with real file paths)
   - Tests — **every checkbox must have an actual command and actual output**, not `<...>` placeholders
   - Forward-compatibility check
   - Rollback

   If anything is empty or still has placeholders, list what's missing and stop. Do not proceed until the user fills them in.

3. **Append a CHANGELOG entry.** Add to [CHANGELOG.md](../../CHANGELOG.md), **at the bottom of the iteration list** (never edit a past entry). Use the established format:

   ```markdown
   ## [Iter <N>] — YYYY-MM-DD — <title>

   - Added / Changed / Removed: <files or features, concise>
   - Tests:
     - <test 1> → <result>
     - <test 2> → <result>
   - Prompt log: [docs/prompts/iter-<N>.md](docs/prompts/iter-<N>.md)
   - Rollback: <how to undo>
   - Forward-compatibility: <one line>
   ```

   Pull the content from `docs/prompts/iter-<N>.md`. Do not invent anything.

4. **Stage the changes.** Run `git status` and show the user. Stage only the iteration's intended files (do not blanket `git add -A`).

5. **Draft the commit message** in the required format:

   ```
   iter-<N>: <title>

   Prompts: docs/prompts/iter-<N>.md
   Iteration: <N>
   Tests: <one-line summary>
   ```

   Show the message to the user and **wait for explicit confirmation** before running `git commit`.

6. **After commit, do NOT push.** Print a reminder: "Push when ready with `git push -u origin feat/iter-<N>-<slug>`."

## Reminders (from CLAUDE.md)

- Never edit a past CHANGELOG entry. Append follow-ups instead.
- No `--no-verify`, no `--force`, no `--amend` unless the user explicitly asks.
- Commit messages use HEREDOC for multi-line bodies on PowerShell:
  ```powershell
  git commit -m @'
  iter-<N>: <title>

  Prompts: docs/prompts/iter-<N>.md
  Iteration: <N>
  Tests: ...
  '@
  ```
