BeforeAll {
    $script:ModuleRoot = Split-Path -Parent $PSScriptRoot
    Import-Module -Name (Join-Path $ModuleRoot 'PSWayforge.psd1') -Force

    function New-DetectFixture {
        param([string] $Base)
        $homeDir = Join-Path $Base 'home'
        $projDir = Join-Path $Base 'proj'
        New-Item -ItemType Directory -Path (Join-Path $homeDir '.claude') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $homeDir '.cursor') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $projDir '.codex')  -Force | Out-Null
        [PSCustomObject]@{ Home = $homeDir; Project = $projDir }
    }
}

AfterAll {
    Remove-Module -Name PSWayforge -Force -ErrorAction SilentlyContinue
}

Describe 'Get-WayforgeHarness' {
    It 'reports Installed from home markers and Configured from project markers' {
        $fx = New-DetectFixture -Base (Join-Path $TestDrive 'd1')
        $info = Get-WayforgeHarness -ProjectPath $fx.Project -HomePath $fx.Home

        ($info | Where-Object Name -eq 'claude').Installed  | Should -BeTrue
        ($info | Where-Object Name -eq 'cursor').Installed  | Should -BeTrue
        ($info | Where-Object Name -eq 'codex').Installed   | Should -BeFalse
        ($info | Where-Object Name -eq 'codex').Configured  | Should -BeTrue
        ($info | Where-Object Name -eq 'claude').Configured | Should -BeFalse
        ($info | Where-Object Name -eq 'grok').Installed    | Should -BeFalse
    }

    It 'returns an entry for every known harness' {
        $info = Get-WayforgeHarness -ProjectPath $TestDrive -HomePath $TestDrive
        ($info | ForEach-Object Name) | Should -Contain 'opencode'
        ($info | ForEach-Object Name) | Should -Contain 'pi'
        ($info | ForEach-Object Name) | Should -Contain 'kimi'
        $info.Count | Should -Be 8
    }
}

Describe 'Select-WayforgeHarness' {
    It 'pre-selects installed and configured harnesses and returns them on confirm' {
        $fx = New-DetectFixture -Base (Join-Path $TestDrive 'd2')
        Mock -CommandName Read-Host -ModuleName PSWayforge -MockWith { '' }
        Mock -CommandName Write-Host -ModuleName PSWayforge -MockWith { }

        $sel = Select-WayforgeHarness -ProjectPath $fx.Project -HomePath $fx.Home
        $sel | Should -Contain 'claude'    # installed
        $sel | Should -Contain 'cursor'    # installed
        $sel | Should -Contain 'codex'     # configured
        $sel | Should -Not -Contain 'grok'
    }

    It 'toggles a numbered entry off before confirming' {
        $fx = New-DetectFixture -Base (Join-Path $TestDrive 'd3')
        # claude is entry 1; toggle it off, then confirm.
        $script:answers = @('1', '')
        $script:i = 0
        Mock -CommandName Read-Host -ModuleName PSWayforge -MockWith { $a = $script:answers[$script:i]; $script:i++; $a }
        Mock -CommandName Write-Host -ModuleName PSWayforge -MockWith { }

        $sel = Select-WayforgeHarness -ProjectPath $fx.Project -HomePath $fx.Home
        $sel | Should -Not -Contain 'claude'
        $sel | Should -Contain 'cursor'
    }
}

Describe 'Sync-WayforgeHarness -Detect' {
    It 'syncs the detected harnesses' {
        $p = Join-Path $TestDrive 'syncdetect'
        New-Item -ItemType Directory -Path (Join-Path $p '.workflow/definitions') -Force | Out-Null
        @'
apiVersion: wayforge/v2
name: default
gates:
  - id: no-edit-dotenv
    on:
      - pre-tool
    when: always
    severity: block
    check:
      forbid:
        path:
          - "**/.env"
'@ | Set-Content (Join-Path $p '.workflow/definitions/default.yaml') -Encoding utf8NoBOM

        Mock -CommandName Get-WayforgeHarness -ModuleName PSWayforge -MockWith {
            @(
                [PSCustomObject]@{ Name = 'claude'; Installed = $true;  Configured = $false }
                [PSCustomObject]@{ Name = 'codex';  Installed = $false; Configured = $true }
            )
        }

        $res = Sync-WayforgeHarness -Detect -ProjectPath $p -WarningAction SilentlyContinue
        ($res | ForEach-Object Harness) | Should -Contain 'claude'
        ($res | ForEach-Object Harness) | Should -Contain 'codex'
        Join-Path $p '.claude/settings.json' | Should -Exist
        Join-Path $p '.codex/hooks.json'     | Should -Exist
    }

    It 'warns and returns nothing when no harness is detected' {
        $p = Join-Path $TestDrive 'syncnone'
        New-Item -ItemType Directory -Path (Join-Path $p '.workflow/definitions') -Force | Out-Null
        Mock -CommandName Get-WayforgeHarness -ModuleName PSWayforge -MockWith { @() }

        $warn = $null
        $res = Sync-WayforgeHarness -Detect -ProjectPath $p -WarningVariable warn -WarningAction SilentlyContinue
        $res  | Should -BeNullOrEmpty
        $warn | Should -Not -BeNullOrEmpty
    }
}
