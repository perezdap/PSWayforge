function Update-WayforgeAgentsFile {
    <#
    .SYNOPSIS
        Renders each workflow's `steps` into a managed block in AGENTS.md.

    .DESCRIPTION
        Projects the narrative process (the `steps` in .workflow/definitions/*.yaml)
        into AGENTS.md, between <!-- wayforge:workflow:start --> and
        <!-- wayforge:workflow:end --> markers. It is non-destructive: content
        outside the markers is preserved, and the block is refreshed idempotently
        on every run. AGENTS.md is created if it does not exist.

    .PARAMETER ProjectPath
        A path inside the project. Defaults to the current directory.

    .PARAMETER WorkflowName
        A single workflow to render. Defaults to every definition that has steps.

    .EXAMPLE
        Update-WayforgeAgentsFile

        Refreshes the workflow section of AGENTS.md from the current definitions.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string])]
    param(
        [string] $ProjectPath = (Get-Location).Path,
        [string] $WorkflowName
    )

    $root = Resolve-WayforgeGitRoot -Path $ProjectPath

    $definitionsDir = Join-Path $root '.workflow/definitions'
    $names = if ($WorkflowName) {
        , $WorkflowName
    }
    elseif (Test-Path $definitionsDir) {
        Get-ChildItem -Path $definitionsDir -Filter '*.yaml' | ForEach-Object { $_.BaseName }
    }
    else {
        @()
    }

    $sections = [System.Collections.Generic.List[string]]::new()
    foreach ($name in $names) {
        $wf    = Get-WayforgeWorkflow -Name $name -ProjectPath $root
        $steps = @(Get-WayforgeField $wf 'steps' | Where-Object { $_ })   # @() filters an absent 'steps' (avoids @($null) count 1)
        if ($steps.Count -eq 0) { continue }

        $lines = [System.Collections.Generic.List[string]]::new()
        $lines.Add("### Workflow: $name") | Out-Null
        $desc = Get-WayforgeField $wf 'description'
        if ($desc) { $lines.Add('') | Out-Null; $lines.Add([string]$desc) | Out-Null }
        $lines.Add('') | Out-Null

        $index = 1
        foreach ($step in $steps) {
            $id       = Get-WayforgeField $step 'id' "step$index"
            $stepName = Get-WayforgeField $step 'name' $id
            $line     = '{0}. **{1}** (`{2}`)' -f $index, $stepName, $id     # single-quoted: backticks literal
            $stepDesc = Get-WayforgeField $step 'description'
            if ($stepDesc) { $line += " — $stepDesc" }
            $lines.Add($line) | Out-Null
            $index++
        }
        $sections.Add(($lines -join "`n")) | Out-Null
    }

    if ($sections.Count -eq 0) { return $null }

    $startMarker = '<!-- wayforge:workflow:start -->'
    $endMarker   = '<!-- wayforge:workflow:end -->'
    $body = @(
        $startMarker
        '## Workflow'
        ''
        'The steps below are enforced by PSWayforge gates. This section is generated from `.workflow/definitions/`; edits between the markers are overwritten.'
        ''
        ($sections -join "`n`n")
        $endMarker
    ) -join "`n"

    $agentsPath = Join-Path $root 'AGENTS.md'
    $content = if (Test-Path $agentsPath -PathType Leaf) { Get-Content $agentsPath -Raw } else { '' }

    $startIdx = $content.IndexOf($startMarker)
    $endIdx   = $content.IndexOf($endMarker)
    $new = if ($startIdx -ge 0 -and $endIdx -gt $startIdx) {
        $content.Substring(0, $startIdx) + $body + $content.Substring($endIdx + $endMarker.Length)
    }
    elseif ([string]::IsNullOrWhiteSpace($content)) {
        "# Agent workspace`n`n$body`n"
    }
    else {
        $content.TrimEnd() + "`n`n" + $body + "`n"
    }

    if ($PSCmdlet.ShouldProcess($agentsPath, 'Render workflow section into AGENTS.md')) {
        Set-Content -Path $agentsPath -Value $new -Encoding utf8NoBOM
    }
    return $agentsPath
}
