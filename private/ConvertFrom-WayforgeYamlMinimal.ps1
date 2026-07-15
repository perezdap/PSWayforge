function ConvertFrom-WayforgeYamlMinimal {
    <#
    .SYNOPSIS
        Minimal internal YAML parser for simple PSWayforge workflow files.

    .DESCRIPTION
        Parses a constrained subset of YAML (mappings, sequences, scalars, and
        comments) without external dependencies. Supports the structure produced
        by templates/workflow.default.yaml. For complex YAML, install
        powershell-yaml.

    .PARAMETER Yaml
        The YAML string to parse.
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)]
        [string] $Yaml
    )

    $script:lines = $Yaml -split "`r?`n" | ForEach-Object {
        $line = $_ -replace '\s*#.*$', ''
        if ($line -match '^\s*$') { return $null }

        $indent = ($line -replace '^(\s*).*', '$1').Length
        $content = $line.TrimStart()
        [PSCustomObject]@{ Indent = $indent; Content = $content }
    } | Where-Object { $_ -ne $null }

    $script:index = 0

    function ConvertFrom-WayforgeYamlScalar {
        param([string] $Value)

        $trimmed = $Value.Trim()
        if ($trimmed -eq '') { return '' }
        if ($trimmed -match '^(true|yes)$') { return $true }
        if ($trimmed -match '^(false|no)$') { return $false }
        if ($trimmed -match '^-?\d+$') { return [int]::Parse($trimmed) }
        if ($trimmed -match '^-?\d+\.\d+$') { return [double]::Parse($trimmed) }

        if (($trimmed.StartsWith('"') -and $trimmed.EndsWith('"')) -or
            ($trimmed.StartsWith("'") -and $trimmed.EndsWith("'"))) {
            return $trimmed.Substring(1, $trimmed.Length - 2)
        }

        return $trimmed
    }

    function Read-MappingKey {
        param([int] $baseIndent)

        $line = $script:lines[$script:index]
        if ($line.Indent -ne $baseIndent -or $line.Content -notmatch '^([^:]+):\s*(.*)$') {
            throw "Expected mapping key at indentation $baseIndent, got: $($line.Content)"
        }

        $key = $matches[1]
        $value = $matches[2]
        $script:index++

        if ($value -ne '') {
            return $key, (ConvertFrom-WayforgeYamlScalar -Value $value)
        }

        if ($script:index -lt $script:lines.Count -and
            $script:lines[$script:index].Indent -gt $baseIndent) {
            return $key, (Read-Block -baseIndent $baseIndent)
        }

        return $key, $null
    }

    function Read-Block($baseIndent) {
        if ($script:index -ge $script:lines.Count) { return $null }
        if ($script:lines[$script:index].Indent -le $baseIndent) { return $null }

        $blockIndent = $script:lines[$script:index].Indent
        $mapping = [ordered]@{}
        $sequence = [System.Collections.Generic.List[object]]::new()
        $isSequence = $false

        while ($script:index -lt $script:lines.Count) {
            $line = $script:lines[$script:index]

            if ($line.Indent -lt $blockIndent) { break }
            if ($line.Indent -gt $blockIndent) {
                throw "Unexpected indentation at line '$($line.Content)'."
            }

            if ($line.Content -match '^-\s+(.*)$') {
                $isSequence = $true
                $rest = $matches[1]
                $itemBaseIndent = $line.Indent + 2
                $script:index++

                if ($rest -match '^([^:]+):\s*(.*)$') {
                    $key = $matches[1]
                    $value = $matches[2]
                    $item = [ordered]@{ $key = if ($value -ne '') { ConvertFrom-WayforgeYamlScalar -Value $value } else { $null } }

                    if ($value -eq '' -and
                        $script:index -lt $script:lines.Count -and
                        $script:lines[$script:index].Indent -gt $itemBaseIndent) {
                        $item[$key] = Read-Block -baseIndent $itemBaseIndent
                    }
                    elseif ($value -ne '') {
                        while ($script:index -lt $script:lines.Count -and
                               $script:lines[$script:index].Indent -eq $itemBaseIndent) {
                            $k, $v = Read-MappingKey -baseIndent $itemBaseIndent
                            $item[$k] = $v
                        }
                    }

                    $sequence.Add($item)
                }
                else {
                    $scalar = ConvertFrom-WayforgeYamlScalar -Value $rest
                    $sequence.Add($scalar)
                }
            }
            elseif ($line.Content -match '^([^:]+):\s*(.*)$') {
                if ($isSequence) {
                    throw "Mixed mapping and sequence at indentation $blockIndent."
                }

                $key, $value = Read-MappingKey -baseIndent $blockIndent
                $mapping[$key] = $value
            }
            else {
                throw "Unrecognized YAML line: $($line.Content)"
            }
        }

        if ($isSequence) {
            return ,$sequence.ToArray()
        }

        return $mapping
    }

    $result = Read-Block -baseIndent -1
    return $result
}
