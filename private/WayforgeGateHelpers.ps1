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

function Test-WayforgeChangeCondition {
    <#
    .SYNOPSIS
        Evaluates a gate `when` predicate against a changeset.
    .DESCRIPTION
        Supports: always, changes_touch(<scope>), changes_only(<scope>).
        Unknown predicates are treated as applicable (fail-safe for block gates).
    #>
    param([string] $Condition, [string[]] $ChangeSet, $Scopes)

    if ([string]::IsNullOrWhiteSpace($Condition) -or $Condition -eq 'always') {
        return $true
    }

    if ($Condition -match '^\s*changes_touch\(\s*(\w+)\s*\)\s*$') {
        $globs = @(if ($Scopes -is [System.Collections.IDictionary] -and $Scopes.Contains($matches[1])) { $Scopes[$matches[1]] })
        foreach ($f in $ChangeSet) {
            foreach ($glob in $globs) {
                if (Test-WayforgeGlobMatch -Path $f -Glob $glob) { return $true }
            }
        }
        return $false
    }

    if ($Condition -match '^\s*changes_only\(\s*(\w+)\s*\)\s*$') {
        if (-not $ChangeSet -or @($ChangeSet).Count -eq 0) { return $false }
        $globs = @(if ($Scopes -is [System.Collections.IDictionary] -and $Scopes.Contains($matches[1])) { $Scopes[$matches[1]] })
        foreach ($f in $ChangeSet) {
            $matched = $false
            foreach ($glob in $globs) {
                if (Test-WayforgeGlobMatch -Path $f -Glob $glob) { $matched = $true; break }
            }
            if (-not $matched) { return $false }
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
            $stdin = if ($EventJson) { $EventJson } else { '' }
            foreach ($line in ($stdin -split "`r?`n")) {
                $parts = $line -split '\s+'
                if ($parts.Count -ge 4) {
                    $localSha = $parts[1]; $remoteSha = $parts[3]
                    $range = if ($remoteSha -match '^0+$') { $localSha } else { "$remoteSha..$localSha" }
                    $out = & git -C $Root diff --name-only $range 2>$null
                    $out | Where-Object { $_ } | ForEach-Object { $files.Add($_) }
                }
            }
            return @($files | Select-Object -Unique)
        }
        'ci' {
            $base = if ($env:WAYFORGE_BASE_REF) { $env:WAYFORGE_BASE_REF } else { 'origin/main' }
            $out = & git -C $Root diff --name-only "$base...HEAD" 2>$null
            return @($out | Where-Object { $_ })
        }
        default {
            # pre-tool / stop: derive from the harness event payload.
            if ($EventJson) {
                try {
                    $ev = $EventJson | ConvertFrom-Json
                    $fp = $ev.tool_input.file_path
                    if ($fp) {
                        $rel = $fp -replace '\\', '/'
                        $rootNorm = ($Root -replace '\\', '/').TrimEnd('/') + '/'
                        if ($rel.StartsWith($rootNorm, [StringComparison]::OrdinalIgnoreCase)) {
                            $rel = $rel.Substring($rootNorm.Length)
                        }
                        return , $rel
                    }
                } catch { }
            }
            return @()
        }
    }
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
            'native' { Invoke-Expression $Command 2>&1 | Out-Null; return $LASTEXITCODE }
            default  { & pwsh -NoProfile -Command $Command 2>&1 | Out-Null; return $LASTEXITCODE }
        }
    }
    catch { return 1 }
    finally { Pop-Location }
}

function Invoke-WayforgeCheck {
    <#
    .SYNOPSIS
        Evaluates one gate `check` (requires_artifact | run) and returns
        an object with Ok/Message/Detail.
    #>
    param($Check, [string] $Root, [string] $Description)

    if ($null -eq $Check) {
        return [PSCustomObject]@{ Ok = $true; Message = $Description; Detail = 'no check' }
    }

    $artifact = Get-WayforgeField $Check 'requires_artifact'
    $run      = Get-WayforgeField $Check 'run'

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
    param($Report)

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
    [Console]::Error.WriteLine(($lines -join "`n"))
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
        default {
            # git, ci, none: human-readable to stderr; nonzero exit blocks.
            Write-WayforgeGateHuman -Report $Report
            return [int][bool]$blocked
        }
    }
}
