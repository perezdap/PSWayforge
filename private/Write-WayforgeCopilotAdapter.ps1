function Write-WayforgeCopilotAdapter {
    <#
    .SYNOPSIS
        Projects pre-tool/stop gates into a GitHub Copilot hook file
        (.github/hooks/wayforge.json).
    .DESCRIPTION
        Uses Copilot's preToolUse command-hook contract (read by the Copilot CLI,
        VS Code, and the cloud agent). Written as a dedicated file. Copilot does
        not support a matcher on preToolUse, so the gate engine filters by tool.
    #>
    param([string] $ProjectRoot, [string] $WorkflowName)

    $set    = Get-WayforgeGateSet -Root $ProjectRoot -WorkflowName $WorkflowName
    $stages = Get-WayforgeStages -Gates $set.Gates

    $hooks = [ordered]@{}
    if ($stages['pre-tool']) {
        $hooks['preToolUse'] = @([ordered]@{ type = 'command'; command = (Get-WayforgeGateCommand -Stage 'pre-tool' -AsHook 'copilot'); cwd = '.'; timeoutSec = 60 })
    }
    if ($stages['stop']) {
        $hooks['stop'] = @([ordered]@{ type = 'command'; command = (Get-WayforgeGateCommand -Stage 'stop' -AsHook 'copilot'); cwd = '.'; timeoutSec = 60 })
    }
    if ($hooks.Count -eq 0) { return $null }

    $dir = Join-Path $ProjectRoot '.github/hooks'
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $path = Join-Path $dir 'wayforge.json'
    ([ordered]@{ version = 1; hooks = $hooks } | ConvertTo-Json -Depth 10) | Set-Content -Path $path -Encoding utf8NoBOM
    return $path
}
