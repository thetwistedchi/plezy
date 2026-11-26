#!/usr/bin/env pwsh
# Plezy Retrowave release: pull, check, build and publish in one go.
#
#   powershell -ExecutionPolicy Bypass -File .\windows\release.ps1
#
# The version comes from lib/retrowave_version.dart, the release text from
# release-notes/<version>.md. Bump the version and write the notes first.
#
#   -SkipAndroid / -SkipWindows   build only one platform
#   -Replace                      (no longer needed: an existing release is updated)
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

# The compiled Dart code holds the version string. A build that still says
# an older version would make the updater offer the same release forever.
function Test-Contains([byte[]]$bytes, [string]$text) {
    # Latin-1 maps every byte to one character, so this is a plain byte search.
    return [Text.Encoding]::GetEncoding(28591).GetString($bytes).Contains($text)
}
function Assert-BuiltVersion([byte[]]$bytes, [string]$what) {
    if (-not (Test-Contains $bytes $version)) {
        throw "$what does not contain version $version (stale build). Run 'flutter clean' and start the release again."
    }
    Write-Host "$what is version $version"
}
function Assert-ApkVersion([string]$apk) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead((Resolve-Path $apk).Path)
    try {
        $entry = $zip.Entries | Where-Object { $_.FullName -like "lib/arm64-v8a/libapp.so" } | Select-Object -First 1
        if (-not $entry) { throw "$apk has no lib/arm64-v8a/libapp.so" }
        $stream = $entry.Open()
        $mem = New-Object IO.MemoryStream
        $stream.CopyTo($mem)
        $stream.Dispose()
        Assert-BuiltVersion $mem.ToArray() $apk
    } finally {
        $zip.Dispose()
    }
}

# Pull first: the version and notes must come from the code being built.
Step "Update sources"
Run git @("pull", "--ff-only")

Step "Version"
$match = Select-String -Path "lib\retrowave_version.dart" -Pattern "retrowaveVersion = '([^']+)'" | Select-Object -First 1
if (-not $match) { throw "Could not read retrowaveVersion from lib\retrowave_version.dart" }
$version = $match.Matches[0].Groups[1].Value
$tag = "v$version"
$notes = "release-notes\$version.md"
Write-Host "Plezy Retrowave $version ($tag)"
if (-not $NoPublish -and -not (Test-Path $notes)) { throw "$notes is missing" }

Step "Dependencies"
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
    Assert-BuiltVersion ([IO.File]::ReadAllBytes("build\windows\x64\runner\Release\data\app.so")) "Windows build"
    Run powershell @("-ExecutionPolicy", "Bypass", "-File", ".\windows\build-installer.ps1")
    $files += "plezy-retrowave-installer.exe", "plezy-retrowave-x64-portable.7z"
}

if (-not $SkipAndroid) {
    Step "Android build (universal)"
    Run flutter @("build", "apk", "--release", "--split-debug-info=build/symbols", "--obfuscate")
    Copy-Item build\app\outputs\flutter-apk\app-release.apk plezy-retrowave-universal.apk -Force
    Assert-ApkVersion plezy-retrowave-universal.apk

    Step "Android build (arm64)"
    Run flutter @("build", "apk", "--release", "--split-per-abi", "--split-debug-info=build/symbols", "--obfuscate")
    Copy-Item build\app\outputs\flutter-apk\app-arm64-v8a-release.apk plezy-retrowave-arm64.apk -Force
    Assert-ApkVersion plezy-retrowave-arm64.apk
    $files += "plezy-retrowave-universal.apk", "plezy-retrowave-arm64.apk"
}

foreach ($f in $files) { if (-not (Test-Path $f)) { throw "$f was not built" } }

if ($NoPublish) {
    Step "Done (not published)"
    $files | ForEach-Object { Write-Host "  $_" }
    exit 0
}

Step "GitHub release $tag"
# A release that already exists (e.g. a rebuild) gets its files replaced and
# its notes refreshed instead of failing.
# (Windows PowerShell turns redirected stderr into errors under "Stop".)
$ErrorActionPreference = "Continue"
& gh release view $tag --repo $repo *> $null
$exists = $LASTEXITCODE -eq 0
$ErrorActionPreference = "Stop"
if ($Replace -or $exists) {
    if ($exists) { Write-Host "$tag exists: replacing its files and notes" }
    Run gh (@("release", "upload", $tag) + $files + @("--repo", $repo, "--clobber"))
    Run gh @("release", "edit", $tag, "--repo", $repo, "--notes-file", $notes)
} else {
    Run gh (@("release", "create", $tag, "--repo", $repo, "--title", "Plezy Retrowave $version", "--notes-file", $notes) + $files)
}

Step "Published"
Write-Host "https://github.com/$repo/releases/tag/$tag"
Write-Host "macOS: the DMG is built and attached by the GitHub workflow (about 20 minutes)."
