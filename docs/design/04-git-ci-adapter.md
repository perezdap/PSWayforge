# Design 04 — Git + CI Adapter (the fail-closed floor)

Status: **Draft for review** · Depends on: [01 Workflow Schema v2](01-workflow-schema-v2.md), [02 Gate Engine](02-gate-engine-contract.md)

## Purpose

Project gates whose `on` includes `pre-commit`, `pre-push`, or `ci` into **local git hooks** and a **CI required check**. This is the layer that actually *guarantees* outcomes.

Harness hooks ([03]) are best-effort: they fail **open** (crash/timeout → action proceeds), require per-clone trust grants, and are bypassable via `--dangerously-bypass-*`. Git and CI are different: they honor the engine's **exit code unconditionally**, and a CI required check runs **server-side**, where no client flag can reach it. Same `Invoke-WayforgeGate`, but here it has teeth.

## What the adapter emits

| File | Layer | From gates where `on` includes |
|---|---|---|
| `.workflow/githooks/pre-commit` | local hook shim | `pre-commit` |
| `.workflow/githooks/pre-push` | local hook shim | `pre-push` |
| `.github/workflows/wayforge-gate.yml` | CI required check | `ci` |
| *(config)* `core.hooksPath = .workflow/githooks` | set by `Register-WayforgeHooks` | — |

Same gate list as every other adapter; this one just filters to the three git/CI stages. No gate is authored twice.

## Local git hooks

Git runs hooks through `sh` on **all** platforms (Git for Windows bundles `sh`), so the shims are POSIX `sh` and defer to the same `gate.ps1` from [03] — one gate implementation, every stage.

```sh
#!/bin/sh
# .workflow/githooks/pre-commit  (pre-push is identical with -Stage pre-push)
root=$(git rev-parse --show-toplevel)
exec pwsh -NoProfile -File "$root/.workflow/hooks/gate.ps1" -Stage pre-commit -AsHook git
```

- **stdin by stage:** `pre-commit` has no stdin; `pre-push` receives `<localref> <localsha> <remoteref> <remotesha>` lines. `exec` preserves stdin, so the engine's per-stage changeset derivation ([02]) reads the ref lines for `pre-push`. The engine interprets stdin by stage (JSON for `pre-tool`/`stop`, ref lines for `pre-push`, nothing for `pre-commit`) — `gate.ps1` is unchanged.
- **`-AsHook git`** → human-readable report to stderr, exit `0` (proceed) / `1` (abort). Nonzero aborts the commit/push.

### Installation & portability

- **`.git/hooks/` is not cloned.** That's why hooks live in a *tracked* directory and we point git at it: `git config core.hooksPath .workflow/githooks`. This is **per-clone local config** — `New-WayforgeProject` sets it automatically after `git init`; anyone else cloning runs `Register-WayforgeHooks` (or a documented one-liner). Loud reminder in `AGENTS.md`.
- **Executable bit:** Windows doesn't track it, but Unix clones need it. Commit the shims executable: `git add --chmod=+x .workflow/githooks/*`. `Register-WayforgeHooks` handles/reminds.
- **Dependencies:** `pwsh` 7.3+ on PATH, `PSWayforge` importable, plus each gate's external tools (gitleaks, semgrep, Pester…). Missing → **fail loudly with an install hint**, never half-work (same principle as the YAML fallback).

## CI workflow (the actual wall)

```yaml
name: wayforge-gate
on:
  pull_request:
jobs:
  gate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0                       # full history for base...HEAD diff
      - name: Install gate dependencies
        shell: pwsh
        run: |
          Install-Module PSWayforge, powershell-yaml -Force -Scope CurrentUser
          # + gitleaks / semgrep etc. as this workflow's gates require
      - name: Run Wayforge gate
        shell: pwsh
        env:
          WAYFORGE_BASE_REF: ${{ github.event.pull_request.base.ref }}
        run: |
          $report = Invoke-WayforgeGate -Stage ci -AsHook ci
          exit $report.ExitCode
```

- **Changeset:** `ci` stage diffs `base...HEAD` using `WAYFORGE_BASE_REF`; `fetch-depth: 0` is required for the base to be reachable.
- `pwsh` is preinstalled on GitHub-hosted runners (ubuntu/windows/macos).
- The job failing **is** the required check failing.

## Making it truly unbypassable

- **Local hooks are bypassable** — `git commit --no-verify`, `git push --no-verify`. They are fast feedback, not the wall.
- **The wall is branch protection + a required status check.** The PR cannot merge until `wayforge-gate` passes. `--no-verify` is a client flag with no power over the server.
- **Scaffolding the workflow file does not enable branch protection** — that's a repo setting. The adapter can optionally configure it (with consent, needs admin + a remote):
  ```
  gh api -X PUT repos/{owner}/{repo}/branches/{branch}/protection \
    -f required_status_checks[contexts][]=wayforge-gate ...
  ```
- **Advanced / self-hosted:** a server-side `pre-receive` hook running the same engine is unbypassable even without CI — note as an option for teams on self-managed git.

## Parity guarantee

Local hooks and CI call the **identical** `Invoke-WayforgeGate`. A gate that blocks locally blocks in CI and vice versa — no drift between "what the developer sees" and "what the merge enforces." Local = fast and courteous; CI = authoritative. Together with the harness layer ([03]), the same gate definition is enforced at three moments — mid-session, at commit, at merge — from one file.

## Open questions (please mark up)

1. **External-tool deps** (gitleaks/semgrep/Pester) — introduce a `requirements:` manifest in `workflow.yaml` that both the CI install step and a local `wayforge doctor` consume, or leave install to the user?
2. **CI provider** — ship GitHub Actions first; add GitLab CI / Azure Pipelines templates later, or emit a provider-agnostic script the user wires into any CI?
3. **Branch protection** — offer to auto-configure via `gh` (with consent) during scaffolding, or always leave it to the user?
4. **`pre-push` cost** — run heavy gates (full tests) at `pre-push` *and* `ci` (may double-run — see [02] caching question), or keep heavy checks CI-only so pushes stay fast?
