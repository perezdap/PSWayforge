function Write-WayforgeGrokAdapter {
    <#
    .SYNOPSIS
        Projects pre-tool/stop gates into a Grok Build hook file
        (.grok/hooks/wayforge.json).
    .DESCRIPTION
        Uses Grok's Claude-compatible PreToolUse hook contract. Written as a
        dedicated file so other .grok/hooks/*.json are untouched. Project hooks
        require a one-time `--trust` / `/hooks-trust` in Grok.
    #>
    param([string] $ProjectRoot, [string] $WorkflowName)

    $set    = Get-WayforgeGateSet -Root $ProjectRoot -WorkflowName $WorkflowName
    $stages = Get-WayforgeStages -Gates $set.Gates

    $hooks = [ordered]@{}
    if ($stages['pre-tool']) {
        $hooks['PreToolUse'] = @([ordered]@{
                matcher = 'Bash|Edit|Write'
                hooks   = @([ordered]@{ type = 'command'; command = (Get-WayforgeGateCommand -Stage 'pre-tool' -AsHook 'grok'); timeout = 60 })
            })
    }
    if ($stages['stop']) {
        $hooks['Stop'] = @([ordered]@{
                hooks = @([ordered]@{ type = 'command'; command = (Get-WayforgeGateCommand -Stage 'stop' -AsHook 'grok'); timeout = 60 })
            })
    }
    if ($hooks.Count -eq 0) { return $null }

    $dir = Join-Path $ProjectRoot '.grok/hooks'
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $path = Join-Path $dir 'wayforge.json'
    ([ordered]@{ hooks = $hooks } | ConvertTo-Json -Depth 10) | Set-Content -Path $path -Encoding utf8NoBOM
    return $path
}
