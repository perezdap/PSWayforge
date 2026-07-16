# Internal helpers for the Wayforge gate engine (Invoke-WayforgeGate).
# Kept in one file; each function is dot-sourced by PSWayforge.psm1.

function Get-WayforgeField {
    <#
    .SYNOPSIS
        Reads a field from a dictionary (powershell-yaml / minimal parser) or a
        PSCustomObject, returning a default when absent.
    #>
    param($Object, [string] $Name, $Default = $null)

    if ($null -eq $Object) { return $Default }
    if ($Object -is [System.Collections.IDictionary]) {
        if ($Object.Contains($Name)) { return $Object[$Name] }
        return $Default
    }
    $prop = $Object.PSObject.Properties[$Name]
    if ($prop) { return $prop.Value }
    return $Default
}

function Get-WayforgeGateSet {
    <#
    .SYNOPSIS
        Loads the gates and scopes from the selected workflow definition(s).
    #>
    param([string] $Root, [string] $WorkflowName)

    $definitionsDir = Join-Path $Root '.workflow/definitions'
    $names = if ($WorkflowName) {
        , $WorkflowName
    }
    elseif (Test-Path $definitionsDir) {
        Get-ChildItem -Path $definitionsDir -Filter '*.yaml' | ForEach-Object { $_.BaseName }
    }
    else {
        @()
    }

    $gates  = [System.Collections.Generic.List[object]]::new()
    $scopes = @{}
    foreach ($name in $names) {
        $wf = Get-WayforgeWorkflow -Name $name -ProjectPath $Root

        $wfScopes = Get-WayforgeField $wf 'scopes'
        if ($wfScopes -is [System.Collections.IDictionary]) {
            foreach ($key in $wfScopes.Keys) { $scopes[$key] = @(Get-WayforgeField $wfScopes $key) }
        }

        foreach ($gate in @(Get-WayforgeField $wf 'gates')) {
            if ($null -ne $gate) { $gates.Add($gate) }
        }
    }

    return [PSCustomObject]@{ Gates = $gates.ToArray(); Scopes = $scopes }
}

function Resolve-WayforgeGitRoot {
    <#
    .SYNOPSIS
        Returns the git top-level for a path, falling back to the resolved path.
    #>
    param([string] $Path)

    $p = (Resolve-Path -Path $Path -ErrorAction SilentlyContinue).Path
    if (-not $p) { $p = $Path }

    $top = & git -C $p rev-parse --show-toplevel 2>$null
    if ($LASTEXITCODE -eq 0 -and $top) { return $top.Trim() }
    return $p
}

function Get-WayforgeDefaultBase {
    <#
    .SYNOPSIS
        Resolves the CI base ref: the remote's default branch, else origin/main
        or origin/master if present. Callers fall back to the full tree if the
        returned ref is unreachable.
    #>
    param([string] $Root)

    $ref = & git -C $Root symbolic-ref --quiet refs/remotes/origin/HEAD 2>$null
    if ($LASTEXITCODE -eq 0 -and $ref) {
        return ($ref -replace '^refs/remotes/', '').Trim()
    }
    foreach ($candidate in 'origin/main', 'origin/master') {
        & git -C $Root rev-parse --verify --quiet $candidate > $null 2>&1
        if ($LASTEXITCODE -eq 0) { return $candidate }
    }
    return 'origin/main'
}

function Convert-WayforgeGlobToRegex {
    <#
    .SYNOPSIS
        Converts a path glob (supporting **, *, ?) into an anchored regex.
    .DESCRIPTION
        `**/` matches any number of leading path segments (including zero),
        `**` matches across separators, `*` matches within a segment, `?` one char.
    #>
    param([string] $Glob)

    $g = $Glob -replace '\\', '/'
    $e = [regex]::Escape($g)
    $e = $e -replace '\\\*\\\*/', '(?:.*/)?'   # **/  -> optional path prefix
    $e = $e -replace '\\\*\\\*', '.*'          # **   -> anything
    $e = $e -replace '\\\*', '[^/]*'           # *    -> within a segment
    $e = $e -replace '\\\?', '[^/]'            # ?    -> one non-separator char
    return '^' + $e + '$'
}

function Test-WayforgeGlobMatch {
    param([string] $Path, [string] $Glob)

    if (-not $Path -or -not $Glob) { return $false }
    $rx = Convert-WayforgeGlobToRegex -Glob $Glob
    return [regex]::IsMatch(($Path -replace '\\', '/'), $rx,
        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
}

function Test-WayforgePathInScope {
    <#
    .SYNOPSIS
        Tests whether a path is in a scope: it must match at least one include
        glob and no exclude glob. Globs prefixed with '!' are excludes.
    #>
    param([string] $Path, $Globs)

    $globList = @($Globs | Where-Object { $_ })
    $includes = @($globList | Where-Object { -not ([string]$_).StartsWith('!') })
    $excludes = @($globList | Where-Object { ([string]$_).StartsWith('!') } | ForEach-Object { ([string]$_).Substring(1) })

    $included = $false
    foreach ($glob in $includes) {
        if (Test-WayforgeGlobMatch -Path $Path -Glob $glob) { $included = $true; break }
    }
    if (-not $included) { return $false }

    foreach ($glob in $excludes) {
        if (Test-WayforgeGlobMatch -Path $Path -Glob $glob) { return $false }
    }
    return $true
}

function Test-WayforgeChangeCondition {
    <#
    .SYNOPSIS
        Evaluates a gate `when` predicate against a changeset.
    .DESCRIPTION
        Supports: always, changes_touch(<scope>), changes_only(<scope>). A scope's
        globs may include '!'-prefixed excludes (a path is in scope if it matches
        an include and no exclude). Unknown predicates are treated as applicable
        (fail-safe for block gates).
    #>
    param([string] $Condition, [string[]] $ChangeSet, $Scopes)

    if ([string]::IsNullOrWhiteSpace($Condition) -or $Condition -eq 'always') {
        return $true
    }

    if ($Condition -match '^\s*changes_touch\(\s*(\w+)\s*\)\s*$') {
        $globs = @(if ($Scopes -is [System.Collections.IDictionary] -and $Scopes.Contains($matches[1])) { $Scopes[$matches[1]] })
        foreach ($f in $ChangeSet) {
            if (Test-WayforgePathInScope -Path $f -Globs $globs) { return $true }
        }
        return $false
    }

    if ($Condition -match '^\s*changes_only\(\s*(\w+)\s*\)\s*$') {
        if (-not $ChangeSet -or @($ChangeSet).Count -eq 0) { return $false }
        $globs = @(if ($Scopes -is [System.Collections.IDictionary] -and $Scopes.Contains($matches[1])) { $Scopes[$matches[1]] })
        foreach ($f in $ChangeSet) {
            if (-not (Test-WayforgePathInScope -Path $f -Globs $globs)) { return $false }
        }
        return $true
    }

    Write-Warning "Unknown gate predicate '$Condition'; treating as applicable."
    return $true
}

function Get-WayforgeChangeSet {
    <#
    .SYNOPSIS
        Derives the changeset (relative, forward-slash paths) for a stage.
    #>
    param([string] $Stage, [string] $Root, [string] $EventJson)

    switch ($Stage) {
        'pre-commit' {
            $out = & git -C $Root diff --cached --name-only --diff-filter=ACMR 2>$null
            return @($out | Where-Object { $_ })
        }
        'pre-push' {
            # The calling shim reads stdin once and passes it via -EventJson
            # (git's pre-push sends "<lref> <lsha> <rref> <rsha>" lines, not JSON).
            $files = [System.Collections.Generic.List[string]]::new()
            $emptyTree = '4b825dc642cb6eb9a060e54bf8d69288fbee4904'   # git's canonical empty tree
            $stdin = if ($EventJson) { $EventJson } else { '' }
            foreach ($line in ($stdin -split "`r?`n")) {
                $parts = $line -split '\s+'
                if ($parts.Count -ge 4) {
                    $localSha = $parts[1]; $remoteSha = $parts[3]
                    if ($remoteSha -match '^0+$') {
                        # New remote branch: diff against the merge-base with the
                        # default branch, else the empty tree (all files). Never
                        # diff the tip alone, which compares against the (clean)
                        # working tree and yields no changes -> fail-open.
                        $base = Get-WayforgeDefaultBase -Root $Root
                        $mergeBase = (& git -C $Root merge-base $base $localSha 2>$null)
                        $from = if ($LASTEXITCODE -eq 0 -and $mergeBase) { $mergeBase.Trim() } else { $emptyTree }
                        $out = & git -C $Root diff --name-only $from $localSha 2>$null
                    }
                    else {
                        $out = & git -C $Root diff --name-only "$remoteSha..$localSha" 2>$null
                    }
                    $out | Where-Object { $_ } | ForEach-Object { $files.Add($_) }
                }
            }
            return @($files | Select-Object -Unique)
        }
        'ci' {
            $base = if ($env:WAYFORGE_BASE_REF) { $env:WAYFORGE_BASE_REF } else { Get-WayforgeDefaultBase -Root $Root }
            $out = & git -C $Root diff --name-only "$base...HEAD" 2>$null
            if ($LASTEXITCODE -ne 0) {
                # Base unreachable: fall back to the full tracked tree so gates
                # still evaluate (fail-safe) instead of an empty diff (fail-open).
                $out = & git -C $Root ls-files 2>$null
            }
            return @($out | Where-Object { $_ })
        }
        default {
            # pre-tool / stop paths come from Get-WayforgeActionContext, which
            # fails closed on a malformed payload rather than swallowing it.
            return @()
        }
    }
}

function Get-WayforgeActionContext {
    <#
    .SYNOPSIS
        Parses a harness event payload into { Paths, ToolName, Command } for the
        pre-tool / stop stages.
    .DESCRIPTION
        This is the single event-normalization boundary before the gate engine.
        Harnesses use different field names for the same concepts, so it accepts
        all known variants: the tool name (tool_name / toolName), the arguments
        container (tool_input / toolArgs / tool_args / input), the file path
        (file_path / filePath / path, plus multi-file arrays), and the command
        (in the args container or top-level, as Cursor's beforeShellExecution
        sends it). An absent payload yields an empty context; a non-empty but
        malformed payload throws, so the engine fails closed (deny).
    #>
    param([string] $EventJson, [string] $Root)

    $context = [PSCustomObject]@{ Paths = @(); ToolName = $null; Command = $null }
    if ([string]::IsNullOrWhiteSpace($EventJson)) { return $context }

    $ev = $EventJson | ConvertFrom-Json          # malformed -> throw -> fail-closed

    $context.ToolName = if ($ev.tool_name) { $ev.tool_name } elseif ($ev.toolName) { $ev.toolName } else { $null }

    # The tool's arguments live under different keys across harnesses.
    $toolArgs = $null
    foreach ($key in 'tool_input', 'toolArgs', 'tool_args', 'input') {
        $value = Get-WayforgeField $ev $key
        if ($null -ne $value) { $toolArgs = $value; break }
    }

    $rawPaths = [System.Collections.Generic.List[string]]::new()
    if ($toolArgs) {
        $context.Command = Get-WayforgeField $toolArgs 'command'
        foreach ($key in 'file_path', 'filePath', 'path', 'filepath') {
            $value = Get-WayforgeField $toolArgs $key
            if ($value) { $rawPaths.Add([string]$value) | Out-Null }
        }
        foreach ($key in 'file_paths', 'filePaths', 'paths', 'files') {
            $value = Get-WayforgeField $toolArgs $key
            if ($value) { foreach ($item in @($value)) { if ($item) { $rawPaths.Add([string]$item) | Out-Null } } }
        }
    }

    # Cursor's beforeShellExecution puts the command at the top level (no args container).
    if (-not $context.Command -and $ev.command) {
        $context.Command = $ev.command
        if (-not $context.ToolName) { $context.ToolName = 'Bash' }
    }

    if ($rawPaths.Count -gt 0) {
        $rootNorm = ($Root -replace '\\', '/').TrimEnd('/') + '/'
        $context.Paths = @($rawPaths | ForEach-Object {
                $rel = $_ -replace '\\', '/'
                if ($rel.StartsWith($rootNorm, [StringComparison]::OrdinalIgnoreCase)) { $rel = $rel.Substring($rootNorm.Length) }
                $rel
            })
    }

    return $context
}

function Get-WayforgeStages {
    <#
    .SYNOPSIS
        Returns a hashtable set of the stages referenced by any gate's `on` list.
    #>
    param($Gates)

    $stages = @{}
    foreach ($gate in $Gates) {
        foreach ($stage in @(Get-WayforgeField $gate 'on')) { if ($stage) { $stages[$stage] = $true } }
    }
    return $stages
}

function Get-WayforgeGateCommand {
    <#
    .SYNOPSIS
        Builds the shell command a harness hook runs to invoke the shared gate
        shim for a stage and dialect.
    #>
    param([string] $Stage, [string] $AsHook)
    return "pwsh -NoProfile -File .workflow/hooks/gate.ps1 -Stage $Stage -AsHook $AsHook"
}

function Merge-WayforgeJsonHooks {
    <#
    .SYNOPSIS
        Merges Wayforge-owned hook entries into a JSON hooks config, preserving
        the user's other events/entries. Our entries (identified by a marker in
        their serialized form, e.g. 'gate.ps1') are refreshed idempotently.
    #>
    param(
        [string] $Path,
        [hashtable] $OwnedByEvent,
        [string] $Marker = 'gate.ps1',
        [switch] $TopLevelVersion
    )

    $doc = @{}
    if (Test-Path $Path -PathType Leaf) {
        try { $doc = Get-Content $Path -Raw | ConvertFrom-Json -AsHashtable }
        catch { Write-Warning "Existing '$Path' is not valid JSON; it will be replaced."; $doc = @{} }
    }
    if ($null -eq $doc) { $doc = @{} }
    if ($TopLevelVersion -and -not $doc.ContainsKey('version')) { $doc['version'] = 1 }
    if ($doc['hooks'] -isnot [System.Collections.IDictionary]) { $doc['hooks'] = @{} }

    foreach ($event in $OwnedByEvent.Keys) {
        $kept = foreach ($entry in (@($doc['hooks'][$event]) | Where-Object { $_ })) {
            if (($entry | ConvertTo-Json -Depth 10 -Compress) -match [regex]::Escape($Marker)) { continue }
            $entry
        }
        # Wrap the whole pipeline in @() so a single entry stays an ARRAY;
        # otherwise ConvertTo-Json emits an object and the harness ignores the hook.
        $doc['hooks'][$event] = @(@(@($kept) + @($OwnedByEvent[$event])) | Where-Object { $_ })
    }

    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    ($doc | ConvertTo-Json -Depth 12) | Set-Content -Path $Path -Encoding utf8NoBOM
    return $Path
}

function ConvertTo-WayforgeArgList {
    <#
    .SYNOPSIS
        Splits a command line into argument tokens, honoring single/double quotes,
        without any shell or PowerShell interpretation.
    #>
    param([string] $CommandLine)

    $tokens = [System.Collections.Generic.List[string]]::new()
    $sb = [System.Text.StringBuilder]::new()
    $quote = $null
    foreach ($ch in $CommandLine.ToCharArray()) {
        if ($quote) {
            if ($ch -eq $quote) { $quote = $null } else { [void]$sb.Append($ch) }
        }
        elseif ($ch -eq '"' -or $ch -eq "'") { $quote = $ch }
        elseif ($ch -eq ' ' -or $ch -eq "`t") {
            if ($sb.Length -gt 0) { $tokens.Add($sb.ToString()) | Out-Null; [void]$sb.Clear() }
        }
        else { [void]$sb.Append($ch) }
    }
    if ($sb.Length -gt 0) { $tokens.Add($sb.ToString()) | Out-Null }
    return $tokens.ToArray()
}

function New-WayforgeGateResult {
    param([string] $Id, [string] $Severity, [string] $Status, [string] $Message, [string] $Detail)
    [PSCustomObject]@{
        PSTypeName = 'PSWayforge.GateResult'
        Id         = $Id
        Severity   = $Severity
        Status     = $Status
        Message    = $Message
        Detail     = $Detail
    }
}

function Invoke-WayforgeRunCheck {
    param([string] $Command, [string] $Shell = 'pwsh', [string] $Root)

    Push-Location $Root
    try {
        switch ($Shell) {
            'sh'     { & sh -c $Command 2>&1 | Out-Null; return $LASTEXITCODE }
            'native' {
                # Direct binary invocation - no shell or PowerShell interpretation
                # of metacharacters. Arguments are passed as a separated list.
                $argv = ConvertTo-WayforgeArgList -CommandLine $Command
                if ($argv.Count -eq 0) { return 0 }
                $exe  = $argv[0]
                $rest = if ($argv.Count -gt 1) { $argv[1..($argv.Count - 1)] } else { @() }
                & $exe @rest 2>&1 | Out-Null
                return $LASTEXITCODE
            }
            default  { & pwsh -NoProfile -Command $Command 2>&1 | Out-Null; return $LASTEXITCODE }
        }
    }
    catch { return 1 }
    finally { Pop-Location }
}

function Invoke-WayforgeCheck {
    <#
    .SYNOPSIS
        Evaluates one gate `check` (requires_artifact | run | forbid) and returns
        an object with Ok/Message/Detail.
    #>
    param(
        $Check, [string] $Root, [string] $Description,
        [string[]] $ChangeSet, [string] $ToolName, [string] $Command
    )

    if ($null -eq $Check) {
        return [PSCustomObject]@{ Ok = $true; Message = $Description; Detail = 'no check' }
    }

    $artifact = Get-WayforgeField $Check 'requires_artifact'
    $run      = Get-WayforgeField $Check 'run'
    $forbid   = Get-WayforgeField $Check 'forbid'

    if ($forbid) {
        # Filter nulls: @(Get-WayforgeField ... 'missing') would be @($null) with
        # Count 1, wrongly registering an (unmatched) dimension.
        $paths    = @(Get-WayforgeField $forbid 'path'    | Where-Object { $_ })
        $tools    = @(Get-WayforgeField $forbid 'tool'    | Where-Object { $_ })
        $commands = @(Get-WayforgeField $forbid 'command' | Where-Object { $_ })

        # AND over the dimensions evaluable in this context. `tool` and `command`
        # only bind mid-session (pre-tool, where a tool/command is in play); at
        # commit/push/ci only `path` binds. Block when every evaluable dimension
        # matches; a rule with no evaluable dimension here does not fire.
        $evaluable = [System.Collections.Generic.List[object]]::new()

        if ($paths.Count) {
            $hit = $null
            foreach ($file in $ChangeSet) {
                foreach ($glob in $paths) {
                    if (Test-WayforgeGlobMatch -Path $file -Glob $glob) { $hit = "path '$file' matches '$glob'"; break }
                }
                if ($hit) { break }
            }
            $evaluable.Add([PSCustomObject]@{ Matched = [bool]$hit; Detail = $hit }) | Out-Null
        }
        if ($tools.Count -and $ToolName) {
            $wanted  = $tools | ForEach-Object { "$_".ToLowerInvariant() }
            $matched = $wanted -contains $ToolName.ToLowerInvariant()
            $evaluable.Add([PSCustomObject]@{ Matched = $matched; Detail = "tool '$ToolName'" }) | Out-Null
        }
        if ($commands.Count -and $Command) {
            $matched = $false
            foreach ($pattern in $commands) { if ($Command -like $pattern) { $matched = $true; break } }
            $evaluable.Add([PSCustomObject]@{ Matched = $matched; Detail = "command '$Command'" }) | Out-Null
        }

        if ($evaluable.Count -gt 0 -and @($evaluable | Where-Object { -not $_.Matched }).Count -eq 0) {
            $why = ($evaluable | ForEach-Object { $_.Detail } | Where-Object { $_ }) -join '; '
            return [PSCustomObject]@{ Ok = $false; Message = $Description; Detail = "forbidden: $why" }
        }
        return [PSCustomObject]@{ Ok = $true; Message = $Description; Detail = 'no forbidden action' }
    }

    if ($artifact) {
        $schema  = Get-WayforgeField $Check 'schema'
        $artPath = Join-Path $Root '.workflow/artifacts' $artifact
        if (-not (Test-Path -Path $artPath -PathType Leaf)) {
            return [PSCustomObject]@{ Ok = $false; Message = $Description; Detail = "missing artifact .workflow/artifacts/$artifact" }
        }
        if ($schema) {
            try {
                $valid = Test-WayforgeSchema -Artifact $artPath -SchemaName $schema -ProjectPath $Root
            }
            catch {
                return [PSCustomObject]@{ Ok = $false; Message = $Description; Detail = "schema error: $($_.Exception.Message)" }
            }
            if (-not $valid) {
                return [PSCustomObject]@{ Ok = $false; Message = $Description; Detail = "artifact '$artifact' fails schema '$schema'" }
            }
        }
        return [PSCustomObject]@{ Ok = $true; Message = $Description; Detail = "artifact '$artifact' present/valid" }
    }

    if ($run) {
        $shell = Get-WayforgeField $Check 'shell' 'pwsh'
        $code  = Invoke-WayforgeRunCheck -Command $run -Shell $shell -Root $Root
        if ($code -eq 0) {
            return [PSCustomObject]@{ Ok = $true; Message = $Description; Detail = 'run passed' }
        }
        return [PSCustomObject]@{ Ok = $false; Message = $Description; Detail = "run exited ${code}: $run" }
    }

    return [PSCustomObject]@{ Ok = $true; Message = $Description; Detail = 'no-op check' }
}

function Write-WayforgeGateHuman {
    param($Report, [switch] $ToStdout)

    $header = "Wayforge gate [$($Report.Stage)]: " + $(if ($Report.Blocked) { 'BLOCKED' } else { 'passed' })
    $lines = @($header)
    foreach ($r in $Report.Results) {
        $mark = switch ($r.Status) {
            'pass' { '[+]' } 'warn' { '[!]' } 'skip' { '[ ]' } 'fail' { '[x]' } default { '[?]' }
        }
        $line = "  $mark $($r.Id) ($($r.Status))"
        if ($r.Detail) { $line += " - $($r.Detail)" }
        $lines += $line
    }
    $text = $lines -join "`n"
    if ($ToStdout) { [Console]::Out.WriteLine($text) } else { [Console]::Error.WriteLine($text) }
}

function Write-WayforgeGateDialect {
    <#
    .SYNOPSIS
        Emits the caller's dialect (stdout/stderr) and returns the exit code
        the calling shim should exit with.
    #>
    param($Report, [string] $AsHook)

    $blocked = $Report.Blocked
    $failed  = @($Report.Results | Where-Object Status -eq 'fail')
    $reason  = ($failed | ForEach-Object { "$($_.Id): $($_.Message)" }) -join '; '
    if (-not $reason) { $reason = 'Wayforge gate failed.' }

    switch ($AsHook) {
        { $_ -in 'claude', 'codex', 'kimi', 'grok', 'copilot' } {
            if ($blocked) {
                $evt = switch ($Report.Stage) { 'stop' { 'Stop' } default { 'PreToolUse' } }
                $json = @{ hookSpecificOutput = @{ hookEventName = $evt; permissionDecision = 'deny'; permissionDecisionReason = $reason } } |
                    ConvertTo-Json -Depth 5 -Compress
                [Console]::Out.WriteLine($json)
                return 2
            }
            return 0
        }
        'cursor' {
            if ($blocked) {
                [Console]::Out.WriteLine((@{ permission = 'deny'; user_message = $reason; agent_message = $reason } | ConvertTo-Json -Compress))
                return 2
            }
            return 0
        }
        { $_ -in 'opencode', 'pi' } {
            if ($blocked) {
                [Console]::Out.WriteLine((@{ decision = 'deny'; reason = $reason } | ConvertTo-Json -Compress))
                return 2
            }
            return 0
        }
        'ci' {
            # CI: human-readable report to stdout so it lands in the job log.
            Write-WayforgeGateHuman -Report $Report -ToStdout
            return [int][bool]$blocked
        }
        default {
            # git, none: human-readable to stderr; nonzero exit blocks.
            Write-WayforgeGateHuman -Report $Report
            return [int][bool]$blocked
        }
    }
}
