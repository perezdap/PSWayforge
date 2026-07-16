BeforeAll {
    $script:ModuleRoot = Split-Path -Parent $PSScriptRoot
    Import-Module -Name (Join-Path $ModuleRoot 'PSWayforge.psd1') -Force

    function New-HProject {
        param([string] $Path)
        New-Item -ItemType Directory -Path (Join-Path $Path '.workflow/definitions') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $Path '.workflow/schemas')     -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $Path '.workflow/artifacts')   -Force | Out-Null
        @'
apiVersion: wayforge/v2
name: default
scopes:
  code:
    - "src/**"
gates:
  - id: plan-before-build
    on:
      - pre-tool
    when: changes_touch(code)
    severity: block
    check:
      requires_artifact: plan.json
      schema: plan
  - id: no-edit-dotenv
    on:
      - pre-tool
    when: always
    severity: block
    check:
      forbid:
        tool:
          - edit
          - write
        path:
          - "**/.env"
  - id: no-force-push
    on:
      - pre-tool
    when: always
    severity: block
    check:
      forbid:
        command:
          - "git push --force*"
'@ | Set-Content (Join-Path $Path '.workflow/definitions/default.yaml') -Encoding utf8NoBOM
        @'
{ "$schema": "http://json-schema.org/draft-07/schema#", "type": "object",
  "required": ["summary"], "properties": { "summary": { "type": "string" } } }
'@ | Set-Content (Join-Path $Path '.workflow/schemas/plan.json') -Encoding utf8NoBOM
    }
}

AfterAll {
    Remove-Module -Name PSWayforge -Force -ErrorAction SilentlyContinue
}

Describe 'Sync-WayforgeHarness codex' {
    It 'writes .codex/hooks.json with a PreToolUse gate.ps1 hook' {
        $p = Join-Path $TestDrive 'codex'; New-HProject -Path $p
        Sync-WayforgeHarness -Harness codex -ProjectPath $p | Out-Null

        $f = Join-Path $p '.codex/hooks.json'; $f | Should -Exist
        $j = Get-Content $f -Raw | ConvertFrom-Json
        $j.hooks.PreToolUse[0].hooks[0].command | Should -Match 'gate\.ps1'
        $j.hooks.PreToolUse[0].hooks[0].command | Should -Match '-AsHook codex'
    }

    It 'merges into an existing .codex/hooks.json and is idempotent' {
        $p = Join-Path $TestDrive 'codexmerge'; New-HProject -Path $p
        New-Item -ItemType Directory -Path (Join-Path $p '.codex') -Force | Out-Null
        @'
{ "hooks": {
    "PreToolUse": [ { "matcher": "Read", "hooks": [ { "type": "command", "command": "echo hi" } ] } ],
    "SessionStart": [ { "hooks": [ { "type": "command", "command": "echo s" } ] } ] } }
'@ | Set-Content (Join-Path $p '.codex/hooks.json') -Encoding utf8NoBOM

        Sync-WayforgeHarness -Harness codex -ProjectPath $p | Out-Null
        Sync-WayforgeHarness -Harness codex -ProjectPath $p | Out-Null

        $j = Get-Content (Join-Path $p '.codex/hooks.json') -Raw | ConvertFrom-Json
        $j.hooks.SessionStart | Should -Not -BeNullOrEmpty                                          # unrelated event kept
        ($j.hooks.PreToolUse | Where-Object { $_.matcher -eq 'Read' }) | Should -Not -BeNullOrEmpty # user entry kept
        @($j.hooks.PreToolUse | Where-Object { ($_.hooks.command -join '') -match 'gate\.ps1' }).Count | Should -Be 1
    }
}

Describe 'Sync-WayforgeHarness grok' {
    It 'writes a dedicated .grok/hooks/wayforge.json' {
        $p = Join-Path $TestDrive 'grok'; New-HProject -Path $p
        Sync-WayforgeHarness -Harness grok -ProjectPath $p | Out-Null

        $f = Join-Path $p '.grok/hooks/wayforge.json'; $f | Should -Exist
        (Get-Content $f -Raw | ConvertFrom-Json).hooks.PreToolUse[0].hooks[0].command | Should -Match '-AsHook grok'
    }
}

Describe 'Sync-WayforgeHarness copilot' {
    It 'writes .github/hooks/wayforge.json with a preToolUse hook' {
        $p = Join-Path $TestDrive 'copilot'; New-HProject -Path $p
        Sync-WayforgeHarness -Harness copilot -ProjectPath $p | Out-Null

        $f = Join-Path $p '.github/hooks/wayforge.json'; $f | Should -Exist
        $j = Get-Content $f -Raw | ConvertFrom-Json
        $j.version | Should -Be 1
        $j.hooks.preToolUse[0].command | Should -Match '-AsHook copilot'
    }
}

Describe 'Sync-WayforgeHarness cursor' {
    It 'writes .cursor/hooks.json with beforeShellExecution and preToolUse' {
        $p = Join-Path $TestDrive 'cursor'; New-HProject -Path $p
        Sync-WayforgeHarness -Harness cursor -ProjectPath $p | Out-Null

        $f = Join-Path $p '.cursor/hooks.json'; $f | Should -Exist
        $j = Get-Content $f -Raw | ConvertFrom-Json
        $j.version                                    | Should -Be 1
        $j.hooks.beforeShellExecution[0].command      | Should -Match '-AsHook cursor'
        $j.hooks.beforeShellExecution[0].failClosed   | Should -BeTrue
        $j.hooks.preToolUse[0].command                | Should -Match 'gate\.ps1'
    }

    It 'blocks a Cursor beforeShellExecution command via the forbid command rule' {
        $p = Join-Path $TestDrive 'cursorcmd'; New-HProject -Path $p
        $event = '{"command":"git push --force origin main","cwd":"."}'
        $r = Invoke-WayforgeGate -Stage pre-tool -AsHook cursor -EventJson $event -ProjectPath $p
        $r.Blocked | Should -BeTrue
    }
}

Describe 'Sync-WayforgeHarness opencode' {
    It 'writes a .opencode/plugins/wayforge-gate.js plugin that throws to block' {
        $p = Join-Path $TestDrive 'opencode'; New-HProject -Path $p
        Sync-WayforgeHarness -Harness opencode -ProjectPath $p | Out-Null

        $f = Join-Path $p '.opencode/plugins/wayforge-gate.js'; $f | Should -Exist
        $c = Get-Content $f -Raw
        $c | Should -Match 'tool\.execute\.before'
        $c | Should -Match 'gate\.ps1'
        $c | Should -Match 'opencode'
        $c | Should -Match 'throw'
    }
}

Describe 'Sync-WayforgeHarness pi' {
    It 'writes a .pi/extensions/wayforge-gate.ts extension that returns block' {
        $p = Join-Path $TestDrive 'pi'; New-HProject -Path $p
        Sync-WayforgeHarness -Harness pi -ProjectPath $p | Out-Null

        $f = Join-Path $p '.pi/extensions/wayforge-gate.ts'; $f | Should -Exist
        $c = Get-Content $f -Raw
        $c | Should -Match 'pi\.on\("tool_call"'
        $c | Should -Match 'block: true'
        $c | Should -Match '"pi"'
    }
}

Describe 'Sync-WayforgeHarness kimi' {
    It 'writes a global-config snippet and warns (Kimi hooks are global-only)' {
        $p = Join-Path $TestDrive 'kimi'; New-HProject -Path $p
        $warn = $null
        Sync-WayforgeHarness -Harness kimi -ProjectPath $p -WarningVariable warn -WarningAction SilentlyContinue | Out-Null

        $f = Join-Path $p '.workflow/harness/kimi.config.toml'; $f | Should -Exist
        $c = Get-Content $f -Raw
        $c | Should -Match '\[\[hooks\]\]'
        $c | Should -Match 'PreToolUse'
        $c | Should -Match '\[\[permission.rules\]\]'
        $c | Should -Match 'Edit\(\*\*/\.env\)'
        $warn | Should -Not -BeNullOrEmpty
    }
}

Describe 'event normalization (per-harness payload shapes)' {
    # The default no-edit-dotenv gate: forbid tool [edit, write], path **/.env.
    It 'denies an <Name> edit of .env' -ForEach @(
        @{ Name = 'Claude';      Hook = 'claude';   Event = '{"tool_name":"Edit","tool_input":{"file_path":".env"}}' }
        @{ Name = 'pi';          Hook = 'pi';       Event = '{"tool_name":"edit","tool_input":{"path":".env"}}' }
        @{ Name = 'opencode';    Hook = 'opencode'; Event = '{"tool_name":"edit","tool_input":{"filePath":".env"}}' }
        @{ Name = 'Copilot CLI'; Hook = 'copilot';  Event = '{"toolName":"edit","toolArgs":{"path":".env"}}' }
    ) {
        $p = Join-Path $TestDrive ("norm_" + $Hook); New-HProject -Path $p
        $r = Invoke-WayforgeGate -Stage pre-tool -AsHook $Hook -EventJson $Event -ProjectPath $p
        $r.Blocked | Should -BeTrue
        ($r.Results | Where-Object Id -eq 'no-edit-dotenv').Status | Should -Be 'fail'
    }

    It 'allows a read of .env (tool restriction honored across shapes)' {
        $p = Join-Path $TestDrive 'norm_read'; New-HProject -Path $p
        $r = Invoke-WayforgeGate -Stage pre-tool -AsHook opencode -EventJson '{"tool_name":"read","tool_input":{"filePath":".env"}}' -ProjectPath $p
        $r.Blocked | Should -BeFalse
    }
}

Describe 'Kimi permission-rule projection' {
    It 'only projects unconditional, blocking, pre-tool path forbids' {
        $p = Join-Path $TestDrive 'kimifilter'
        New-Item -ItemType Directory -Path (Join-Path $p '.workflow/definitions') -Force | Out-Null
        @'
apiVersion: wayforge/v2
name: default
scopes:
  code:
    - "src/**"
gates:
  - id: block-env-pretool
    on:
      - pre-tool
    when: always
    severity: block
    check:
      forbid:
        path:
          - "**/.env"
  - id: block-secret-commit-only
    on:
      - pre-commit
    when: always
    severity: block
    check:
      forbid:
        path:
          - "**/secret.txt"
  - id: block-key-conditional
    on:
      - pre-tool
    when: changes_touch(code)
    severity: block
    check:
      forbid:
        path:
          - "**/*.key"
'@ | Set-Content (Join-Path $p '.workflow/definitions/default.yaml') -Encoding utf8NoBOM

        Sync-WayforgeHarness -Harness kimi -ProjectPath $p -WarningAction SilentlyContinue | Out-Null
        $c = Get-Content (Join-Path $p '.workflow/harness/kimi.config.toml') -Raw

        $c | Should -Match 'Edit\(\*\*/\.env\)'      # unconditional pre-tool -> projected
        $c | Should -Not -Match 'secret\.txt'        # pre-commit only -> hook-only
        $c | Should -Not -Match '\*\.key'            # conditional -> hook-only
    }
}

Describe 'Sync-WayforgeHarness multi' {
    It 'syncs several harnesses at once and shares one gate shim' {
        $p = Join-Path $TestDrive 'multi'; New-HProject -Path $p
        $res = Sync-WayforgeHarness -Harness claude, codex, cursor, opencode -ProjectPath $p

        $res.Harness | Should -Contain 'opencode'
        Join-Path $p '.claude/settings.json'          | Should -Exist
        Join-Path $p '.codex/hooks.json'              | Should -Exist
        Join-Path $p '.cursor/hooks.json'             | Should -Exist
        Join-Path $p '.opencode/plugins/wayforge-gate.js' | Should -Exist
        Join-Path $p '.workflow/hooks/gate.ps1'       | Should -Exist
    }
}
