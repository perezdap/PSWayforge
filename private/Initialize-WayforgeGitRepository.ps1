function Initialize-WayforgeGitRepository {
    <#
    .SYNOPSIS
        Runs git init in the project directory if git is available.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectRoot
    )

    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Write-Warning 'git was not found on PATH; skipping git init.'
        return
    }

    $gitDir = Join-Path $ProjectRoot '.git'
    if (Test-Path $gitDir) {
        Write-Verbose 'Git repository already initialized.'
        return
    }

    Push-Location $ProjectRoot
    try {
        if ($PSCmdlet.ShouldProcess($ProjectRoot, 'git init')) {
            & git init 2>&1 | Out-Null
            if ($LASTEXITCODE -ne 0) {
                Write-Warning "git init completed with exit code $LASTEXITCODE."
            }
        }
    }
    finally {
        Pop-Location
    }
}
