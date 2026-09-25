# Build-Release.ps1
# Creates a release package of the ICantEvenRightNow addon with proper directory structure

param(
    [Parameter(Mandatory=$false)]
    [string]$Version = "0.6.0"
)

$AddonName = "ICantEvenRightNow"
$ScriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Split-Path -Parent $ScriptPath
$BuildPath = Join-Path $RepoRoot "build"
$ReleaseRoot = Join-Path $BuildPath "release"
$ReleasePath = Join-Path $ReleaseRoot $AddonName
$ZipPath = Join-Path $BuildPath "$AddonName-v$Version.zip"

Write-Host "Building $AddonName v$Version..." -ForegroundColor Cyan

# Clean build directory
if (Test-Path $BuildPath) {
    Write-Host "Cleaning build directory..." -ForegroundColor Yellow
    Remove-Item -Path $BuildPath -Recurse -Force
}

# Create build directories
New-Item -Path $ReleasePath -ItemType Directory -Force | Out-Null

# Copy addon files to release directory (matching Heirloom structure)
$FilesToCopy = @(
    "$AddonName.toc",
    "$AddonName.png",
    "ICantEvenRightNow_icon.png",
    "ICantEvenRightNow_icon.tga",
    "Core.lua",
    "Data.lua",
    "Debug.lua",
    "Shared.lua",
    "Evaluator.lua",
    "Filter.lua",
    "Scanner.lua",
    "Transfer.lua",
    "UI.lua",
    "LICENSE",
    "CHANGELOG.md"
)

foreach ($File in $FilesToCopy) {
    $SourceFile = Join-Path $RepoRoot $File
    if (Test-Path $SourceFile) {
        Write-Host "Copying $File..." -ForegroundColor Green
        Copy-Item -Path $SourceFile -Destination $ReleasePath -Recurse -Force
    } else {
        Write-Host "Warning: $File not found" -ForegroundColor Yellow
    }
}

# Create ZIP file with the addon folder at the archive root
Write-Host "Creating ZIP file..." -ForegroundColor Yellow
Compress-Archive -Path $ReleasePath -DestinationPath $ZipPath -Force

Write-Host "`nBuild complete!" -ForegroundColor Green
Write-Host "Release directory: $ReleasePath" -ForegroundColor Gray
Write-Host "ZIP file: $ZipPath" -ForegroundColor Gray
