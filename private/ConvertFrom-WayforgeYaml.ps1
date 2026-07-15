. (Join-Path -Path $PSScriptRoot -ChildPath 'ConvertFrom-WayforgeYamlMinimal.ps1')

function ConvertFrom-WayforgeYaml {
    <#
    .SYNOPSIS
        Parses a YAML string into a PowerShell object.

    .DESCRIPTION
        Uses the powershell-yaml module when available. If the module is not
        installed, falls back to a minimal internal parser that supports the
        simple workflow definitions used by PSWayforge.

        This avoids declaring a hard module dependency while still handling
        common scaffold YAML. For complex workflow files, install
        powershell-yaml.

    .PARAMETER Yaml
        The YAML string to parse.
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)]
        [string] $Yaml
    )

    $module = Get-Module -ListAvailable -Name powershell-yaml -ErrorAction SilentlyContinue |
        Sort-Object -Property Version -Descending |
        Select-Object -First 1

    if ($module) {
        Import-Module -Name powershell-yaml -RequiredVersion $module.Version -Force
        return ConvertFrom-Yaml -Yaml $Yaml
    }

    return ConvertFrom-WayforgeYamlMinimal -Yaml $Yaml
}
