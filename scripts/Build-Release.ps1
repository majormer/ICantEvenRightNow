# Build-Release.ps1
# Creates a local release zip of the addon. The file list comes from the TOC
# (code files) plus any Interface\AddOns\ICantEvenRightNow\... asset paths the
# TOC or Lua code reference, so new modules and icons are picked up automatically.
# Official releases are built by the tag-triggered packager workflow instead.

param(
    [Parameter(Mandatory=$false)]
    [string]$Version
)

$ErrorActionPreference = "Stop"
$ScriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Split-Path -Parent $ScriptPath
. (Join-Path $ScriptPath "Get-AddonFiles.ps1")
$Manifest = Get-AddonManifest -RepoRoot $RepoRoot

$AddonName = $Manifest.AddonName
if (-not $Version) { $Version = $Manifest.Version }
$BuildPath = Join-Path $RepoRoot "build"
$ReleaseRoot = Join-Path $BuildPath "release"
$ReleasePath = Join-Path $ReleaseRoot $AddonName
$ZipPath = Join-Path $BuildPath "$AddonName-v$Version.zip"

Write-Host "Building $AddonName v$Version..." -ForegroundColor Cyan

# Validate before packaging
& (Join-Path $ScriptPath "Test-Addon.ps1")
if ($LASTEXITCODE -ne 0) {
    Write-Host "Validation failed; not building." -ForegroundColor Red
    exit 1
}

# Clean build directory
if (Test-Path $BuildPath) {
    Write-Host "Cleaning build directory..." -ForegroundColor Yellow
    Remove-Item -Path $BuildPath -Recurse -Force
}

# Create build directories
New-Item -Path $ReleasePath -ItemType Directory -Force | Out-Null

$FilesToCopy = @($Manifest.Toc) + $Manifest.CodeFiles + $Manifest.Assets + $Manifest.Extras

foreach ($File in $FilesToCopy) {
    $SourceFile = Join-Path $RepoRoot $File
    if (Test-Path $SourceFile) {
        Write-Host "Copying $File..." -ForegroundColor Green
        $DestFile = Join-Path $ReleasePath $File
        New-Item -Path (Split-Path -Parent $DestFile) -ItemType Directory -Force | Out-Null
        Copy-Item -Path $SourceFile -Destination $DestFile -Force
    } else {
        Write-Host "Missing: $File" -ForegroundColor Red
        exit 1
    }
}

# Create ZIP file with the addon folder at the archive root
Write-Host "Creating ZIP file..." -ForegroundColor Yellow
Compress-Archive -Path $ReleasePath -DestinationPath $ZipPath -Force

Write-Host "`nBuild complete!" -ForegroundColor Green
Write-Host "Release directory: $ReleasePath" -ForegroundColor Gray
Write-Host "ZIP file: $ZipPath" -ForegroundColor Gray
