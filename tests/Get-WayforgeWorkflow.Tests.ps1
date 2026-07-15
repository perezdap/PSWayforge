BeforeAll {
    $script:ModuleRoot = Split-Path -Parent $PSScriptRoot
    $script:ManifestPath = Join-Path -Path $ModuleRoot -ChildPath 'PSWayforge.psd1'

    if (-not (Test-Path -Path $ManifestPath)) {
        throw "PSWayforge module manifest not found at '$ManifestPath'. Implement the foundation, utilities, and templates scopes before running these tests."
    }

    Import-Module -Name $ManifestPath -Force

    $script:ProjectPath = New-Item -ItemType Directory -Path (Join-Path -Path $TestDrive -ChildPath 'WorkflowProject')
    $script:DefinitionsDir = New-Item -ItemType Directory -Path (Join-Path -Path $ProjectPath -ChildPath '.workflow/definitions')
    $script:DefinitionPath = Join-Path -Path $DefinitionsDir -ChildPath 'default.yaml'

    @'
name: default
steps:
  - id: scout
    prompt: locate-context
  - id: plan
    prompt: generate-plan
'@ | Set-Content -Path $DefinitionPath
}

AfterAll {
    Remove-Module -Name PSWayforge -Force -ErrorAction SilentlyContinue
}

Describe 'Get-WayforgeWorkflow' {
    It 'returns a parsed workflow definition object' {
        $workflow = Get-WayforgeWorkflow -Name 'default' -ProjectPath $ProjectPath

        $workflow | Should -Not -BeNullOrEmpty
        $workflow.name | Should -Be 'default'
        $workflow.steps | Should -HaveCount 2
        $workflow.steps[0].id | Should -Be 'scout'
        $workflow.steps[1].prompt | Should -Be 'generate-plan'
    }

    It 'throws when the workflow definition does not exist' {
        { Get-WayforgeWorkflow -Name 'missing' -ProjectPath $ProjectPath } | Should -Throw
    }
}
