#!/usr/bin/env pwsh
# Plezy Retrowave release: pull, check, build and publish in one go.
#
#   powershell -ExecutionPolicy Bypass -File .\windows\release.ps1
#
# The version comes from lib/retrowave_version.dart, the release text from
# RELEASE_NOTES_<version>.md. Bump the version and write the notes first.
#
#   -SkipAndroid / -SkipWindows   build only one platform
#   -Replace                      re-upload files (and notes) to an existing release
#   -NoPublish                    build and check only, no GitHub release
#   -SkipAnalyze                  skip the "flutter analyze" check

param(
    [switch]$SkipAndroid,
    [switch]$SkipWindows,
    [switch]$Replace,
    [switch]$NoPublish,
    [switch]$SkipAnalyze
)

$ErrorActionPreference = "Stop"
$repo = "thetwistedchi/plezy"
$root = Resolve-Path (Join-Path $PSScriptRoot "..")
Set-Location $root

function Step($text) { Write-Host "`n== $text" -ForegroundColor Magenta }
function Run($exe, [string[]]$arguments) {
    & $exe @arguments
    if ($LASTEXITCODE -ne 0) { throw "$exe $($arguments -join ' ') failed (exit $LASTEXITCODE)" }
}

Step "Version"
$match = Select-String -Path "lib\retrowave_version.dart" -Pattern "retrowaveVersion = '([^']+)'" | Select-Object -First 1
if (-not $match) { throw "Could not read retrowaveVersion from lib\retrowave_version.dart" }
$version = $match.Matches[0].Groups[1].Value
$tag = "v$version"
$notes = "RELEASE_NOTES_$version.md"
Write-Host "Plezy Retrowave $version ($tag)"
if (-not $NoPublish -and -not (Test-Path $notes)) { throw "$notes is missing" }

Step "Update sources"
Run git @("pull", "--ff-only")
Run flutter @("pub", "get")

if (-not $SkipAnalyze) {
    Step "flutter analyze (errors stop the release, warnings do not)"
    Run flutter @("analyze", "--no-fatal-infos", "--no-fatal-warnings")
}

$files = @()

if (-not $SkipWindows) {
    Step "Windows build"
    # Only a copy running from the build folder locks files; the installed app is left alone.
    $buildDir = (Join-Path (Get-Location) "build")
    Get-Process plezy -ErrorAction SilentlyContinue |
        Where-Object { $_.Path -and $_.Path.StartsWith($buildDir, [StringComparison]::OrdinalIgnoreCase) } |
        Stop-Process -Force
    Run flutter @("build", "windows", "--release")
    Run powershell @("-ExecutionPolicy", "Bypass", "-File", ".\windows\build-installer.ps1")
    $files += "plezy-retrowave-installer.exe", "plezy-retrowave-x64-portable.7z"
}

if (-not $SkipAndroid) {
    Step "Android build (universal)"
    Run flutter @("build", "apk", "--release", "--split-debug-info=build/symbols", "--obfuscate")
    Copy-Item build\app\outputs\flutter-apk\app-release.apk plezy-retrowave-universal.apk -Force

    Step "Android build (arm64)"
    Run flutter @("build", "apk", "--release", "--split-per-abi", "--split-debug-info=build/symbols", "--obfuscate")
    Copy-Item build\app\outputs\flutter-apk\app-arm64-v8a-release.apk plezy-retrowave-arm64.apk -Force
    $files += "plezy-retrowave-universal.apk", "plezy-retrowave-arm64.apk"
}

foreach ($f in $files) { if (-not (Test-Path $f)) { throw "$f was not built" } }

if ($NoPublish) {
    Step "Done (not published)"
    $files | ForEach-Object { Write-Host "  $_" }
    exit 0
}

Step "GitHub release $tag"
if ($Replace) {
    Run gh (@("release", "upload", $tag) + $files + @("--repo", $repo, "--clobber"))
    Run gh @("release", "edit", $tag, "--repo", $repo, "--notes-file", $notes)
} else {
    Run gh (@("release", "create", $tag, "--repo", $repo, "--title", "Plezy Retrowave $version", "--notes-file", $notes) + $files)
}

Step "Published"
Write-Host "https://github.com/$repo/releases/tag/$tag"
Write-Host "macOS: start the Codemagic build, then: gh release upload $tag plezy-retrowave-macos.dmg --repo $repo --clobber"
