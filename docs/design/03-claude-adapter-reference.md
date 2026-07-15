# Design 03 — Claude Adapter (reference projection)

Status: **Draft for review** · Depends on: [01 Workflow Schema v2](01-workflow-schema-v2.md), [02 Gate Engine](02-gate-engine-contract.md)

## Purpose

The Claude Code adapter is the **reference projection**: it turns a `workflow.yaml` into Claude Code config. It is first because Claude's hook contract is the de-facto standard that **Codex, Kimi, Grok, and Copilot reuse** — two of them (Grok, Copilot-in-VS-Code) read `.claude/settings.json` *directly*. Getting this adapter right gives us five harnesses for roughly the price of one.

> ⚠️ **Verify before shipping.** Exact hook event names, the `permissions` deny specifier syntax, and `${CLAUDE_PROJECT_DIR}` expansion should be re-confirmed against current Claude Code docs at implementation time (see [enforcement matrix memory], verified 2026-07-15). The *shape* below is the target.

## What the adapter emits

| File | Layer | From |
|---|---|---|
| `AGENTS.md` | guidance (universal) | `steps` + `description` — **shared renderer**, not Claude-specific |
| `.claude/settings.json` (`hooks` + `permissions`) | enforcement | `gates` where `on` ∈ {`pre-tool`, `stop`} and `forbid` gates |
| `.workflow/hooks/gate.ps1` | enforcement shim | fixed template; calls `Invoke-WayforgeGate` |
| `.claude/commands/{plan,build,gate}.md` | ergonomics (optional) | `steps` |

The adapter only consumes gate stages Claude can enforce (`pre-tool`, `stop`). `pre-commit`/`pre-push`/`ci` gates are ignored here — they belong to the git and CI adapters. Same gate list, different filter.

## Stage → Claude event mapping

| Gate `on:` | Claude hook event | Matcher |
|---|---|---|
| `pre-tool` | `PreToolUse` | `Edit\|Write\|MultiEdit\|Bash` (union of tools the gates guard) |
| `stop` | `Stop` | — (forces another pass before finishing) |
| `forbid` (any) | `permissions.deny` **and** `PreToolUse` | fail-closed rule + best-effort hook |

## `.claude/settings.json` (generated)

```json
{
  "permissions": {
    "deny": [
      "Edit(**/.env)",
      "Edit(**/.env.*)",
      "Write(**/.env)",
      "Write(**/.env.*)"
    ]
  },
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Edit|Write|MultiEdit|Bash",
        "hooks": [
          {
            "type": "command",
            "command": "pwsh -NoProfile -File \"${CLAUDE_PROJECT_DIR}/.workflow/hooks/gate.ps1\" -Stage pre-tool -AsHook claude"
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "pwsh -NoProfile -File \"${CLAUDE_PROJECT_DIR}/.workflow/hooks/gate.ps1\" -Stage stop -AsHook claude"
          }
        ]
      }
    ]
  }
}
```

- `permissions.deny` projects `forbid` gates as **fail-closed** rules (no script, no fail-open window) — this is why `no-edit-dotenv` appears here *and* in the hook.
- The `PreToolUse` matcher is the union of tools referenced by the stage's gates, so we only intercept relevant calls.
- `.claude/settings.json` is **committed** (team-shared, project scope). Never write `.claude/settings.local.json` (that's the user's gitignored space).

## The gate shim — `.workflow/hooks/gate.ps1`

Fixed template, harness-agnostic except the `-AsHook` value passed in the command. **This same script is what Codex/Kimi/Grok/Copilot invoke** — only their config wrapper differs.

```powershell
#requires -Version 7.3
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('pre-tool','stop','pre-commit','pre-push','ci')]
    [string] $Stage,
    [string] $AsHook = 'claude'
)

# Harness event payload arrives on stdin for pre-tool/stop.
$eventJson = if ([Console]::In.Peek() -ge 0) { [Console]::In.ReadToEnd() } else { $null }

Import-Module PSWayforge -ErrorAction Stop     # or dot-source a pinned/vendored copy

$report = Invoke-WayforgeGate -Stage $Stage -AsHook $AsHook -EventJson $eventJson
exit $report.ExitCode                          # 2 = deny (harness), 0 = proceed
```

Fail-open safety (per [02]) lives inside `Invoke-WayforgeGate`: it always emits well-formed dialect output and a sane exit code even on internal error, so the shim never needs its own `try/catch`.

## Slash commands (optional ergonomics)

`.claude/commands/plan.md` — makes `/plan` run the plan step's intent. Advisory (prompt text, not a gate), but improves cooperation so the agent naturally produces `plan.json` before the `plan-before-build` gate ever fires.

```markdown
---
description: Produce plan.json for the current task
---
Read AGENTS.md and the scout report, then write an approach and acceptance
criteria to `.workflow/artifacts/plan.json` matching the `plan` schema.
```

## How the other four hook-compatible harnesses reuse this

The gate **script** (`gate.ps1`) and the **engine** are identical. Only the *config wrapper that registers it* changes:

| Harness | Config file the adapter writes | Registration delta vs Claude |
|---|---|---|
| **Codex** | `.codex/hooks.json` (or `[hooks]` in `config.toml`) | Same events/dialect; TOML/JSON wrapper. Doc the `/hooks` trust step. |
| **Kimi** | `~/.kimi-code/config.toml` `[[hooks]]` + `[[permission.rules]]` | TOML wrapper; `forbid` → `[[permission.rules]] deny` (fail-closed). |
| **Grok** | `.grok/hooks/*.json` + `[permission]` in `.grok/config.toml` | Dedicated config (decided — no silent reuse of `.claude/`). Same dialect; doc `--trust`. |
| **Copilot** | `.github/hooks/*.json` (+ VS Code reads `.claude/settings.json`) | `.github/` home; same dialect. |
| **Cursor** | `.cursor/hooks.json` | Same idea, **different dialect** (`permission`/`agent_message`) → `-AsHook cursor`. CLI: only `beforeShellExecution` fires, which still covers the commit path. |

`opencode` and `pi` are the genuine outliers — they need a small JS/TS shim that shells out to `gate.ps1` (or `Invoke-WayforgeGate`) and maps our `{"decision":"deny"}` to `throw` / `{block:true}`. Covered in a later adapter doc.

## Install / trust notes

- After emitting config, the agent may need a one-time trust grant depending on harness (Claude generally trusts project `.claude/settings.json`; Codex `/hooks`, Grok `--trust`). The adapter should **print the exact trust command** for the target so enforcement doesn't silently no-op.
- `.workflow/hooks/gate.ps1` requires `pwsh` (7.3+) on PATH and `PSWayforge` importable (installed module or vendored copy). The shim fails loudly with an install hint if not — never half-works.

## Why this stays honest about enforcement

Claude hooks (like all harness hooks) are **best-effort**: bypassable via `--dangerously-bypass-*` flags, and `permissions.deny` only binds an agent that honors it. The **durable guarantee is still the git/CI floor** running the *same* `Invoke-WayforgeGate`. This adapter buys excellent mid-session UX and early correction; it does not replace the floor.

## Open questions (please mark up)

1. **Emit `.claude/commands/*` by default**, or only with an opt-in flag?
2. **`permissions.deny` specifier syntax** — confirm `Tool(glob)` form and whether globs are path- or gitignore-style before generating.

*Decided:* Grok gets a **dedicated `.grok/` config** (no silent reuse of `.claude/settings.json`).
