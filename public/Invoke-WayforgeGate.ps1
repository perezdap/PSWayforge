function Invoke-WayforgeGate {
    <#
    .SYNOPSIS
        Evaluates a workflow's gates for a stage and reports pass/block.

    .DESCRIPTION
        The single gate engine every enforcement point calls — harness hooks,
        git pre-commit/pre-push hooks, and CI. It loads the gate definitions from
        .workflow/definitions, derives the changeset for the stage, evaluates each
        applicable gate, and returns a PSWayforge.GateReport.

        With -AsHook, it also writes the caller's dialect (deny JSON for harness
        hooks, a human report for git/ci) and sets the report's ExitCode so a
        calling shim can `exit $report.ExitCode`.

        The evaluation is wrapped so that any internal error (for example a
        malformed workflow definition) fails closed: the engine emits a
        block decision through the caller's dialect rather than crashing.

    .PARAMETER Stage
        The enforcement stage: pre-tool, stop, pre-commit, pre-push, or ci.

    .PARAMETER AsHook
        The caller dialect. Harness values (claude/codex/kimi/grok/copilot,
        cursor, opencode, pi) emit deny output + exit 2; git/ci emit a human
        report + exit 1 on block; 'none' (default) reports only.

    .PARAMETER EventJson
        The harness event payload (for pre-tool/stop), typically read from stdin.

    .PARAMETER ProjectPath
        A path inside the target repository. Defaults to the current directory;
        the git top-level is resolved from it.

    .PARAMETER WorkflowName
        A single workflow definition to evaluate. Defaults to every definition in
        .workflow/definitions.

    .PARAMETER ChangeSet
        Overrides changeset derivation (mainly for testing).

    .EXAMPLE
        Invoke-WayforgeGate -Stage pre-commit -AsHook git

        Evaluates the pre-commit gates for the current repository, prints a
        report, and returns a report whose ExitCode is non-zero if any
        block-severity gate failed (so a git hook can abort the commit).

    .EXAMPLE
        '{"tool_name":"Edit","tool_input":{"file_path":"src/a.ps1"}}' |
            & { Invoke-WayforgeGate -Stage pre-tool -AsHook claude -EventJson ([Console]::In.ReadToEnd()) }

        Evaluates the mid-session gates for a Claude Edit and emits a Claude
        permission-decision payload (deny + exit 2) when blocked.
    #>
    [CmdletBinding()]
    [OutputType('PSWayforge.GateReport')]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('pre-tool', 'stop', 'pre-commit', 'pre-push', 'ci')]
        [string] $Stage,

        [ValidateSet('claude', 'codex', 'kimi', 'grok', 'copilot', 'cursor', 'opencode', 'pi', 'git', 'ci', 'none')]
        [string] $AsHook = 'none',

        [string] $EventJson,

        [string] $ProjectPath = (Get-Location).Path,

        [string] $WorkflowName,

        [string[]] $ChangeSet
    )

    try {
        $root = Resolve-WayforgeGitRoot -Path $ProjectPath

        $set    = Get-WayforgeGateSet -Root $root -WorkflowName $WorkflowName
        $gates  = $set.Gates
        $scopes = $set.Scopes

        $actionTool    = $null
        $actionCommand = $null
        if (-not $PSBoundParameters.ContainsKey('ChangeSet')) {
            if ($Stage -in @('pre-tool', 'stop')) {
                $ctx           = Get-WayforgeActionContext -EventJson $EventJson -Root $root
                $ChangeSet     = $ctx.Paths
                $actionTool    = $ctx.ToolName
                $actionCommand = $ctx.Command
            }
            else {
                $ChangeSet = Get-WayforgeChangeSet -Stage $Stage -Root $root -EventJson $EventJson
            }
        }

        $results = [System.Collections.Generic.List[object]]::new()
        foreach ($gate in $gates) {
            $on = @(Get-WayforgeField $gate 'on')
            if ($Stage -notin $on) { continue }

            $id       = Get-WayforgeField $gate 'id' '(unnamed)'
            $desc     = Get-WayforgeField $gate 'description' $id
            $severity = Get-WayforgeField $gate 'severity' 'block'
            $when     = Get-WayforgeField $gate 'when' 'always'
            $check    = Get-WayforgeField $gate 'check'

            if (-not (Test-WayforgeChangeCondition -Condition $when -ChangeSet $ChangeSet -Scopes $scopes)) {
                $results.Add((New-WayforgeGateResult -Id $id -Severity $severity -Status 'skip' -Message "skipped ($when = false)")) | Out-Null
                continue
            }

            $eval   = Invoke-WayforgeCheck -Check $check -Root $root -Description $desc -ChangeSet $ChangeSet -ToolName $actionTool -Command $actionCommand
            $status = if ($eval.Ok) { 'pass' } elseif ($severity -eq 'warn') { 'warn' } else { 'fail' }
            $results.Add((New-WayforgeGateResult -Id $id -Severity $severity -Status $status -Message $eval.Message -Detail $eval.Detail)) | Out-Null
        }

        $blocked = @($results | Where-Object Status -eq 'fail').Count -gt 0
        $report = [PSCustomObject]@{
            PSTypeName = 'PSWayforge.GateReport'
            Stage      = $Stage
            Blocked    = $blocked
            Results    = $results.ToArray()
            ExitCode   = 0
        }
    }
    catch {
        # Fail closed within our control: never let an internal error escape past
        # the dialect serializer. The caller receives a well-formed block.
        $errResult = New-WayforgeGateResult -Id 'wayforge-engine-error' -Severity 'block' -Status 'fail' `
            -Message 'Wayforge gate engine error' -Detail $_.Exception.Message
        $report = [PSCustomObject]@{
            PSTypeName = 'PSWayforge.GateReport'
            Stage      = $Stage
            Blocked    = $true
            Results    = @($errResult)
            ExitCode   = 0
        }
    }

    $report.ExitCode = Write-WayforgeGateDialect -Report $report -AsHook $AsHook
    return $report
}
