function Invoke-WayforgeHook {
    <#
    .SYNOPSIS
        Invokes a PSWayforge lifecycle hook.

    .DESCRIPTION
        Resolves .workflow/hooks/<HookName>.ps1 inside the current or specified
        project and invokes it safely. Parameters supplied by the caller are
        passed to the hook script via its `-WayforgeParameters` parameter. Hook
        scripts should declare `param([hashtable]$WayforgeParameters)` to
        receive them.

    .PARAMETER HookName
        The name of the hook to invoke (without .ps1 extension).

    .PARAMETER ProjectPath
        The project root. Defaults to the current working directory.

    .PARAMETER Parameters
        Optional hashtable of parameters to pass into the hook script.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $HookName,

        [Parameter()]
        [string] $ProjectPath = (Get-Location).Path,

        [Parameter()]
        [hashtable] $Parameters = @{}
    )

    $projectRoot = Resolve-WayforgeProjectPath -ProjectPath $ProjectPath
    $hookPath = Join-Path -Path $projectRoot -ChildPath ".workflow/hooks/${HookName}.ps1"

    if (-not (Test-Path -Path $hookPath -PathType Leaf)) {
        throw "Hook '$HookName' not found at '$hookPath'."
    }

    $resolvedHook = (Resolve-Path -Path $hookPath).Path
    $command = Get-Command -Name $resolvedHook -CommandType ExternalScript

    try {
        if ($command.Parameters.ContainsKey('WayforgeParameters')) {
            & $resolvedHook -WayforgeParameters $Parameters
        }
        else {
            & $resolvedHook
        }
    }
    catch {
        throw "Hook '$HookName' failed: $_"
    }
}
