function Install-WayforgeGateShim {
    <#
    .SYNOPSIS
        Writes the shared gate shim (.workflow/hooks/gate.ps1) that every
        enforcement point invokes. Harness-agnostic; the caller passes -Stage
        and -AsHook. Overwrites to keep it in sync with the module.
    #>
    param([string] $ProjectRoot)

    $hooksDir = Join-Path $ProjectRoot '.workflow/hooks'
    if (-not (Test-Path $hooksDir)) { New-Item -ItemType Directory -Path $hooksDir -Force | Out-Null }

    $shimPath = Join-Path $hooksDir 'gate.ps1'
    $content = @'
#requires -Version 7.3
# Shared Wayforge gate shim. Invoked by harness hooks and git hooks.
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('pre-tool', 'stop', 'pre-commit', 'pre-push', 'ci')]
    [string] $Stage,
    [string] $AsHook = 'git'
)

$ErrorActionPreference = 'Stop'
$eventJson = if ([Console]::In.Peek() -ge 0) { [Console]::In.ReadToEnd() } else { $null }

Import-Module PSWayforge -ErrorAction Stop

$report = Invoke-WayforgeGate -Stage $Stage -AsHook $AsHook -EventJson $eventJson -ProjectPath (Get-Location).Path
exit $report.ExitCode
'@

    Set-Content -Path $shimPath -Value $content -Encoding utf8NoBOM
    return $shimPath
}
