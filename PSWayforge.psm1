$publicPath  = Join-Path $PSScriptRoot 'public'
$privatePath = Join-Path $PSScriptRoot 'private'

Get-ChildItem -Path $privatePath -Filter '*.ps1' -ErrorAction SilentlyContinue |
    ForEach-Object { . $_.FullName }

$publicFunctions = Get-ChildItem -Path $publicPath -Filter '*.ps1' -ErrorAction SilentlyContinue |
    ForEach-Object {
        . $_.FullName
        $_.BaseName
    }

Export-ModuleMember -Function $publicFunctions
