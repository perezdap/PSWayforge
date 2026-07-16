function Initialize-WayforgeProject {
    <#
    .SYNOPSIS
        Applies the Wayforge workspace and enforcement to an existing project, in place.

    .DESCRIPTION
        The in-place counterpart to New-WayforgeProject: it targets an existing
        directory directly (no -Name/-Path split) and scaffolds additively —
        existing files are preserved and harness config is merged, never
        clobbered. Enforcement (git hooks + harness config) is wired unless
        -SkipEnforcement is set.

    .PARAMETER Path
        The existing project directory to initialize. Defaults to the current directory.

    .PARAMETER Harness
        Which harnesses to wire. Defaults to 'claude'. Ignored with -DetectHarness.

    .PARAMETER SkipEnforcement
        Scaffold the workspace but skip wiring git hooks and harness config.

    .PARAMETER WithCI
        Also generate the CI gate workflow.

    .PARAMETER DetectHarness
        Wire every harness detected as installed on this machine (claude fallback).

    .EXAMPLE
        Initialize-WayforgeProject -DetectHarness

        Adds Wayforge enforcement to the current repository, wiring every agent
        you have installed, without overwriting anything you already have.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType('PSWayforge.Project')]
    param(
        [Parameter(Position = 0)]
        [string] $Path = (Get-Location).Path,

        [ValidateSet('claude', 'codex', 'grok', 'copilot', 'cursor', 'opencode', 'pi', 'kimi')]
        [string[]] $Harness = @('claude'),

        [switch] $SkipEnforcement,

        [switch] $WithCI,

        [switch] $DetectHarness
    )

    $target = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
    if (-not (Test-Path -Path $target -PathType Container)) {
        throw "Initialize-WayforgeProject requires an existing directory. '$target' does not exist."
    }

    $name   = Split-Path -Path $target -Leaf
    $parent = Split-Path -Path $target -Parent
    if (-not $parent) {
        throw "Cannot initialize at a filesystem root: '$target'."
    }

    $params = @{
        Name               = $name
        Path               = $parent
        InitializeExisting = $true
    }
    if ($PSBoundParameters.ContainsKey('Harness')) { $params.Harness = $Harness }
    if ($SkipEnforcement) { $params.SkipEnforcement = $true }
    if ($WithCI)          { $params.WithCI = $true }
    if ($DetectHarness)   { $params.DetectHarness = $true }

    New-WayforgeProject @params
}
