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

    It 'throws when the path is not a git repository' {
        $p = Join-Path $TestDrive 'notgit'
        New-Item -ItemType Directory -Path $p -Force | Out-Null
        { Register-WayforgeHooks -ProjectPath $p } | Should -Throw
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
}
