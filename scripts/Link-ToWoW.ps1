# Link-ToWoW.ps1
# Points the WoW AddOns folder at this repository with a directory junction, so
# edits (and branch switches) are live after /reload with no copy step.
#
#   .\scripts\Link-ToWoW.ps1                 create the junction
#   .\scripts\Link-ToWoW.ps1 -Replace        replace an existing copied folder
#   .\scripts\Link-ToWoW.ps1 -Unlink         remove the junction (repo is untouched)
#
# AddOns path lookup order: -AddOnsPath, WOW_ADDONS_PATH in .env, default Battle.net path.
# A junction needs no admin rights. WoW only loads files listed in the TOC, so
# extra repo files (docs, .git) in the folder are ignored by the client.

param(
    [string]$AddOnsPath,
    [switch]$Replace,
    [switch]$Unlink
)

$ErrorActionPreference = "Stop"
$AddonName = "ICantEvenRightNow"
$RepoRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)

if (-not $AddOnsPath) {
    $envFile = Join-Path $RepoRoot ".env"
    if (Test-Path $envFile) {
        $line = Get-Content $envFile | Where-Object { $_ -match '^\s*WOW_ADDONS_PATH\s*=\s*(.+)$' } | Select-Object -First 1
        if ($line -and $line -match '=\s*(.+)$') { $AddOnsPath = $Matches[1].Trim().Trim('"') }
    }
}
if (-not $AddOnsPath) { $AddOnsPath = "C:\Program Files (x86)\World of Warcraft\_retail_\Interface\AddOns" }

if (-not (Test-Path $AddOnsPath)) {
    Write-Host "AddOns folder not found: $AddOnsPath" -ForegroundColor Red
    Write-Host "Pass -AddOnsPath or set WOW_ADDONS_PATH in .env" -ForegroundColor Yellow
    exit 1
}

$Target = Join-Path $AddOnsPath $AddonName
$existing = Get-Item -Path $Target -Force -ErrorAction SilentlyContinue

if ($Unlink) {
    if ($existing -and $existing.LinkType -eq "Junction") {
        # Removing a junction deletes only the link, never the repository it points to.
        $existing.Delete()
        Write-Host "Removed junction $Target" -ForegroundColor Green
    } else {
        Write-Host "No junction at $Target; nothing to do." -ForegroundColor Yellow
    }
    exit 0
}

if ($existing) {
    if ($existing.LinkType -eq "Junction" -and ($existing.Target -eq $RepoRoot -or $existing.Target -contains $RepoRoot)) {
        Write-Host "Already linked: $Target -> $RepoRoot" -ForegroundColor Green
        exit 0
    }
    if ($existing.LinkType) {
        Write-Host "$Target is a $($existing.LinkType) to $($existing.Target). Remove it first." -ForegroundColor Red
        exit 1
    }
    if (-not $Replace) {
        Write-Host "$Target is a copied folder. Re-run with -Replace to swap it for a junction." -ForegroundColor Yellow
        exit 1
    }
    Write-Host "Removing copied folder $Target" -ForegroundColor Yellow
    Remove-Item -Path $Target -Recurse -Force
}

New-Item -ItemType Junction -Path $Target -Target $RepoRoot | Out-Null
Write-Host "Linked: $Target -> $RepoRoot" -ForegroundColor Green
Write-Host "Type /reload in game to pick up changes." -ForegroundColor Cyan
