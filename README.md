# PSWayforge

[![CI](https://github.com/perezdap/PSWayforge/actions/workflows/ci.yml/badge.svg)](https://github.com/perezdap/PSWayforge/actions/workflows/ci.yml)

A PowerShell module that turns one workflow definition into **enforced, agent-agnostic guardrails** across the coding agents you use.

Define a workflow once — the steps an agent should follow and the gates it must pass — and PSWayforge projects it into:

- **Guidance** every agent reads (`AGENTS.md`)
- **Mid-session hooks** for 8 harnesses that block disallowed actions before they run
- **A git commit floor** (`pre-commit` / `pre-push`) that no agent can skip
- **A CI merge floor** that runs the same gate, unbypassable server-side

One gate engine, evaluated at every moment: mid-session, at commit, at push, at merge.

## Install

```powershell
Install-Module PSWayforge
```

## Quick start

```powershell
# Scaffold a new enforced workspace, wiring every agent you have installed
New-WayforgeProject -Name MyApp -Path . -DetectHarness

# ...or add Wayforge to an existing repository, in place (non-destructive)
Initialize-WayforgeProject -DetectHarness
```

That creates a git repo where — for example — an agent (or a human) **cannot land code without a plan** and **cannot touch `.env`**, enforced through each agent's own hooks *and* the git hooks.

## Adding to an existing project

`Initialize-WayforgeProject` applies Wayforge to the current repository **in place** and non-destructively — existing files are preserved and each agent's config (e.g. `.claude/settings.json`) is *merged*, not overwritten:

```powershell
Initialize-WayforgeProject -DetectHarness        # wire every installed agent
# ...or choose specific harnesses:
Initialize-WayforgeProject -Harness claude,codex
```

Two things to know when applying it to an existing codebase:

- **The default gates enforce immediately.** The scaffolded `.workflow/definitions/default.yaml` requires a `plan.json` for code changes and forbids `.env` edits — so your next commit touching source without a plan will be blocked. The default `code` scope matches source files **by extension across any layout** (flat root, `cmd/`, `pkg/`, `src/`, …) while excluding Wayforge's own tree, so it works out of the box; open that file to narrow or extend it if you want.
- **After upgrading the module** (`Update-Module PSWayforge`), re-run `Sync-WayforgeHarness -Detect` inside the repo to regenerate each agent's config with the latest fixes.

## How it works

A workflow lives in `.workflow/definitions/*.yaml`:

```yaml
apiVersion: wayforge/v2
name: default
scopes:
  code: ["src/**", "public/**", "private/**"]
gates:
  - id: plan-before-build
    description: Code changes require an approved plan
    on: [pre-tool, pre-commit]
    when: changes_touch(code)
    severity: block
    check:
      requires_artifact: plan.json
      schema: plan
  - id: no-edit-dotenv
    on: [pre-tool, pre-commit, ci]
    when: always
    check:
      forbid:
        tool: [edit, write]
        path: ["**/.env"]
```

Gates assert conditions on the changeset (the git index is the state — no positional pointer to desync). `Invoke-WayforgeGate` is the single engine; each enforcement point calls it and only the output dialect differs. **Exit code 2 is the universal deny**, so a gate blocks on every harness even where each parses a different response shape.

## Supported harnesses

| Harness | Wired via |
|---|---|
| Claude Code | `.claude/settings.json` |
| OpenAI Codex CLI | `.codex/hooks.json` |
| Grok Build | `.grok/hooks/wayforge.json` |
| GitHub Copilot | `.github/hooks/wayforge.json` |
| Cursor (IDE + CLI) | `.cursor/hooks.json` |
| opencode | `.opencode/plugins/wayforge-gate.js` |
| pi | `.pi/extensions/wayforge-gate.ts` |
| Kimi Code | snippet for `~/.kimi-code/config.toml` (global-only) |

All share one `gate.ps1` shim. `Get-WayforgeHarness` detects what's installed; `Sync-WayforgeHarness -Detect` wires them.

## Commands

| Command | Purpose |
|---|---|
| `New-WayforgeProject` | Scaffold a new enforced workspace |
| `Initialize-WayforgeProject` | Apply Wayforge to an existing project, in place |
| `Invoke-WayforgeGate` | Evaluate a workflow's gates for a stage (the engine) |
| `Sync-WayforgeHarness` | Project gates into per-harness config |
| `Register-WayforgeHooks` | Install the git-hook floor (`core.hooksPath`) |
| `Register-WayforgeCI` | Generate the CI merge-gate workflow |
| `Get-WayforgeHarness` / `Select-WayforgeHarness` | Detect / choose harnesses |
| `Update-WayforgeAgentsFile` | Render the workflow's steps into a managed block in `AGENTS.md` |
| `Get-WayforgeWorkflow` / `Test-WayforgeSchema` / `Invoke-WayforgeHook` | Workflow, schema, and hook utilities |

## Requirements

- PowerShell 7.3+
- `git` on PATH (for the git/CI floor)
- `powershell-yaml` (optional; a minimal parser is used as a fallback)

## Design docs

See [`docs/design/`](docs/design/) for the workflow schema, gate engine contract, and adapter designs.

## License

[MIT](LICENSE)
