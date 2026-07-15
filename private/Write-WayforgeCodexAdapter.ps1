function Write-WayforgeCodexAdapter {
    <#
    .SYNOPSIS
        Projects pre-tool/stop gates into Codex CLI hooks (.codex/hooks.json).
    .DESCRIPTION
        Registers the shared gate shim on PreToolUse (and Stop) using Codex's
        Claude-compatible hook contract. Merges into any existing .codex/hooks.json.
        Project hooks require a one-time `/hooks` trust in Codex.
    #>
    param([string] $ProjectRoot, [string] $WorkflowName)

    $set    = Get-WayforgeGateSet -Root $ProjectRoot -WorkflowName $WorkflowName
    $stages = Get-WayforgeStages -Gates $set.Gates

    $owned = @{}
    if ($stages['pre-tool']) {
        $owned['PreToolUse'] = @([ordered]@{
                matcher = 'Bash|Edit|Write'
                hooks   = @([ordered]@{ type = 'command'; command = (Get-WayforgeGateCommand -Stage 'pre-tool' -AsHook 'codex'); timeout = 60 })
            })
    }
    if ($stages['stop']) {
        $owned['Stop'] = @([ordered]@{
                hooks = @([ordered]@{ type = 'command'; command = (Get-WayforgeGateCommand -Stage 'stop' -AsHook 'codex'); timeout = 60 })
            })
    }
    if ($owned.Count -eq 0) { return $null }

    return Merge-WayforgeJsonHooks -Path (Join-Path $ProjectRoot '.codex/hooks.json') -OwnedByEvent $owned
}
