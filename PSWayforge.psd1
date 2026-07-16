@{
    RootModule           = 'PSWayforge.psm1'
    ModuleVersion        = '0.4.1'
    GUID                 = 'cc6c71de-c415-442a-9170-9589bfa5eb0a'
    Author               = 'PSWayforge Contributors'
    CompanyName          = ''
    Copyright            = '(c) PSWayforge Contributors. All rights reserved.'
    Description          = 'Scaffolds agent-agnostic project workspaces with AGENTS.md, skills, workflows, hooks, and schemas.'
    PowerShellVersion    = '7.3'
    CompatiblePSEditions = @('Core')
    FunctionsToExport    = @(
        'New-WayforgeProject'
        'Initialize-WayforgeProject'
        'Invoke-WayforgeHook'
        'Test-WayforgeSchema'
        'Get-WayforgeWorkflow'
        'Invoke-WayforgeGate'
        'Register-WayforgeHooks'
        'Register-WayforgeCI'
        'Sync-WayforgeHarness'
        'Get-WayforgeHarness'
        'Select-WayforgeHarness'
        'Update-WayforgeAgentsFile'
    )
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @()
    PrivateData          = @{
        PSData = @{
            Tags                     = @('agent', 'workspace', 'scaffold', 'workflow', 'ai', 'enforcement', 'guardrails', 'hooks')
            LicenseUri               = 'https://github.com/perezdap/PSWayforge/blob/main/LICENSE'
            ProjectUri               = 'https://github.com/perezdap/PSWayforge'
            RequireLicenseAcceptance = $false
            ReleaseNotes             = '0.4.1: The scaffolded example skill now carries the name/description YAML frontmatter that skill loaders require - previously every scaffolded project shipped a SKILL.md that loaders rejected as invalid. Existing projects need the frontmatter added by hand, since scaffolding never overwrites existing files. 0.4.0: The workflow''s steps are now actually rendered into AGENTS.md (a managed, non-destructive marker block) via Update-WayforgeAgentsFile and during scaffolding - previously steps were parsed but unused. 0.3.0: Scopes support !-prefixed exclude globs; the default code scope now matches source by extension across any layout (flat/root, cmd/pkg/internal, etc.) while excluding Wayforge''s own tree, so the plan gate is no longer a no-op on non-standard layouts. 0.2.2: Purge stale Write(path) deny rules on re-sync. 0.2.1: Fix hook JSON array shape + Edit-only deny rules. 0.2.0: Add Initialize-WayforgeProject. 0.1.0: initial release.'
        }
    }
}
