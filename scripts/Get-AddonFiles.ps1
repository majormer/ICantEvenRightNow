# Get-AddonFiles.ps1
# Single source of truth for what ships in the addon: the TOC.
# Dot-source this file, then call Get-AddonManifest.

function Get-AddonManifest {
    param(
        [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot)
    )

    $addonName = "ICantEvenRightNow"
    $tocPath = Join-Path $RepoRoot "$addonName.toc"
    $tocLines = Get-Content -Path $tocPath

    $version = ($tocLines | Where-Object { $_ -match '^## Version:\s*(.+)$' } | ForEach-Object { $Matches[1].Trim() } | Select-Object -First 1)

    # Load-order files: every non-comment, non-blank TOC line.
    $codeFiles = @($tocLines | Where-Object { $_.Trim() -and -not $_.StartsWith("#") } | ForEach-Object { $_.Trim() -replace '\\', '/' })

    # Assets: any Interface\AddOns\<addon>\<file> path referenced by the TOC or Lua code.
    $pattern = "Interface\\{1,2}AddOns\\{1,2}$addonName\\{1,2}([A-Za-z0-9_.\-]+)"
    $sources = @($tocPath) + @($codeFiles | Where-Object { $_ -like "*.lua" } | ForEach-Object { Join-Path $RepoRoot $_ })
    $assets = @($sources | ForEach-Object { Select-String -Path $_ -Pattern $pattern -AllMatches } |
        ForEach-Object { $_.Matches } | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)

    [pscustomobject]@{
        AddonName = $addonName
        RepoRoot  = $RepoRoot
        Version   = $version
        Toc       = "$addonName.toc"
        CodeFiles = $codeFiles
        Assets    = $assets
        # Shipped alongside the addon but not loaded by the client.
        Extras    = @("LICENSE", "CHANGELOG.md")
    }
}
