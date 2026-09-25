# Test-Addon.ps1
# Static checks to run before committing or deploying. Exits non-zero on failure.
#
#   .\scripts\Test-Addon.ps1          full check
#   .\scripts\Test-Addon.ps1 -Hook    used by .githooks/pre-commit (missing luac is a warning)
#
# Lua compiler lookup order: $env:LUAC, LUAC=... in .env, then luac5.1 / luac / luac5.4 on PATH.
# WoW runs Lua 5.1; a newer luac is fine for syntax but misses 5.1-only errors.

param(
    [switch]$Hook
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
. (Join-Path $PSScriptRoot "Get-AddonFiles.ps1")
$m = Get-AddonManifest -RepoRoot $RepoRoot

$failures = New-Object System.Collections.Generic.List[string]
$warnings = New-Object System.Collections.Generic.List[string]

function Get-DotEnvValue([string]$Name) {
    $envFile = Join-Path $RepoRoot ".env"
    if (-not (Test-Path $envFile)) { return $null }
    $line = Get-Content $envFile | Where-Object { $_ -match "^\s*$Name\s*=\s*(.+)$" } | Select-Object -First 1
    if ($line -and $line -match "=\s*(.+)$") { return $Matches[1].Trim().Trim('"') }
    return $null
}

function Resolve-Luac {
    foreach ($candidate in @($env:LUAC, (Get-DotEnvValue "LUAC"))) {
        if ($candidate -and (Test-Path $candidate)) { return $candidate }
    }
    foreach ($name in @("luac5.1", "luac", "luac5.4", "luac54")) {
        $cmd = Get-Command $name -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($cmd) { return $cmd.Source }
    }
    return $null
}

Push-Location $RepoRoot
try {
    # 1. TOC files and referenced assets exist
    foreach ($f in @($m.CodeFiles) + @($m.Assets)) {
        if (-not (Test-Path $f)) { $failures.Add("Missing file referenced by TOC or code: $f") }
    }

    # 2. Lua syntax
    $luac = Resolve-Luac
    $luaFiles = @(git ls-files "*.lua")
    if ($luac) {
        $out = & $luac -p @luaFiles 2>&1
        if ($LASTEXITCODE -ne 0) { $failures.Add("Lua parse failed:`n$($out -join "`n")") }
    } else {
        $msg = "No Lua compiler found; syntax not checked. Set LUAC in .env or install Lua 5.1."
        if ($Hook) { $warnings.Add($msg) } else { $failures.Add($msg) }
    }

    # 3. Leftover merge conflict markers
    $textFiles = @(git ls-files | Where-Object { $_ -match '\.(lua|toc|md|ps1|yml|json|pkgmeta)$' -or $_ -eq ".pkgmeta" })
    $markers = Select-String -Path $textFiles -Pattern '^(<{7}|>{7}) ' -ErrorAction SilentlyContinue
    foreach ($hit in $markers) { $failures.Add("Conflict marker: $($hit.Path):$($hit.LineNumber)") }

    # 4. Line endings stored in the index must be LF (see .gitattributes)
    $badEol = @(git ls-files --eol | Where-Object { $_ -match '^i/(crlf|mixed)' })
    foreach ($row in $badEol) { $failures.Add("Non-LF line endings in index: $(($row -split "`t")[-1]). Run: git add --renormalize .") }

    # 5. Version sanity: TOC version has a CHANGELOG section, or there is an Unreleased section
    $changelog = Get-Content "CHANGELOG.md" -Raw
    $hasVersion = $changelog -match ("(?m)^## \[" + [regex]::Escape($m.Version) + "\]")
    $hasUnreleased = $changelog -match '(?m)^## \[Unreleased\]'
    if (-not ($hasVersion -or $hasUnreleased)) {
        $failures.Add("CHANGELOG.md has neither a [$($m.Version)] nor an [Unreleased] section.")
    }
}
finally {
    Pop-Location
}

foreach ($w in $warnings) { Write-Host "WARN  $w" -ForegroundColor Yellow }
if ($failures.Count -gt 0) {
    foreach ($f in $failures) { Write-Host "FAIL  $f" -ForegroundColor Red }
    exit 1
}
$luacLabel = if ($luac) { " (luac: $luac)" } else { "" }
Write-Host "OK    $($m.AddonName) $($m.Version): $($m.CodeFiles.Count) code files, $($m.Assets.Count) assets$luacLabel" -ForegroundColor Green
exit 0
