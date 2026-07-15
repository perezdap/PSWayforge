function Install-WayforgeFile {
    <#
    .SYNOPSIS
        Writes a scaffold file from a template, skipping existing files.

    .DESCRIPTION
        Copies a template file into the project after replacing simple token
        placeholders. If the target file already exists, a warning is emitted
        and the file is left untouched. This supports the additive-only
        InitializeExisting behavior.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectRoot,

        [Parameter(Mandatory)]
        [string]$RelativePath,

        [Parameter(Mandatory)]
        [string]$TemplatePath,

        [hashtable]$Tokens = @{}
    )

    $target = Join-Path $ProjectRoot $RelativePath

    if (Test-Path $target) {
        Write-Warning "Skipping existing file: $target"
        return
    }

    if (-not (Test-Path $TemplatePath)) {
        Write-Warning "Template not found: $TemplatePath"
        return
    }

    $content = Get-Content -Raw -Path $TemplatePath
    foreach ($token in $Tokens.GetEnumerator()) {
        $content = $content -replace [regex]::Escape($token.Key), $token.Value
    }

    $parent = Split-Path -Parent $target
    if (-not (Test-Path $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    if ($PSCmdlet.ShouldProcess($target, 'Write file from template')) {
        Set-Content -Path $target -Value $content -Encoding utf8NoBOM
    }
}
