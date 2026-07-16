function Select-WayforgeHarness {
    <#
    .SYNOPSIS
        Interactive multiselect of harnesses, pre-checked from detection.

    .DESCRIPTION
        Shows the known harnesses with installed/configured tags, pre-selecting
        those that are installed or already configured. The user toggles entries
        by number and confirms; the chosen harness names are returned (suitable
        for Sync-WayforgeHarness -Harness or New-WayforgeProject -Harness).

    .PARAMETER ProjectPath
        The project to inspect. Defaults to the current directory.

    .PARAMETER HomePath
        The home directory to inspect. Defaults to the user profile.

    .EXAMPLE
        Sync-WayforgeHarness -Harness (Select-WayforgeHarness)

        Prompts for harnesses (pre-checked from what's installed) and syncs them.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [string] $ProjectPath = (Get-Location).Path,
        [string] $HomePath = $(if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME })
    )

    $info = @(Get-WayforgeHarness -ProjectPath $ProjectPath -HomePath $HomePath)
    $selected = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($h in $info) { if ($h.Installed -or $h.Configured) { [void]$selected.Add($h.Name) } }

    while ($true) {
        Write-Host 'Select harnesses to enforce (pre-checked = installed or configured):'
        for ($i = 0; $i -lt $info.Count; $i++) {
            $h = $info[$i]
            $mark = if ($selected.Contains($h.Name)) { '[x]' } else { '[ ]' }
            $tags = @()
            if ($h.Installed) { $tags += 'installed' }
            if ($h.Configured) { $tags += 'configured' }
            $suffix = if ($tags) { " ($($tags -join ', '))" } else { '' }
            Write-Host ('  {0,2}. {1} {2}{3}' -f ($i + 1), $mark, $h.Name, $suffix)
        }

        $answer = Read-Host "Toggle numbers (comma-separated), 'a' for all, 'n' for none, or Enter to confirm"
        if ([string]::IsNullOrWhiteSpace($answer)) { break }

        switch -Regex ($answer.Trim()) {
            '^a$' { foreach ($h in $info) { [void]$selected.Add($h.Name) }; continue }
            '^n$' { $selected.Clear(); continue }
            default {
                foreach ($token in ($answer -split '[,\s]+' | Where-Object { $_ })) {
                    $index = 0
                    if ([int]::TryParse($token, [ref]$index) -and $index -ge 1 -and $index -le $info.Count) {
                        $name = $info[$index - 1].Name
                        if ($selected.Contains($name)) { [void]$selected.Remove($name) } else { [void]$selected.Add($name) }
                    }
                }
            }
        }
    }

    return @($info | Where-Object { $selected.Contains($_.Name) } | ForEach-Object { $_.Name })
}
