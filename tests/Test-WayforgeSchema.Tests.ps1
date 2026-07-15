BeforeAll {
    $script:ModuleRoot = Split-Path -Parent $PSScriptRoot
    $script:ManifestPath = Join-Path -Path $ModuleRoot -ChildPath 'PSWayforge.psd1'

    if (-not (Test-Path -Path $ManifestPath)) {
        throw "PSWayforge module manifest not found at '$ManifestPath'. Implement the foundation, utilities, and templates scopes before running these tests."
    }

    Import-Module -Name $ManifestPath -Force

    $script:ProjectPath = New-Item -ItemType Directory -Path (Join-Path -Path $TestDrive -ChildPath 'SchemaProject')
    $script:SchemasDir = New-Item -ItemType Directory -Path (Join-Path -Path $ProjectPath -ChildPath '.workflow/schemas')
    $script:SchemaPath = Join-Path -Path $SchemasDir -ChildPath 'plan.json'

    @'
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "object",
  "required": ["name"],
  "properties": {
    "name": { "type": "string" }
  }
}
'@ | Set-Content -Path $SchemaPath
}

AfterAll {
    Remove-Module -Name PSWayforge -Force -ErrorAction SilentlyContinue
}

Describe 'Test-WayforgeSchema' {
    It 'returns true for a valid JSON string artifact' {
        Test-WayforgeSchema -Artifact '{"name":"scout"}' -SchemaName 'plan' -ProjectPath $ProjectPath | Should -Be $true
    }

    It 'returns false for an invalid JSON string artifact' {
        Test-WayforgeSchema -Artifact '{"name":123}' -SchemaName 'plan' -ProjectPath $ProjectPath | Should -Be $false
    }

    It 'accepts a Hashtable artifact' {
        Test-WayforgeSchema -Artifact @{ name = 'plan' } -SchemaName 'plan' -ProjectPath $ProjectPath | Should -Be $true
    }

    It 'throws when the named schema file does not exist' {
        { Test-WayforgeSchema -Artifact '{}' -SchemaName 'missing' -ProjectPath $ProjectPath } | Should -Throw
    }

    It 'validates using Test-Json' {
        InModuleScope -ModuleName PSWayforge -Parameters @{ ProjectPath = $ProjectPath } {
            Mock Test-Json { return $true }
            Test-WayforgeSchema -Artifact '{}' -SchemaName 'plan' -ProjectPath $ProjectPath | Should -Be $true
            Should -Invoke Test-Json -Exactly 1
        }
    }
}
