function Sync-WayforgeHarness {
    <#
    .SYNOPSIS
        Projects the workflow's gates into per-harness configuration.

    .DESCRIPTION
        Ensures the shared gate shim exists, then renders enforcement config for
        each requested harness. All harnesses reuse the same gate shim; only the
        config wrapper (and, for Cursor, the deny dialect) differs.

    .PARAMETER Harness
        One or more harnesses to sync: claude, codex, grok, copilot, cursor,
        opencode, pi, kimi. Defaults to 'claude'. (Kimi hooks are global-only, so
        its output is a snippet to add to ~/.kimi-code/config.toml.)

    .PARAMETER ProjectPath
        A path inside the target repository. Defaults to the current directory.

    .PARAMETER WorkflowName
        A single workflow definition to project. Defaults to all definitions.

    .EXAMPLE
        Sync-WayforgeHarness -Harness claude

        Ensures the shared gate shim exists and (re)generates .claude/settings.json
        from the workflow's gates.
    #>
    [CmdletBinding()]
    [OutputType('PSWayforge.HarnessSync')]
    param(
        [ValidateSet('claude', 'codex', 'grok', 'copilot', 'cursor', 'opencode', 'pi', 'kimi')]
        [string[]] $Harness = @('claude'),

        [string] $ProjectPath = (Get-Location).Path,

        [string] $WorkflowName
    )

    $root = Resolve-WayforgeGitRoot -Path $ProjectPath
    Install-WayforgeGateShim -ProjectRoot $root | Out-Null

    $results = [System.Collections.Generic.List[object]]::new()
    foreach ($h in $Harness) {
        $file = switch ($h) {
            'claude'   { Write-WayforgeClaudeAdapter   -ProjectRoot $root -WorkflowName $WorkflowName }
            'codex'    { Write-WayforgeCodexAdapter     -ProjectRoot $root -WorkflowName $WorkflowName }
            'grok'     { Write-WayforgeGrokAdapter      -ProjectRoot $root -WorkflowName $WorkflowName }
            'copilot'  { Write-WayforgeCopilotAdapter   -ProjectRoot $root -WorkflowName $WorkflowName }
            'cursor'   { Write-WayforgeCursorAdapter    -ProjectRoot $root -WorkflowName $WorkflowName }
            'opencode' { Write-WayforgeOpencodeAdapter  -ProjectRoot $root -WorkflowName $WorkflowName }
            'pi'       { Write-WayforgePiAdapter        -ProjectRoot $root -WorkflowName $WorkflowName }
            'kimi'     { Write-WayforgeKimiAdapter      -ProjectRoot $root -WorkflowName $WorkflowName }
        }
        $results.Add([PSCustomObject]@{ PSTypeName = 'PSWayforge.HarnessSync'; Harness = $h; File = $file }) | Out-Null
    }

    return $results.ToArray()
}
