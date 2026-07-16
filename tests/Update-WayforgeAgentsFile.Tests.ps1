BeforeAll {
    $script:ModuleRoot   = Split-Path -Parent $PSScriptRoot
    $script:ManifestPath = Join-Path -Path $ModuleRoot -ChildPath 'PSWayforge.psd1'
    Import-Module -Name $ManifestPath -Force

    function New-StepsProject {
        param([string] $Path)
        New-Item -ItemType Directory -Path (Join-Path $Path '.workflow/definitions') -Force | Out-Null
        Copy-Item (Join-Path $ModuleRoot 'templates/workflow.default.yaml') (Join-Path $Path '.workflow/definitions/default.yaml')
    }
}

AfterAll {
    Remove-Module -Name PSWayforge -Force -ErrorAction SilentlyContinue
}

Describe 'Update-WayforgeAgentsFile' {
    It 'renders the workflow steps into a managed block, preserving other content' {
        $p = Join-Path $TestDrive 'render'; New-StepsProject -Path $p
        "# My Project`n`nCustom guidance I wrote." | Set-Content (Join-Path $p 'AGENTS.md') -Encoding utf8NoBOM

        Update-WayforgeAgentsFile -ProjectPath $p | Out-Null
        $c = Get-Content (Join-Path $p 'AGENTS.md') -Raw

        $c | Should -Match 'Custom guidance I wrote\.'      # preserved
        $c | Should -Match 'wayforge:workflow:start'
        $c | Should -Match 'wayforge:workflow:end'
        $c | Should -Match '\bscout\b'
        $c | Should -Match '\bplan\b'
        $c | Should -Match '\bbuild\b'
    }

    It 'is idempotent (a single managed block after repeated runs)' {
        $p = Join-Path $TestDrive 'idem'; New-StepsProject -Path $p
        Update-WayforgeAgentsFile -ProjectPath $p | Out-Null
        Update-WayforgeAgentsFile -ProjectPath $p | Out-Null
        $c = Get-Content (Join-Path $p 'AGENTS.md') -Raw
        ([regex]::Matches($c, 'wayforge:workflow:start')).Count | Should -Be 1
    }

    It 'creates AGENTS.md when none exists' {
        $p = Join-Path $TestDrive 'fresh'; New-StepsProject -Path $p
        Update-WayforgeAgentsFile -ProjectPath $p | Out-Null
        Join-Path $p 'AGENTS.md' | Should -Exist
    }

    It 'returns null when no workflow has steps' {
        $p = Join-Path $TestDrive 'nosteps'
        New-Item -ItemType Directory -Path (Join-Path $p '.workflow/definitions') -Force | Out-Null
        @'
apiVersion: wayforge/v2
name: default
gates:
  - id: g
    on: [pre-commit]
    when: always
    check:
      forbid:
        path: ["**/.env"]
'@ | Set-Content (Join-Path $p '.workflow/definitions/default.yaml') -Encoding utf8NoBOM

        Update-WayforgeAgentsFile -ProjectPath $p | Should -BeNullOrEmpty
    }
}
