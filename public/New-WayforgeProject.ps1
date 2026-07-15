function New-WayforgeProject {
    <#
    .SYNOPSIS
        Scaffolds a new Wayforge workspace.

    .DESCRIPTION
        Creates a project directory and populates it with the standard Wayforge
        workspace structure: AGENTS.md, .agents/skills/, .workflow/definitions/,
        .workflow/hooks/, .workflow/schemas/, and a .gitignore. If the target
        directory already exists, use -InitializeExisting to add missing files
        and directories only; existing files are never overwritten.

    .PARAMETER Name
        The name of the project. This becomes the directory name and is used in
        generated artifacts such as AGENTS.md.

    .PARAMETER Path
        The parent path where the project directory will be created. Relative
        paths are resolved from the current location.

    .PARAMETER InitializeExisting
        When set, scaffolding is applied to an existing directory. Any file that
        already exists is skipped with a warning instead of being overwritten.

    .EXAMPLE
        New-WayforgeProject -Name MyProject -Path C:\Projects

        Creates C:\Projects\MyProject and scaffolds a fresh workspace.

    .EXAMPLE
        New-WayforgeProject -Name MyProject -Path . -InitializeExisting

        Scaffolds a workspace into the existing ./MyProject directory without
        overwriting any files.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Name,

        [Parameter(Mandatory, Position = 1)]
        [string]$Path,

        [switch]$InitializeExisting
    )

    begin {
        $ErrorActionPreference = 'Stop'
    }

    process {
        $resolvedParent = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
        $projectRoot    = Join-Path $resolvedParent $Name

        if (Test-Path $projectRoot) {
            if (-not $InitializeExisting) {
                throw "Project directory already exists: $projectRoot. Use -InitializeExisting to scaffold additively."
            }
            if (-not (Test-Path $projectRoot -PathType Container)) {
                throw "A non-directory file exists at the project path: $projectRoot"
            }
            Write-Verbose "Scaffolding into existing directory: $projectRoot"
        }
        else {
            if ($PSCmdlet.ShouldProcess($projectRoot, 'Create project directory')) {
                New-Item -ItemType Directory -Path $projectRoot | Out-Null
            }
        }

        $directories = @(
            (Join-Path $projectRoot '.agents' 'skills')
            (Join-Path $projectRoot '.workflow' 'definitions')
            (Join-Path $projectRoot '.workflow' 'hooks')
            (Join-Path $projectRoot '.workflow' 'schemas')
        )

        foreach ($dir in $directories) {
            if (-not (Test-Path $dir)) {
                if ($PSCmdlet.ShouldProcess($dir, 'Create directory')) {
                    New-Item -ItemType Directory -Path $dir -Force | Out-Null
                }
            }
        }

        $moduleRoot = Resolve-WayforgeModuleRoot

        Install-WayforgeFile `
            -ProjectRoot $projectRoot `
            -RelativePath 'AGENTS.md' `
            -TemplatePath (Join-Path $moduleRoot 'templates' 'AGENTS.md.template') `
            -Tokens @{ '{{PROJECT_NAME}}' = $Name }

        Install-WayforgeFile `
            -ProjectRoot $projectRoot `
            -RelativePath '.gitignore' `
            -TemplatePath (Join-Path $moduleRoot 'templates' 'gitignore.template')

        Install-WayforgeFile `
            -ProjectRoot $projectRoot `
            -RelativePath (Join-Path '.agents' 'skills' 'example' 'SKILL.md') `
            -TemplatePath (Join-Path $moduleRoot 'templates' 'skill.example' 'SKILL.md')

        Install-WayforgeFile `
            -ProjectRoot $projectRoot `
            -RelativePath (Join-Path '.workflow' 'definitions' 'default.yaml') `
            -TemplatePath (Join-Path $moduleRoot 'templates' 'workflow.default.yaml')

        Install-WayforgeFile `
            -ProjectRoot $projectRoot `
            -RelativePath (Join-Path '.workflow' 'schemas' 'example.json') `
            -TemplatePath (Join-Path $moduleRoot 'templates' 'schema.example.json')

        Initialize-WayforgeGitRepository -ProjectRoot $projectRoot

        [PSCustomObject]@{
            PSTypeName          = 'PSWayforge.Project'
            Name                = $Name
            Path                = $projectRoot
            InitializedExisting = $InitializeExisting.IsPresent
        }
    }
}
