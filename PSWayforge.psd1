@{
    RootModule           = 'PSWayforge.psm1'
    ModuleVersion        = '0.2.1'
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
            ReleaseNotes             = '0.2.1: Fix Claude/Codex/Cursor hook config emitting a single matcher as a JSON object instead of an array (Claude ignored the hook); Claude/Kimi deny rules now use Edit(path) only (Write(path) is not a valid rule). 0.2.0: Add Initialize-WayforgeProject. 0.1.0: initial release.'
        }
    }
}
