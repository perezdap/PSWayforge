function Write-WayforgeClaudeAdapter {
    <#
    .SYNOPSIS
        Projects a workflow's gates into .claude/settings.json.
    .DESCRIPTION
        Registers the shared gate shim at PreToolUse / Stop for gates whose
        `on` includes pre-tool / stop, and projects `forbid` gates into
        permissions.deny (fail-closed). Only the stages Claude can enforce are
        consumed here; pre-commit/pre-push/ci belong to the git + CI adapter.
    #>
    param([string] $ProjectRoot, [string] $WorkflowName)

    $set   = Get-WayforgeGateSet -Root $ProjectRoot -WorkflowName $WorkflowName
    $gates = $set.Gates

    $hasPreTool = $false
    $hasStop    = $false
    $denies     = [System.Collections.Generic.List[string]]::new()

    foreach ($gate in $gates) {
        $on = @(Get-WayforgeField $gate 'on')
        if ('pre-tool' -in $on) { $hasPreTool = $true }
        if ('stop' -in $on)     { $hasStop = $true }

        $forbid = Get-WayforgeField (Get-WayforgeField $gate 'check') 'forbid'
        if ($forbid) {
            $paths = @(Get-WayforgeField $forbid 'path')
            $tools = @(Get-WayforgeField $forbid 'tool')
            if (-not $tools) { $tools = @('edit', 'write') }
            foreach ($path in $paths) {
                foreach ($tool in $tools) {
                    $cap = switch ($tool) {
                        'edit'  { 'Edit' }  'write' { 'Write' }  'bash' { 'Bash' }
                        default { (Get-Culture).TextInfo.ToTitleCase($tool) }
                    }
                    $denies.Add("$cap($path)")
                }
            }
        }
    }

    # Literal ${CLAUDE_PROJECT_DIR} must survive into the JSON (single-quoted).
    $shim = '"${CLAUDE_PROJECT_DIR}/.workflow/hooks/gate.ps1"'
    $mkCommand = { param($stage) "pwsh -NoProfile -File $shim -Stage $stage -AsHook claude" }

    $hooks = [ordered]@{}
    if ($hasPreTool) {
        $hooks['PreToolUse'] = @(
            [ordered]@{
                matcher = 'Edit|Write|MultiEdit|NotebookEdit|Bash'
                hooks   = @([ordered]@{ type = 'command'; command = (& $mkCommand 'pre-tool') })
            }
        )
    }
    if ($hasStop) {
        $hooks['Stop'] = @(
            [ordered]@{ hooks = @([ordered]@{ type = 'command'; command = (& $mkCommand 'stop') }) }
        )
    }

    $settings = [ordered]@{}
    if ($denies.Count -gt 0) { $settings['permissions'] = [ordered]@{ deny = $denies.ToArray() } }
    if ($hooks.Count -gt 0)  { $settings['hooks'] = $hooks }

    $claudeDir = Join-Path $ProjectRoot '.claude'
    if (-not (Test-Path $claudeDir)) { New-Item -ItemType Directory -Path $claudeDir -Force | Out-Null }

    $settingsPath = Join-Path $claudeDir 'settings.json'
    ($settings | ConvertTo-Json -Depth 8) | Set-Content -Path $settingsPath -Encoding utf8NoBOM
    return $settingsPath
}
