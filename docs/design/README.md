# PSWayforge Design Docs

Reference designs for evolving PSWayforge from a scaffolder into a **multi-harness workflow-enforcement projector** — one workflow definition, projected into guidance + enforcement across every coding-agent harness, with a git/CI floor as the fail-closed guarantee.

| # | Doc | What it specifies |
|---|---|---|
| 01 | [Workflow Schema v2](01-workflow-schema-v2.md) | The `gates` block — one source of truth for process (`steps`) + enforced invariants (`gates`). Invariant model, stages, checks, predicates. |
| 02 | [Gate Engine Contract](02-gate-engine-contract.md) | `Invoke-WayforgeGate` — the single engine every enforcement point calls. Changeset derivation, evaluation, `GateReport`, and the per-harness output dialects (the reuse boundary). |
| 03 | [Claude Adapter](03-claude-adapter-reference.md) | The reference projection. `.claude/settings.json` hooks + `permissions`, the shared `gate.ps1` shim, and how Codex/Kimi/Grok/Copilot/Cursor reuse it. |
| 04 | [Git + CI Adapter](04-git-ci-adapter.md) | The fail-closed floor. Tracked `.workflow/githooks/` via `core.hooksPath`, the CI required check running the same engine, and how the merge wall becomes unbypassable. |

**Layering** (established): `AGENTS.md` (universal guidance) → per-harness hooks/deny-rules (mid-session, best-effort, fail-open) → **git pre-commit + CI required-check (fail-closed floor)**.

**Decided:** artifacts live in `.workflow/artifacts/`; gates take a per-gate `shell:` field (`pwsh` default); Grok gets a dedicated `.grok/` config.

**Not yet designed:** opencode/pi JS-TS shim adapter (05), the `Sync-WayforgeHarness` projector + harness detection/selection UX (06).

Status: all three are **drafts for review**. Each ends with an *Open questions* section to mark up before implementation.
