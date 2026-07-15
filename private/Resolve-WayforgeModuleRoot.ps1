function Resolve-WayforgeModuleRoot {
    <#
    .SYNOPSIS
        Returns the root directory of the PSWayforge module.
    #>
    [CmdletBinding()]
    param()

    $callerRoot = $PSScriptRoot
    if (-not $callerRoot) {
        throw 'Unable to resolve module root: $PSScriptRoot is not available.'
    }

    return Split-Path -Parent $callerRoot
}
