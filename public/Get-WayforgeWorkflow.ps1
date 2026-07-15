function Get-WayforgeWorkflow {
    <#
    .SYNOPSIS
        Loads a workflow definition as a PowerShell object.

    .DESCRIPTION
        Resolves .workflow/definitions/<Name>.yaml inside the current or
        specified project, parses the YAML, and returns the resulting object.

    .PARAMETER Name
        The name of the workflow definition (without .yaml extension).

    .PARAMETER ProjectPath
        The project root. Defaults to the current working directory.
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Name,

        [Parameter()]
        [string] $ProjectPath = (Get-Location).Path
    )

    $projectRoot = Resolve-WayforgeProjectPath -ProjectPath $ProjectPath
    $definitionPath = Join-Path -Path $projectRoot -ChildPath ".workflow/definitions/${Name}.yaml"

    if (-not (Test-Path -Path $definitionPath -PathType Leaf)) {
        throw "Workflow definition '$Name' not found at '$definitionPath'."
    }

    $resolvedDefinition = (Resolve-Path -Path $definitionPath).Path
    $yaml = Get-Content -Path $resolvedDefinition -Raw

    try {
        return ConvertFrom-WayforgeYaml -Yaml $yaml
    }
    catch {
        throw "Failed to parse workflow '$Name': $_"
    }
}
