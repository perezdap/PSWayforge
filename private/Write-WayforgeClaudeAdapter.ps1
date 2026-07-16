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
            # Claude's Edit(path) rule covers ALL file-editing tools (Edit, Write,
            # MultiEdit, NotebookEdit); there is no Write(path) permission rule, so
            # emitting one is ignored (and warned about). Paths -> Edit; commands -> Bash.
            foreach ($path in @(Get-WayforgeField $forbid 'path' | Where-Object { $_ })) {
                $rule = "Edit($path)"
                if (-not $denies.Contains($rule)) { $denies.Add($rule) }
            }
            foreach ($command in @(Get-WayforgeField $forbid 'command' | Where-Object { $_ })) {
                $rule = "Bash($command)"
                if (-not $denies.Contains($rule)) { $denies.Add($rule) }
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

    # Merge into any existing settings.json rather than replacing it, so unrelated
    # hooks, permissions, and other keys the user maintains are preserved. Our own
    # entries (identified by the gate.ps1 command) are refreshed idempotently.
    $claudeDir    = Join-Path $ProjectRoot '.claude'
    $settingsPath = Join-Path $claudeDir 'settings.json'

    $settings = @{}
    if (Test-Path $settingsPath -PathType Leaf) {
        try { $settings = Get-Content $settingsPath -Raw | ConvertFrom-Json -AsHashtable }
        catch { Write-Warning "Existing .claude/settings.json is not valid JSON; it will be replaced."; $settings = @{} }
    }
    if ($null -eq $settings) { $settings = @{} }

    if ($denies.Count -gt 0) {
        if ($settings['permissions'] -isnot [System.Collections.IDictionary]) { $settings['permissions'] = @{} }
        # Purge stale Write(path) rules that our Edit(path) rules now supersede.
        # Older versions (< 0.2.1) emitted Write(path), which Claude ignores and
        # warns about; the merge would otherwise preserve them forever.
        $superseded = @($denies | Where-Object { $_ -like 'Edit(*' } | ForEach-Object { $_ -replace '^Edit\(', 'Write(' })
        $merged = [System.Collections.Generic.List[string]]::new()
        foreach ($d in @($settings['permissions']['deny'])) {
            if (-not $d -or $superseded -contains $d) { continue }
            if (-not $merged.Contains($d)) { $merged.Add($d) | Out-Null }
        }
        foreach ($d in $denies) { if (-not $merged.Contains($d)) { $merged.Add($d) | Out-Null } }
        $settings['permissions']['deny'] = $merged.ToArray()
    }

    if ($hooks.Count -gt 0) {
        if ($settings['hooks'] -isnot [System.Collections.IDictionary]) { $settings['hooks'] = @{} }
        foreach ($event in $hooks.Keys) {
            # Keep the user's own entries for this event; drop any prior Wayforge
            # entry (whose command references gate.ps1) before adding the current one.
            $kept = foreach ($entry in (@($settings['hooks'][$event]) | Where-Object { $_ })) {
                $cmds = @($entry.hooks) | ForEach-Object { $_.command }
                if ($cmds -match 'gate\.ps1') { continue }
                $entry
            }
            # Wrap the whole pipeline in @() so a single entry stays an ARRAY;
            # otherwise ConvertTo-Json emits an object and Claude ignores the hook.
            $settings['hooks'][$event] = @(@(@($kept) + @($hooks[$event])) | Where-Object { $_ })
        }
    }

    if (-not (Test-Path $claudeDir)) { New-Item -ItemType Directory -Path $claudeDir -Force | Out-Null }
    ($settings | ConvertTo-Json -Depth 8) | Set-Content -Path $settingsPath -Encoding utf8NoBOM
    return $settingsPath
}
