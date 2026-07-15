# Design 01 — Workflow Schema v2 (`gates`)

Status: **Draft for review** · Depends on: none · Consumed by: [02 Gate Engine](02-gate-engine-contract.md), [03 Claude Adapter](03-claude-adapter-reference.md)

## Purpose

Extend the workflow definition so a single file is the **one source of truth** for both:

- the **narrative process** an agent should follow (`steps`) — projected into `AGENTS.md` as *guidance*, and
- the **enforced invariants** (`gates`) — projected into harness hooks, git hooks, and CI as *enforcement*.

Everything downstream (`Invoke-WayforgeGate`, every harness adapter, the git floor) reads this file and nothing else.

## Design principles

1. **Invariant model, not a positional state machine.** There is no `state.json` pointer that says "we are in `build`." A gate asserts a condition against the *current changeset* (the git index / the tool being called). "Plan before build" is expressed as *"if code is staged, `plan.json` must exist and validate"* — derivable from ground truth, impossible to desync.
2. **One gate, many stages.** A gate declares which stages it applies to (`on:`). The same invariant can be checked mid-session (harness `pre-tool`), at commit (`pre-commit`), and in CI (`ci`). Each adapter consumes only the stages it can enforce.
3. **Fail-closed where it matters.** `forbid` guardrails project to native declarative deny-rules (fail-closed) on harnesses that support them; `run`/`requires_artifact` gates project to hook scripts (best-effort) plus the git/CI floor (fail-closed).

## Annotated example

```yaml
apiVersion: wayforge/v2
name: default
description: Scout → plan → build with a security + quality gate.

# Reusable file-glob sets referenced by `when:` predicates.
scopes:
  code:  ["**/*.ps1", "**/*.psm1", "**/*.cs", "**/*.ts", "src/**"]
  docs:  ["**/*.md", "docs/**"]
  infra: ["**/*.tf", ".github/workflows/**"]

# ── Narrative process (guidance) → rendered into AGENTS.md ──────────────
steps:
  - id: scout
    name: Scout Context
    description: Read AGENTS.md, skills, and existing code.
    outputs:
      - artifact: scout-report.json
        schema: scout
  - id: plan
    name: Plan
    description: Produce an approach + acceptance criteria.
    inputs:
      - artifact: scout-report.json
        schema: scout
    outputs:
      - artifact: plan.json
        schema: plan
  - id: build
    name: Build
    description: Implement the plan; keep artifacts valid.
    inputs:
      - artifact: plan.json
        schema: plan

# ── Enforced invariants (enforcement) → hooks + git + CI ───────────────
gates:
  - id: no-secrets
    description: Staged content must contain no secrets.
    on: [pre-tool, pre-commit, ci]
    when: always
    severity: block
    check:
      run: gitleaks protect --staged --no-banner --redact
      shell: native          # invoke the binary directly, no shell wrapper

  - id: no-edit-dotenv
    description: Never write to .env files.
    on: [pre-tool, pre-commit]
    when: always
    severity: block
    check:
      forbid: { tool: [edit, write], path: ["**/.env", "**/.env.*"] }

  - id: plan-before-build
    description: Code changes require an approved, valid plan.
    on: [pre-tool, pre-commit]
    when: changes_touch(code)
    severity: block
    check:
      requires_artifact: plan.json
      schema: plan

  - id: tests-pass
    description: Test suite must pass before code is pushed/merged.
    on: [pre-push, ci]
    when: changes_touch(code)
    severity: block
    check:
      run: Invoke-Pester -CI -Path ./tests
      shell: pwsh

  - id: lint
    description: Formatting/style (advisory).
    on: [pre-commit]
    when: changes_touch(code)
    severity: warn
    check:
      run: pwsh -NoProfile -File ./scripts/lint.ps1

on_complete:
  - hook: done
```

## Field reference

### Top level
| Field | Req | Notes |
|---|---|---|
| `apiVersion` | ✅ | `wayforge/v2`. Presence of this string selects the v2 parser; files without it parse as legacy v1. |
| `name` | ✅ | Workflow id (matches `.workflow/definitions/<name>.yaml`). |
| `description` | – | One line; flows into `AGENTS.md`. |
| `scopes` | – | Map of name → glob list, referenced by `when:` predicates. |
| `steps` | – | Narrative process (unchanged from v1, still supported). |
| `gates` | – | Enforced invariants (new). |
| `on_complete` | – | Terminal hooks (unchanged). |

### `gates[]`
| Field | Req | Values |
|---|---|---|
| `id` | ✅ | kebab-case, unique. Shown in block messages. |
| `description` | ✅ | Human reason; surfaced to the agent when denied. |
| `on` | ✅ | Subset of the **stage enum** below. |
| `when` | – | Predicate (default `always`). |
| `severity` | – | `block` (default) or `warn`. |
| `check` | ✅ | Exactly one check kind (below). |

### Stage enum (`on`)
| Stage | Fires | Enforced by |
|---|---|---|
| `pre-tool` | before a harness tool call (mid-session) | harness `PreToolUse` hook (best-effort) |
| `stop` | when the agent tries to finish | harness `Stop` hook (forces another pass) |
| `pre-commit` | `git commit` | git hook (`core.hooksPath`) |
| `pre-push` | `git push` | git hook |
| `ci` | pull request / branch build | CI required check (**unbypassable floor**) |

### `check` kinds (exactly one)
| Kind | Shape | Pass condition |
|---|---|---|
| `run` | `run: <command string>` + optional `shell: <pwsh\|sh\|native>` (default `pwsh`) | command exits `0` |
| `requires_artifact` | `requires_artifact: <name>` + optional `schema: <name>` | artifact exists in `.workflow/artifacts/` **and** validates via `Test-WayforgeSchema` |
| `forbid` | `forbid: { tool: [..], path: [..], command: [..] }` | the staged change / tool call matches **no** forbidden pattern |

`forbid` is the only check that also projects to **native declarative deny-rules** (fail-closed) on harnesses that support them; `run`/`requires_artifact` project to hook scripts + git/CI.

### `when` predicates
| Predicate | True when |
|---|---|
| `always` | always |
| `changes_touch(<scope>)` | changeset intersects the named scope's globs |
| `changes_only(<scope>)` | changeset is a subset of the scope (e.g. docs-only commit) |

Predicates are pure functions of the changeset — no stored phase. For `pre-tool`, the "changeset" is the tool's target (the file/command in the event payload).

## Evaluation semantics

- For a given stage, the engine selects gates whose `on` includes it, evaluates `when`, skips if false, runs `check`.
- Declaration order is preserved; the engine may front-load cheap checks (secrets, artifact presence) before expensive `run` gates.
- **Aggregate result:** the operation is blocked if **any** `severity: block` gate fails. `warn` failures print but never block.

## Projection preview (how one file fans out)

```
gates[*].on = pre-tool ─┐
              stop ──────┼─► harness adapters (Claude/Codex/Kimi/Grok/Copilot/Cursor/opencode/pi)
gates[*].on = pre-commit ┐
              pre-push ───┼─► git adapter  (.workflow/githooks/* via core.hooksPath)
gates[*].on = ci ─────────┴─► CI adapter   (.github/workflows/wayforge-gate.yml)
steps[*], description ────► AGENTS.md renderer (universal guidance, all harnesses)
```

## Decisions

- **Artifact location** — `.workflow/artifacts/<name>`, checked against the working tree (gitignored is fine).
- **`run` shell** — per-gate `shell:` field (`pwsh` default; `sh` / `native` available) for cross-platform explicitness.

## Open questions (please mark up)

1. **Predicate surface** — is `always` / `changes_touch` / `changes_only` enough for v2, or do we need `any_of` / `not`?
2. **Legacy v1** — keep parsing indefinitely, or emit a deprecation warning and a `Convert-WayforgeWorkflow` upgrader?
