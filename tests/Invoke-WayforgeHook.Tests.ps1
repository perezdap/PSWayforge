BeforeAll {
    $script:ModuleRoot = Split-Path -Parent $PSScriptRoot
    $script:ManifestPath = Join-Path -Path $ModuleRoot -ChildPath 'PSWayforge.psd1'

    if (-not (Test-Path -Path $ManifestPath)) {
        throw "PSWayforge module manifest not found at '$ManifestPath'. Implement the foundation and utilities scopes before running these tests."
    }

    Import-Module -Name $ManifestPath -Force

    $script:ProjectPath = New-Item -ItemType Directory -Path (Join-Path -Path $TestDrive -ChildPath 'HookProject')
    $script:HooksDir = New-Item -ItemType Directory -Path (Join-Path -Path $ProjectPath -ChildPath '.workflow/hooks')
    $script:TestHook = Join-Path -Path $HooksDir -ChildPath 'test-hook.ps1'
    $script:BadHook = Join-Path -Path $HooksDir -ChildPath 'bad-hook.ps1'

    @'
param([hashtable]$WayforgeParameters)
"Hello $($WayforgeParameters.Name)"
'@ | Set-Content -Path $TestHook

    'throw "hook failed"' | Set-Content -Path $BadHook
}

AfterAll {
    Remove-Module -Name PSWayforge -Force -ErrorAction SilentlyContinue
}

Describe 'Invoke-WayforgeHook' {
    It 'invokes a hook script in .workflow/hooks and returns its output' {
        $result = Invoke-WayforgeHook -HookName 'test-hook' -ProjectPath $ProjectPath -Parameters @{ Name = 'World' }
        $result | Should -Be 'Hello World'
    }

    It 'throws when the requested hook does not exist' {
        { Invoke-WayforgeHook -HookName 'missing-hook' -ProjectPath $ProjectPath } | Should -Throw
    }

    It 'surfaces hook script errors as terminating errors' {
        { Invoke-WayforgeHook -HookName 'bad-hook' -ProjectPath $ProjectPath } | Should -Throw '*hook failed*'
    }
}
