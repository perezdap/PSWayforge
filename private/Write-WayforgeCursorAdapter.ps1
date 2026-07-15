function Write-WayforgeCursorAdapter {
    <#
    .SYNOPSIS
        Projects pre-tool gates into Cursor hooks (.cursor/hooks.json).
    .DESCRIPTION
        Registers the shared gate shim on beforeShellExecution (fires in the
        cursor-agent CLI, covering the commit path) and preToolUse (IDE), using
        Cursor's distinct deny dialect (`-AsHook cursor`). failClosed keeps the
        gate binding on hook crash/timeout. Merges into any existing hooks.json.
    #>
    param([string] $ProjectRoot, [string] $WorkflowName)

    $set    = Get-WayforgeGateSet -Root $ProjectRoot -WorkflowName $WorkflowName
    $stages = Get-WayforgeStages -Gates $set.Gates
    if (-not $stages['pre-tool']) { return $null }

    $command = Get-WayforgeGateCommand -Stage 'pre-tool' -AsHook 'cursor'
    $entry   = [ordered]@{ command = $command; timeout = 60; failClosed = $true }
    $owned   = @{
        beforeShellExecution = @($entry)
        preToolUse           = @($entry)
    }

    return Merge-WayforgeJsonHooks -Path (Join-Path $ProjectRoot '.cursor/hooks.json') -OwnedByEvent $owned -TopLevelVersion
}
