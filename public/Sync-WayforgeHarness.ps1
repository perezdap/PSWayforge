function Sync-WayforgeHarness {
    <#
    .SYNOPSIS
        Projects the workflow's gates into per-harness configuration.

    .DESCRIPTION
        Ensures the shared gate shim exists, then renders enforcement config for
        each requested harness. Currently supports 'claude' (the reference
        projection); further harnesses reuse the same shim with a different
        config wrapper.

    .PARAMETER Harness
        One or more harnesses to sync. Defaults to 'claude'.

    .PARAMETER ProjectPath
        A path inside the target repository. Defaults to the current directory.

    .PARAMETER WorkflowName
        A single workflow definition to project. Defaults to all definitions.
    #>
    [CmdletBinding()]
    param(
        [ValidateSet('claude')]
        [string[]] $Harness = @('claude'),

        [string] $ProjectPath = (Get-Location).Path,

        [string] $WorkflowName
    )

    $root = Resolve-WayforgeGitRoot -Path $ProjectPath
    Install-WayforgeGateShim -ProjectRoot $root | Out-Null

    $results = [System.Collections.Generic.List[object]]::new()
    foreach ($h in $Harness) {
        switch ($h) {
            'claude' {
                $file = Write-WayforgeClaudeAdapter -ProjectRoot $root -WorkflowName $WorkflowName
                $results.Add([PSCustomObject]@{ PSTypeName = 'PSWayforge.HarnessSync'; Harness = 'claude'; File = $file }) | Out-Null
            }
        }
    }

    return $results.ToArray()
}
