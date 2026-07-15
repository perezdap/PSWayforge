function Resolve-WayforgeProjectPath {
    <#
    .SYNOPSIS
        Resolves and validates a PSWayforge project path.

    .DESCRIPTION
        Converts a relative or absolute project path into a fully-qualified
        directory path. Throws if the directory does not exist.

    .PARAMETER ProjectPath
        The project directory. Defaults to the current working directory.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter()]
        [string] $ProjectPath = (Get-Location).Path
    )

    $resolved = (Resolve-Path -Path $ProjectPath -ErrorAction SilentlyContinue).Path
    if (-not $resolved -or -not (Test-Path -Path $resolved -PathType Container)) {
        throw "Project path '$ProjectPath' does not exist or is not a directory."
    }

    return $resolved
}
