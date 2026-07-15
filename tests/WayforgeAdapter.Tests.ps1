BeforeAll {
    $script:ModuleRoot   = Split-Path -Parent $PSScriptRoot
    $script:ManifestPath = Join-Path -Path $ModuleRoot -ChildPath 'PSWayforge.psd1'
    Import-Module -Name $ManifestPath -Force

    function New-GateProject {
        param([string] $Path)
        New-Item -ItemType Directory -Path (Join-Path $Path '.workflow/definitions') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $Path '.workflow/schemas')     -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $Path '.workflow/artifacts')   -Force | Out-Null
        @'
apiVersion: wayforge/v2
name: default
scopes:
  code:
    - "**/*.ps1"
gates:
  - id: plan-before-build
    description: Code changes require a valid plan
    on:
      - pre-commit
      - pre-tool
    when: changes_touch(code)
    severity: block
    check:
      requires_artifact: plan.json
      schema: plan
  - id: no-edit-dotenv
    description: Never commit .env files
    on:
      - pre-commit
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

Describe 'forbid check' {
    It 'blocks a change that touches a forbidden path' {
        $p = Join-Path $TestDrive 'forbidproj'
        New-GateProject -Path $p
        $r = Invoke-WayforgeGate -Stage pre-commit -AsHook git -ProjectPath $p -ChangeSet @('.env')
        $r.Blocked | Should -BeTrue
        ($r.Results | Where-Object Id -eq 'no-edit-dotenv').Status | Should -Be 'fail'
    }

    It 'allows a change that touches no forbidden path' {
        $p = Join-Path $TestDrive 'forbidproj2'
        New-GateProject -Path $p
        '{ "summary": "x" }' | Set-Content (Join-Path $p '.workflow/artifacts/plan.json') -Encoding utf8NoBOM
        $r = Invoke-WayforgeGate -Stage pre-commit -AsHook git -ProjectPath $p -ChangeSet @('foo.ps1')
        $r.Blocked | Should -BeFalse
    }
}

Describe 'Sync-WayforgeHarness (claude)' {
    It 'generates .claude/settings.json with hooks and forbid deny-rules' {
        $p = Join-Path $TestDrive 'syncproj'
        New-GateProject -Path $p
        Sync-WayforgeHarness -Harness claude -ProjectPath $p | Out-Null

        $settingsPath = Join-Path $p '.claude/settings.json'
        $settingsPath | Should -Exist
        Join-Path $p '.workflow/hooks/gate.ps1' | Should -Exist

        $settings = Get-Content $settingsPath -Raw | ConvertFrom-Json
        $settings.hooks.PreToolUse | Should -Not -BeNullOrEmpty
        $settings.hooks.PreToolUse[0].hooks[0].command | Should -Match 'gate\.ps1'
        $settings.hooks.PreToolUse[0].hooks[0].command | Should -Match '\$\{CLAUDE_PROJECT_DIR\}'
        $settings.permissions.deny | Should -Contain 'Edit(**/.env)'
        $settings.permissions.deny | Should -Contain 'Write(**/.env)'
    }

    It 'preserves existing settings.json entries and is idempotent' {
        $p = Join-Path $TestDrive 'mergeproj'
        New-GateProject -Path $p
        $claude = Join-Path $p '.claude'
        New-Item -ItemType Directory -Path $claude -Force | Out-Null
        @'
{
  "model": "claude-x",
  "permissions": { "allow": ["Bash(ls)"], "deny": ["Edit(secret.txt)"] },
  "hooks": { "PreToolUse": [ { "matcher": "Read", "hooks": [ { "type": "command", "command": "echo hi" } ] } ] }
}
'@ | Set-Content (Join-Path $claude 'settings.json') -Encoding utf8NoBOM

        Sync-WayforgeHarness -Harness claude -ProjectPath $p | Out-Null
        $s = Get-Content (Join-Path $claude 'settings.json') -Raw | ConvertFrom-Json

        $s.model                | Should -Be 'claude-x'          # unrelated key preserved
        $s.permissions.allow    | Should -Contain 'Bash(ls)'     # unrelated permission preserved
        $s.permissions.deny     | Should -Contain 'Edit(secret.txt)'  # existing deny preserved
        $s.permissions.deny     | Should -Contain 'Edit(**/.env)'     # ours added
        ($s.hooks.PreToolUse | Where-Object { $_.matcher -eq 'Read' }) | Should -Not -BeNullOrEmpty  # user hook kept

        # Idempotent: a second sync must not duplicate our gate.ps1 hook entry.
        Sync-WayforgeHarness -Harness claude -ProjectPath $p | Out-Null
        $s2 = Get-Content (Join-Path $claude 'settings.json') -Raw | ConvertFrom-Json
        @($s2.hooks.PreToolUse | Where-Object { ($_.hooks.command -join '') -match 'gate\.ps1' }).Count | Should -Be 1
    }
}

Describe 'forbid dimensions' {
    It 'blocks a command-only rule at pre-tool when the command matches' {
        $p = Join-Path $TestDrive 'cmdforbid'
        New-Item -ItemType Directory -Path (Join-Path $p '.workflow/definitions') -Force | Out-Null
        @'
apiVersion: wayforge/v2
name: default
gates:
  - id: no-force-push
    description: Do not force-push
    on:
      - pre-tool
    when: always
    severity: block
    check:
      forbid:
        command:
          - "git push --force*"
'@ | Set-Content (Join-Path $p '.workflow/definitions/default.yaml') -Encoding utf8NoBOM

        $blockEvent = '{"tool_name":"Bash","tool_input":{"command":"git push --force origin main"}}'
        $okEvent    = '{"tool_name":"Bash","tool_input":{"command":"git status"}}'

        (Invoke-WayforgeGate -Stage pre-tool -AsHook claude -EventJson $blockEvent -ProjectPath $p).Blocked | Should -BeTrue
        (Invoke-WayforgeGate -Stage pre-tool -AsHook claude -EventJson $okEvent    -ProjectPath $p).Blocked | Should -BeFalse
    }

    It 'honors the tool restriction: blocks Edit but allows Read of a forbidden path' {
        $p = Join-Path $TestDrive 'toolforbid'
        New-GateProject -Path $p    # no-edit-dotenv: tool [edit, write], path **/.env

        $edit = '{"tool_name":"Edit","tool_input":{"file_path":".env"}}'
        $read = '{"tool_name":"Read","tool_input":{"file_path":".env"}}'

        (Invoke-WayforgeGate -Stage pre-tool -AsHook claude -EventJson $edit -ProjectPath $p).Blocked | Should -BeTrue
        (Invoke-WayforgeGate -Stage pre-tool -AsHook claude -EventJson $read -ProjectPath $p).Blocked | Should -BeFalse
    }
}

Describe 'pre-push changeset' {
    It 'sees pushed files on a new branch instead of failing open' {
        $p = Join-Path $TestDrive 'prepush'
        New-Item -ItemType Directory -Path (Join-Path $p '.workflow/definitions') -Force | Out-Null
        @'
apiVersion: wayforge/v2
name: default
gates:
  - id: no-edit-dotenv
    description: Never push dotenv files
    on:
      - pre-push
    when: always
    severity: block
    check:
      forbid:
        path:
          - "**/.env"
'@ | Set-Content (Join-Path $p '.workflow/definitions/default.yaml') -Encoding utf8NoBOM

        Push-Location $p
        try {
            git init -q
            git config user.email 'a@b.c'; git config user.name 'test'
            'SECRET=1' | Set-Content .env -Encoding utf8NoBOM
            git add -A; git commit -q -m init
            $sha = (git rev-parse HEAD).Trim()
            $zero = '0' * 40
            $event = "refs/heads/feature $sha refs/heads/feature $zero"

            $r = Invoke-WayforgeGate -Stage pre-push -AsHook git -EventJson $event -ProjectPath $p
            $r.Blocked | Should -BeTrue     # .env seen via empty-tree diff, not fail-open
        }
        finally { Pop-Location }
    }
}

Describe 'ConvertTo-WayforgeArgList' {
    It 'splits quoted arguments without shell interpretation' {
        InModuleScope PSWayforge {
            $a = ConvertTo-WayforgeArgList -CommandLine 'foo "a b" c'
            $a.Count | Should -Be 3
            $a[1]    | Should -Be 'a b'
        }
    }
}

Describe 'Register-WayforgeHooks' {
    It 'installs git hook shims with LF endings and sets core.hooksPath' {
        $p = Join-Path $TestDrive 'hookproj'
        New-Item -ItemType Directory -Path $p -Force | Out-Null
        Push-Location $p
        try {
            git init -q
            Register-WayforgeHooks -ProjectPath $p | Out-Null

            Join-Path $p '.workflow/hooks/gate.ps1'      | Should -Exist
            $preCommit = Join-Path $p '.workflow/githooks/pre-commit'
            $preCommit | Should -Exist

            $raw = Get-Content $preCommit -Raw
            $raw | Should -Match '^#!/bin/sh'
            ($raw -match "`r") | Should -BeFalse          # must be LF for sh

            (git config core.hooksPath) | Should -Be '.workflow/githooks'
        }
        finally { Pop-Location }
    }

    It 'tracks the git hook shims as executable (mode 100755)' {
        $p = Join-Path $TestDrive 'execbit'
        New-Item -ItemType Directory -Path $p -Force | Out-Null
        Push-Location $p
        try {
            git init -q
            Register-WayforgeHooks -ProjectPath $p | Out-Null
            $entry = git ls-files --stage .workflow/githooks/pre-commit
            (($entry -split '\s+')[0]) | Should -Be '100755'
        }
        finally { Pop-Location }
    }

    It 'throws when the path is not a git repository' {
        $p = Join-Path $TestDrive 'notgit'
        New-Item -ItemType Directory -Path $p -Force | Out-Null
        { Register-WayforgeHooks -ProjectPath $p } | Should -Throw
    }

    It 'does not mutate the repository under -WhatIf' {
        $p = Join-Path $TestDrive 'whatif'
        New-Item -ItemType Directory -Path $p -Force | Out-Null
        Push-Location $p
        try {
            git init -q
            Register-WayforgeHooks -ProjectPath $p -WhatIf | Out-Null
            Join-Path $p '.workflow/hooks/gate.ps1'      | Should -Not -Exist
            Join-Path $p '.workflow/githooks/pre-commit' | Should -Not -Exist
            (git config core.hooksPath) | Should -BeNullOrEmpty
        }
        finally { Pop-Location }
    }
}

Describe 'Register-WayforgeCI' {
    It 'generates a GitHub Actions gate workflow' {
        $p = Join-Path $TestDrive 'ciproj'
        New-Item -ItemType Directory -Path $p -Force | Out-Null
        Register-WayforgeCI -ProjectPath $p | Out-Null

        $wf = Join-Path $p '.github/workflows/wayforge-gate.yml'
        $wf | Should -Exist
        $raw = Get-Content $wf -Raw
        $raw | Should -Match 'name:\s*wayforge-gate'
        $raw | Should -Match 'Invoke-WayforgeGate -Stage ci'
        $raw | Should -Match 'fetch-depth:\s*0'
        ($raw -match "`r") | Should -BeFalse       # LF for portability
    }
}

Describe 'ci stage' {
    It 'blocks a forbidden path found in the base...HEAD diff' {
        $p = Join-Path $TestDrive 'cigate'
        New-Item -ItemType Directory -Path (Join-Path $p '.workflow/definitions') -Force | Out-Null
        @'
apiVersion: wayforge/v2
name: default
gates:
  - id: no-edit-dotenv
    description: Never commit dotenv files
    on:
      - ci
    when: always
    severity: block
    check:
      forbid:
        path:
          - "**/.env"
'@ | Set-Content (Join-Path $p '.workflow/definitions/default.yaml') -Encoding utf8NoBOM

        Push-Location $p
        try {
            git init -q
            git config user.email 'a@b.c'; git config user.name 'test'
            'base' | Set-Content base.txt -Encoding utf8NoBOM
            git add base.txt; git commit -q -m base
            $base = (git rev-parse HEAD).Trim()

            'SECRET=1' | Set-Content .env -Encoding utf8NoBOM
            git add -f .env; git commit -q -m env

            $env:WAYFORGE_BASE_REF = $base
            try { $r = Invoke-WayforgeGate -Stage ci -AsHook ci -ProjectPath $p }
            finally { Remove-Item Env:WAYFORGE_BASE_REF -ErrorAction SilentlyContinue }

            $r.Blocked | Should -BeTrue
            ($r.Results | Where-Object Id -eq 'no-edit-dotenv').Status | Should -Be 'fail'
        }
        finally { Pop-Location }
    }

    It 'falls back to the full tree when the base ref is unreachable' {
        $p = Join-Path $TestDrive 'cifallback'
        New-Item -ItemType Directory -Path (Join-Path $p '.workflow/definitions') -Force | Out-Null
        @'
apiVersion: wayforge/v2
name: default
gates:
  - id: no-edit-dotenv
    description: Never commit dotenv files
    on:
      - ci
    when: always
    severity: block
    check:
      forbid:
        path:
          - "**/.env"
'@ | Set-Content (Join-Path $p '.workflow/definitions/default.yaml') -Encoding utf8NoBOM

        Push-Location $p
        try {
            git init -q
            git config user.email 'a@b.c'; git config user.name 'test'
            'x' | Set-Content base.txt -Encoding utf8NoBOM
            'SECRET=1' | Set-Content .env -Encoding utf8NoBOM
            git add -A; git commit -q -m init

            $env:WAYFORGE_BASE_REF = 'origin/does-not-exist'
            try { $r = Invoke-WayforgeGate -Stage ci -AsHook ci -ProjectPath $p }
            finally { Remove-Item Env:WAYFORGE_BASE_REF -ErrorAction SilentlyContinue }

            $r.Blocked | Should -BeTrue      # .env found via full-tree fallback
        }
        finally { Pop-Location }
    }
}
