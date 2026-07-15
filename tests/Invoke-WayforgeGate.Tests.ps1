BeforeAll {
    $script:ModuleRoot   = Split-Path -Parent $PSScriptRoot
    $script:ManifestPath = Join-Path -Path $ModuleRoot -ChildPath 'PSWayforge.psd1'
    Import-Module -Name $ManifestPath -Force

    # Minimal v2 workspace: one gate requiring a valid plan for code changes.
    $script:Project = Join-Path $TestDrive 'gateproj'
    New-Item -ItemType Directory -Path (Join-Path $Project '.workflow/definitions') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $Project '.workflow/schemas')     -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $Project '.workflow/artifacts')   -Force | Out-Null

    @'
apiVersion: wayforge/v2
name: default
scopes:
  code:
    - "**/*.ps1"
  docs:
    - "**/*.md"
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
'@ | Set-Content (Join-Path $Project '.workflow/definitions/default.yaml') -Encoding utf8NoBOM

    @'
{ "$schema": "http://json-schema.org/draft-07/schema#", "type": "object",
  "required": ["summary"], "properties": { "summary": { "type": "string" } } }
'@ | Set-Content (Join-Path $Project '.workflow/schemas/plan.json') -Encoding utf8NoBOM

    $script:PlanPath = Join-Path $Project '.workflow/artifacts/plan.json'
}

AfterAll {
    Remove-Module -Name PSWayforge -Force -ErrorAction SilentlyContinue
}

Describe 'Invoke-WayforgeGate' {
    BeforeEach {
        if (Test-Path $PlanPath) { Remove-Item $PlanPath -Force }
    }

    It 'blocks a code change when the required artifact is missing' {
        $r = Invoke-WayforgeGate -Stage pre-commit -AsHook git -ProjectPath $Project -ChangeSet @('foo.ps1')
        $r.Blocked  | Should -BeTrue
        $r.ExitCode | Should -Be 1
        ($r.Results | Where-Object Id -eq 'plan-before-build').Status | Should -Be 'fail'
    }

    It 'skips the gate for a docs-only change' {
        $r = Invoke-WayforgeGate -Stage pre-commit -AsHook git -ProjectPath $Project -ChangeSet @('README.md')
        $r.Blocked | Should -BeFalse
        ($r.Results | Where-Object Id -eq 'plan-before-build').Status | Should -Be 'skip'
    }

    It 'passes a code change when a valid plan artifact exists' {
        '{ "summary": "do the thing" }' | Set-Content $PlanPath -Encoding utf8NoBOM
        $r = Invoke-WayforgeGate -Stage pre-commit -AsHook git -ProjectPath $Project -ChangeSet @('foo.ps1')
        $r.Blocked | Should -BeFalse
        ($r.Results | Where-Object Id -eq 'plan-before-build').Status | Should -Be 'pass'
    }

    It 'fails a code change when the plan artifact is present but invalid' {
        '{ "notsummary": 1 }' | Set-Content $PlanPath -Encoding utf8NoBOM
        $r = Invoke-WayforgeGate -Stage pre-commit -AsHook git -ProjectPath $Project -ChangeSet @('foo.ps1')
        $r.Blocked | Should -BeTrue
    }

    It 'emits Claude dialect exit code 2 when blocked at pre-tool' {
        $event = '{"hook_event_name":"PreToolUse","tool_name":"Edit","tool_input":{"file_path":"bar.ps1"}}'
        $r = Invoke-WayforgeGate -Stage pre-tool -AsHook claude -EventJson $event -ProjectPath $Project
        $r.Blocked  | Should -BeTrue
        $r.ExitCode | Should -Be 2
    }

    It 'does not block a stage that no gate targets' {
        $r = Invoke-WayforgeGate -Stage pre-push -AsHook git -ProjectPath $Project -ChangeSet @('foo.ps1')
        $r.Blocked | Should -BeFalse
        $r.Results | Should -BeNullOrEmpty
    }

    It 'fails closed when a workflow definition cannot be parsed' {
        $bad = Join-Path $TestDrive 'badworkflow'
        New-Item -ItemType Directory -Path (Join-Path $bad '.workflow/definitions') -Force | Out-Null
        'gates: [unclosed' | Set-Content (Join-Path $bad '.workflow/definitions/default.yaml') -Encoding utf8NoBOM

        $r = Invoke-WayforgeGate -Stage pre-commit -AsHook git -ProjectPath $bad -ChangeSet @('foo.ps1')
        $r.Blocked   | Should -BeTrue
        $r.Results.Id | Should -Contain 'wayforge-engine-error'
    }

    It 'fails closed on a malformed pre-tool event payload' {
        $r = Invoke-WayforgeGate -Stage pre-tool -AsHook claude -EventJson 'not json {' -ProjectPath $Project
        $r.Blocked   | Should -BeTrue
        $r.Results.Id | Should -Contain 'wayforge-engine-error'
    }
}
