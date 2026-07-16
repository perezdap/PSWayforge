BeforeAll {
    $script:ModuleRoot = Split-Path -Parent $PSScriptRoot
    $script:ManifestPath = Join-Path -Path $ModuleRoot -ChildPath 'PSWayforge.psd1'

    if (-not (Test-Path -Path $ManifestPath)) {
        throw "PSWayforge module manifest not found at '$ManifestPath'. Implement the foundation scope before running these tests."
    }

    Import-Module -Name $ManifestPath -Force
}

AfterAll {
    Remove-Module -Name PSWayforge -Force -ErrorAction SilentlyContinue
}

Describe 'New-WayforgeProject' {
    BeforeEach {
        Get-ChildItem -Path $TestDrive -ErrorAction SilentlyContinue |
            Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'creates a new project directory' {
        New-WayforgeProject -Name 'WayforgeTestProject' -Path $TestDrive
        Join-Path -Path $TestDrive -ChildPath 'WayforgeTestProject' | Should -Exist
    }

    It 'creates AGENTS.md at the project root' {
        New-WayforgeProject -Name 'WayforgeTestProject' -Path $TestDrive
        Join-Path -Path $TestDrive -ChildPath 'WayforgeTestProject/AGENTS.md' | Should -Exist
    }

    It 'renders the workflow steps into AGENTS.md' {
        New-WayforgeProject -Name 'WayforgeTestProject' -Path $TestDrive -WarningAction SilentlyContinue | Out-Null
        $agents = Get-Content (Join-Path $TestDrive 'WayforgeTestProject/AGENTS.md') -Raw
        $agents | Should -Match 'wayforge:workflow:start'
        $agents | Should -Match '\bscout\b'
    }

    It 'creates the .agents and .workflow directories' {
        New-WayforgeProject -Name 'WayforgeTestProject' -Path $TestDrive
        Join-Path -Path $TestDrive -ChildPath 'WayforgeTestProject/.agents' | Should -Exist
        Join-Path -Path $TestDrive -ChildPath 'WayforgeTestProject/.workflow' | Should -Exist
    }

    It 'installs the example skill, default workflow, and example schema' {
        New-WayforgeProject -Name 'WayforgeTestProject' -Path $TestDrive
        Join-Path -Path $TestDrive -ChildPath 'WayforgeTestProject/.agents/skills/example/SKILL.md' | Should -Exist
        Join-Path -Path $TestDrive -ChildPath 'WayforgeTestProject/.workflow/definitions/default.yaml' | Should -Exist
        Join-Path -Path $TestDrive -ChildPath 'WayforgeTestProject/.workflow/schemas/example.json' | Should -Exist
    }

    It 'gives the example skill the name and description frontmatter that skill loaders require' {
        New-WayforgeProject -Name 'WayforgeTestProject' -Path $TestDrive -WarningAction SilentlyContinue | Out-Null
        $skill = Get-Content (Join-Path $TestDrive 'WayforgeTestProject/.agents/skills/example/SKILL.md') -Raw

        $skill | Should -Match '(?s)\A---\r?\n.*\r?\n---\r?\n'
        $skill | Should -Match '(?m)^name:\s*example\s*$'
        $skill | Should -Match '(?m)^description:\s*\S'
    }

    It 'creates a .gitignore and initializes a git repository when git is available' {
        New-WayforgeProject -Name 'WayforgeTestProject' -Path $TestDrive

        Join-Path -Path $TestDrive -ChildPath 'WayforgeTestProject/.gitignore' | Should -Exist

        if (Get-Command -Name git -ErrorAction SilentlyContinue) {
            Join-Path -Path $TestDrive -ChildPath 'WayforgeTestProject/.git' | Should -Exist
        }
    }

    It 'warns and skips files when git is unavailable' {
        $testProjectPath = Join-Path -Path $TestDrive -ChildPath 'WayforgeNoGitProject'

        InModuleScope -ModuleName PSWayforge -Parameters @{ TestDrive = $TestDrive; TestProjectPath = $testProjectPath } {
            Mock Get-Command { return $null } -ParameterFilter { $Name -eq 'git' }

            New-WayforgeProject -Name 'WayforgeNoGitProject' -Path $TestDrive -WarningVariable warnings -WarningAction SilentlyContinue | Out-Null

            $warnings | Should -Not -BeNullOrEmpty
            $testProjectPath | Should -Exist
            Join-Path -Path $testProjectPath -ChildPath '.git' | Should -Not -Exist
        }
    }

    It 'is additive only when -InitializeExisting is used and does not overwrite existing files' {
        $testProjectPath = Join-Path -Path $TestDrive -ChildPath 'WayforgeExistingProject'
        New-Item -ItemType Directory -Path $testProjectPath | Out-Null
        $agentsPath = Join-Path -Path $testProjectPath -ChildPath 'AGENTS.md'
        'existing agents content' | Set-Content -Path $agentsPath -NoNewline

        $warnings = $null
        New-WayforgeProject -Name 'WayforgeExistingProject' -Path $TestDrive -InitializeExisting -WarningAction SilentlyContinue -WarningVariable warnings | Out-Null

        # The existing file is not overwritten; the workflow block is appended
        # non-destructively (the user's content is preserved).
        $agents = Get-Content -Path $agentsPath -Raw
        $agents | Should -Match 'existing agents content'
        $agents | Should -Match 'wayforge:workflow:start'
        Join-Path -Path $testProjectPath -ChildPath '.gitignore' | Should -Exist
        $warnings | Should -Not -BeNullOrEmpty
    }

    It 'wires the enforcement layer when git is available' {
        New-WayforgeProject -Name 'EnforcedProject' -Path $TestDrive -WarningAction SilentlyContinue | Out-Null
        $root = Join-Path $TestDrive 'EnforcedProject'

        if (Get-Command -Name git -ErrorAction SilentlyContinue) {
            Join-Path $root '.claude/settings.json'        | Should -Exist
            Join-Path $root '.workflow/hooks/gate.ps1'     | Should -Exist
            Join-Path $root '.workflow/githooks/pre-commit' | Should -Exist
            Join-Path $root '.workflow/artifacts'          | Should -Exist
            Push-Location $root
            try { (git config core.hooksPath) | Should -Be '.workflow/githooks' }
            finally { Pop-Location }
        }
    }

    It 'skips enforcement when -SkipEnforcement is set' {
        $result = New-WayforgeProject -Name 'PlainProject' -Path $TestDrive -SkipEnforcement -WarningAction SilentlyContinue
        $root = Join-Path $TestDrive 'PlainProject'

        $result.Enforced | Should -BeFalse
        Join-Path $root '.claude/settings.json'         | Should -Not -Exist
        Join-Path $root '.workflow/githooks/pre-commit' | Should -Not -Exist
    }
}
