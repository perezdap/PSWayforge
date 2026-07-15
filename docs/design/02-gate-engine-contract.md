# Design 02 — Gate Engine Contract (`Invoke-WayforgeGate`)

Status: **Draft for review** · Depends on: [01 Workflow Schema v2](01-workflow-schema-v2.md) · Consumed by: [03 Claude Adapter](03-claude-adapter-reference.md), git adapter, CI adapter

## Purpose

One function evaluates the workflow's `gates` for a given stage and reports pass/block. Every enforcement point — harness hooks, the git pre-commit/pre-push hooks, and CI — calls **the same engine**; only the thin *output serialization* differs per caller. This is what lets one gate script serve five hook-compatible harnesses plus git plus CI.

> **Naming.** The engine cmdlet is `Invoke-WayforgeGate` (it *does work* and produces a report — `Invoke-`, not `Test-`). A convenience `Test-WayforgeGate` returning `[bool]` may wrap it for scripting, but the shims call `Invoke-WayforgeGate`.

## Signature

```powershell
Invoke-WayforgeGate
    -Stage       <pre-tool|stop|pre-commit|pre-push|ci>   # required
    [-AsHook     <claude|codex|kimi|grok|copilot|cursor|opencode|pi|git|ci>]
    [-EventJson  <string>]          # harness event payload (pre-tool/stop), from stdin
    [-ProjectPath <string>]         # default: git toplevel of cwd
    [-WorkflowName <string>]        # default: every definition in .workflow/definitions
    [-ChangeSet  <string[]>]        # override; else derived from git per stage
    -> [PSWayforge.GateReport]
```

- Without `-AsHook`, returns the report object and writes a human-readable summary (for CLI/CI logs).
- With `-AsHook <target>`, additionally writes the **target's dialect** to stdout and sets `$report.ExitCode` so the calling shim can `exit` with it.

## Changeset derivation (per stage)

| Stage | Changeset source |
|---|---|
| `pre-commit` | `git diff --cached --name-only` |
| `pre-push` | files in the pushed range (refs on stdin → `git diff --name-only <remote>..<local>`) |
| `ci` | `git diff --name-only <base>...HEAD` (base = target branch), or full tree if base unknown |
| `pre-tool` / `stop` | from `-EventJson`: the tool name + target path/command; working tree if none |

## Evaluation algorithm

```
root      = Resolve git toplevel (ProjectPath)
defs      = load workflow definition(s)  (v2 parser)
gates     = defs.gates where Stage ∈ gate.on
changeset = derive(Stage, EventJson, git)
results   = []
foreach gate in gates (declaration order, cheap checks first):
    if not predicate(gate.when, changeset): results += SKIP; continue
    switch gate.check:
      run:               ok = (exit code of `command` in shell(gate.check.shell ?? pwsh) == 0)
      requires_artifact: ok = exists(.workflow/artifacts/<name>) AND
                              Test-WayforgeSchema -Artifact <path> -SchemaName <schema>
      forbid:            ok = changeset/tool-target matches NO forbidden pattern
    results += (gate.id, gate.severity, ok ? PASS : (severity==warn ? WARN : FAIL), message)
blocked  = any(r.status == FAIL)          # block-severity failures only
report   = GateReport{ Stage, Blocked, Results, ExitCode = translate(AsHook, blocked) }
```

## `PSWayforge.GateReport` shape

```
Stage      : string
Blocked    : bool          # any block-severity gate failed
ExitCode   : int           # what the shim should exit with (see dialects)
Results    : GateResult[]
  .Id        : string
  .Severity  : block|warn
  .Status    : pass|fail|warn|skip
  .Message   : string      # gate.description + specifics; shown to agent on deny
  .Detail    : string      # command output / validation error (verbose)
```

## Output dialects (`-AsHook`) — the interop contract

The **core evaluation is identical**; only these serializers differ. This table *is* the reuse boundary.

| Target | On block: stdout | Exit code | Notes |
|---|---|---|---|
| `claude`, `codex`, `kimi`, `grok`, `copilot` | `{"hookSpecificOutput":{"hookEventName":"<evt>","permissionDecision":"deny","permissionDecisionReason":"<msg>"}}` | `2` | The de-facto standard dialect. Emit JSON **and** exit 2 (some tools key on one, some the other; fail-open tools need explicit deny). |
| `cursor` | `{"permission":"deny","user_message":"<msg>","agent_message":"<msg>"}` | `2` | Cursor uses different field names. `beforeSubmitPrompt` uses `{"continue":false}`. |
| `opencode` | `{"decision":"deny","reason":"<msg>"}` (our shape) | `2` | Consumed by the plugin shim → `throw` / `permission.ask` deny. |
| `pi` | `{"decision":"deny","reason":"<msg>"}` (our shape) | `2` | Consumed by the extension shim → `return {block:true, reason}`. |
| `git` | human-readable report to **stderr** | `0` pass / `1` block | Nonzero aborts the commit/push. |
| `ci` | markdown report to stdout | `0` pass / `1` block | Fails the required check. |

On **pass**: exit `0`, no deny JSON (silence ≠ approve on hook-compatible harnesses — we never *implicitly allow*, we simply don't object, so the harness's normal permission flow continues).

## Artifact resolution

- `requires_artifact: plan.json` → `.<root>/.workflow/artifacts/plan.json`.
- Presence is checked against the **working tree** (not the index), so an agent that just wrote `plan.json` satisfies the gate even before staging it.
- Validity reuses the existing `Test-WayforgeSchema` against `.workflow/schemas/<schema>.json`.

## Error handling & the fail-open reality

Harness hooks **fail open** (a crash/timeout/malformed output lets the action proceed). The engine therefore:

1. **Always emits well-formed output** — a `try/catch` around evaluation guarantees the dialect serializer runs even on internal error.
2. On internal error for a `block`-severity gate, defaults to **deny within our control** (emit deny + exit 2) — we fail closed as far as the harness will honor.
3. Never throws out of the shim; the shim's last line is `exit $report.ExitCode`.
4. Because hooks are ultimately bypassable, **the git pre-commit + CI required-check remain the fail-closed guarantee** — the engine is identical there, but git/CI honor our exit code unconditionally.

## Worked examples

**Mid-session, agent tries to edit code with no plan:**
```
stdin: {"hook_event_name":"PreToolUse","tool_name":"Edit","tool_input":{"file_path":"src/auth.ps1"}}
Invoke-WayforgeGate -Stage pre-tool -AsHook claude -EventJson <stdin>
→ gate plan-before-build: changes_touch(code)=true, plan.json missing → FAIL
→ stdout {"hookSpecificOutput":{"permissionDecision":"deny","permissionDecisionReason":"plan-before-build: Code changes require an approved, valid plan (.workflow/artifacts/plan.json)."}}
→ exit 2   # Claude blocks the Edit
```

**Commit gate, docs-only change:**
```
git diff --cached --name-only → README.md
Invoke-WayforgeGate -Stage pre-commit -AsHook git
→ plan-before-build: changes_touch(code)=false → SKIP
→ no-secrets: PASS
→ exit 0   # commit proceeds
```

## Open questions (please mark up)

1. **`-WorkflowName` default** — evaluate *all* definitions, or a single active one? (Multiple workflows → union of gates; is that desired?)
2. **`run` timeout** — global default (e.g. 60s pre-commit) with per-gate override?
3. **Caching** — memoize expensive `run` gates (tests) by tree hash within a stage to avoid double-runs across pre-push and CI?
4. **`Test-WayforgeGate` bool wrapper** — ship it, or is `Invoke-WayforgeGate` + `.Blocked` enough?
