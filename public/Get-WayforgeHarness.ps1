function Get-WayforgeHarness {
    <#
    .SYNOPSIS
        Reports each known harness as Installed (a home-directory marker exists)
        and/or Configured (Wayforge config exists in the project).

    .DESCRIPTION
        Detection powers smart defaults for Sync-WayforgeHarness -Detect and
        New-WayforgeProject -DetectHarness: Installed marks harnesses the user has
        on this machine; Configured marks harnesses already wired in the project
        (so re-syncing updates rather than surprises).

    .PARAMETER ProjectPath
        The project to inspect for existing config. Defaults to the current directory.

    .PARAMETER HomePath
        The home directory to inspect for installed harnesses. Defaults to the
        user profile.

    .EXAMPLE
        Get-WayforgeHarness | Where-Object Installed

        Lists the harnesses installed on this machine.
    #>
    [CmdletBinding()]
    [OutputType('PSWayforge.HarnessInfo')]
    param(
        [string] $ProjectPath = (Get-Location).Path,
        [string] $HomePath = $(if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME })
    )

    $root = (Resolve-Path -Path $ProjectPath -ErrorAction SilentlyContinue).Path
    if (-not $root) { $root = $ProjectPath }

    $markers = @(
        [ordered]@{ Name = 'claude';   Home = '.claude';          Repo = '.claude' }
        [ordered]@{ Name = 'codex';    Home = '.codex';           Repo = '.codex' }
        [ordered]@{ Name = 'grok';     Home = '.grok';            Repo = '.grok' }
        [ordered]@{ Name = 'copilot';  Home = '.copilot';         Repo = '.github/hooks/wayforge.json' }
        [ordered]@{ Name = 'cursor';   Home = '.cursor';          Repo = '.cursor' }
        [ordered]@{ Name = 'opencode'; Home = '.config/opencode'; Repo = '.opencode' }
        [ordered]@{ Name = 'pi';       Home = '.pi';              Repo = '.pi' }
        [ordered]@{ Name = 'kimi';     Home = '.kimi-code';       Repo = '.workflow/harness/kimi.config.toml' }
    )

    foreach ($marker in $markers) {
        [PSCustomObject]@{
            PSTypeName = 'PSWayforge.HarnessInfo'
            Name       = $marker.Name
            Installed  = [bool](Test-Path -Path (Join-Path $HomePath $marker.Home))
            Configured = [bool](Test-Path -Path (Join-Path $root $marker.Repo))
        }
    }
}
