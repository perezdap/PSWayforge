@{
    RootModule           = 'PSWayforge.psm1'
    ModuleVersion        = '0.1.0'
    GUID                 = 'cc6c71de-c415-442a-9170-9589bfa5eb0a'
    Author               = 'PSWayforge Contributors'
    CompanyName          = ''
    Copyright            = '(c) PSWayforge Contributors. All rights reserved.'
    Description          = 'Scaffolds agent-agnostic project workspaces with AGENTS.md, skills, workflows, hooks, and schemas.'
    PowerShellVersion    = '7.3'
    CompatiblePSEditions = @('Core')
    FunctionsToExport    = @(
        'New-WayforgeProject'
        'Invoke-WayforgeHook'
        'Test-WayforgeSchema'
        'Get-WayforgeWorkflow'
        'Invoke-WayforgeGate'
        'Register-WayforgeHooks'
        'Sync-WayforgeHarness'
    )
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @()
    PrivateData          = @{
        PSData = @{
            Tags       = @('agent', 'workspace', 'scaffold', 'workflow', 'ai')
            LicenseUri = 'https://github.com/perezdap/PSWayforge/blob/main/LICENSE'
            ProjectUri = 'https://github.com/perezdap/PSWayforge'
        }
    }
}
