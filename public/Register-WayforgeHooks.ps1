function Register-WayforgeHooks {
    <#
    .SYNOPSIS
        Installs the fail-closed git floor: the shared gate shim, the
        pre-commit/pre-push hook shims, and core.hooksPath.

    .DESCRIPTION
        Writes .workflow/hooks/gate.ps1 and .workflow/githooks/{pre-commit,
        pre-push} (POSIX sh, LF line endings), then points git at the tracked
        hooks directory via `core.hooksPath`. Because git config is per-clone,
        this must be run once in every clone (New-WayforgeProject calls it
        automatically after git init).

    .PARAMETER ProjectPath
        A path inside the target repository. Defaults to the current directory.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([string] $ProjectPath = (Get-Location).Path)

    $root = Resolve-WayforgeGitRoot -Path $ProjectPath

    $inside = & git -C $root rev-parse --is-inside-work-tree 2>$null
    if ($LASTEXITCODE -ne 0 -or $inside -ne 'true') {
        throw "Register-WayforgeHooks requires a git repository. '$root' is not one."
    }

    Install-WayforgeGateShim -ProjectRoot $root | Out-Null

    $ghDir = Join-Path $root '.workflow/githooks'
    if (-not (Test-Path $ghDir)) { New-Item -ItemType Directory -Path $ghDir -Force | Out-Null }

    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    foreach ($stage in 'pre-commit', 'pre-push') {
        $shim = @"
#!/bin/sh
root=`$(git rev-parse --show-toplevel)
exec pwsh -NoProfile -File "`$root/.workflow/hooks/gate.ps1" -Stage $stage -AsHook git
"@
        $shim = ($shim -replace "`r`n", "`n")               # sh requires LF, never CRLF
        $path = Join-Path $ghDir $stage
        if ($PSCmdlet.ShouldProcess($path, 'Write git hook shim')) {
            [System.IO.File]::WriteAllText($path, $shim, $utf8NoBom)
            if (-not $IsWindows) { & chmod +x $path }
        }
    }

    if ($PSCmdlet.ShouldProcess($root, 'Set core.hooksPath = .workflow/githooks')) {
        & git -C $root config core.hooksPath .workflow/githooks
    }

    [PSCustomObject]@{
        PSTypeName  = 'PSWayforge.HookRegistration'
        ProjectRoot = $root
        HooksPath   = '.workflow/githooks'
        Shim        = '.workflow/hooks/gate.ps1'
        Stages      = @('pre-commit', 'pre-push')
    }
}
