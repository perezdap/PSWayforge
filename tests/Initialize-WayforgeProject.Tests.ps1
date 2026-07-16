BeforeAll {
    $script:ModuleRoot   = Split-Path -Parent $PSScriptRoot
    $script:ManifestPath = Join-Path -Path $ModuleRoot -ChildPath 'PSWayforge.psd1'
    Import-Module -Name $ManifestPath -Force
}

AfterAll {
    Remove-Module -Name PSWayforge -Force -ErrorAction SilentlyContinue
}

Describe 'Initialize-WayforgeProject' {
    It 'scaffolds Wayforge into an existing directory in place, preserving files' {
        $p = Join-Path $TestDrive 'existing'
        New-Item -ItemType Directory -Path $p -Force | Out-Null
        'keep me' | Set-Content (Join-Path $p 'README.md') -Encoding utf8NoBOM
        Push-Location $p
        try { git init -q } finally { Pop-Location }

        $result = Initialize-WayforgeProject -Path $p -SkipEnforcement -WarningAction SilentlyContinue

        $result.Name | Should -Be 'existing'
        Join-Path $p 'AGENTS.md'                          | Should -Exist
        Join-Path $p '.workflow/definitions/default.yaml' | Should -Exist
        (Get-Content (Join-Path $p 'README.md') -Raw).Trim() | Should -Be 'keep me'   # not clobbered
    }

    It 'wires enforcement when git is available' {
        $p = Join-Path $TestDrive 'enforced'
        New-Item -ItemType Directory -Path $p -Force | Out-Null
        Push-Location $p
        try { git init -q } finally { Pop-Location }

        $result = Initialize-WayforgeProject -Path $p -Harness claude -WarningAction SilentlyContinue

        if (Get-Command git -ErrorAction SilentlyContinue) {
            $result.Enforced | Should -BeTrue
            Join-Path $p '.claude/settings.json'    | Should -Exist
            Join-Path $p '.workflow/hooks/gate.ps1' | Should -Exist
        }
    }

    It 'throws when the directory does not exist' {
        { Initialize-WayforgeProject -Path (Join-Path $TestDrive 'does-not-exist') } | Should -Throw
    }
}
