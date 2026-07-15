function Test-WayforgeSchema {
    <#
    .SYNOPSIS
        Validates an artifact against a JSON Schema.

    .DESCRIPTION
        Locates .workflow/schemas/<SchemaName>.json inside the current or
        specified project and validates the supplied artifact with Test-Json.

    .PARAMETER Artifact
        The artifact to validate. Accepts a JSON string, a path to a JSON file,
        or any object that can be serialized to JSON.

    .PARAMETER SchemaName
        The name of the schema file (without .json extension).

    .PARAMETER ProjectPath
        The project root. Defaults to the current working directory.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [object] $Artifact,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $SchemaName,

        [Parameter()]
        [string] $ProjectPath = (Get-Location).Path
    )

    process {
        $projectRoot = Resolve-WayforgeProjectPath -ProjectPath $ProjectPath
        $schemaPath = Join-Path -Path $projectRoot -ChildPath ".workflow/schemas/${SchemaName}.json"

        if (-not (Test-Path -Path $schemaPath -PathType Leaf)) {
            throw "Schema '$SchemaName' not found at '$schemaPath'."
        }

        $resolvedSchema = (Resolve-Path -Path $schemaPath).Path

        $json = switch ($Artifact) {
            { $_ -is [string] } {
                # Treat as a file path if it points to an existing JSON file;
                # otherwise treat the string itself as JSON.
                if (Test-Path -Path $_ -PathType Leaf) {
                    Get-Content -Path $_ -Raw
                }
                else {
                    $_
                }
            }
            default {
                $Artifact | ConvertTo-Json -Depth 10 -Compress:$false
            }
        }

        # Test-Json writes a non-terminating error when validation fails while
        # still returning $false. SilentlyContinue keeps the output clean and
        # preserves the boolean return value.
        return Test-Json -Json $json -SchemaFile $resolvedSchema -ErrorAction SilentlyContinue
    }
}
