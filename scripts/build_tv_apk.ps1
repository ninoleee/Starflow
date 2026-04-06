param(
  [string]$SettingsJsonPath = "",
  [string]$OutputDir = "",
  [switch]$SkipBuild
)

$ErrorActionPreference = "Stop"

function Get-DefaultOutputDir {
  return [Environment]::GetFolderPath("Desktop")
}

function Get-ResolvedOutputDir([string]$path) {
  if ([string]::IsNullOrWhiteSpace($path)) {
    return (Get-DefaultOutputDir)
  }
  return (Resolve-Path -LiteralPath $path).Path
}

function Update-PubspecVersion([string]$pubspecPath) {
  $raw = Get-Content -LiteralPath $pubspecPath -Raw
  $match = [regex]::Match($raw, '(?m)^version:\s*(\d+)\.(\d+)\.(\d+)\+(\d+)\s*$')
  if (-not $match.Success) {
    throw "Unable to parse version from $pubspecPath"
  }

  $major = [int]$match.Groups[1].Value
  $build = [int]$match.Groups[4].Value
  $month = (Get-Date).Month
  $day = (Get-Date).Day

  $nextVersion = "{0}.{1}.{2}+{3}" -f $major, $month, $day, ($build + 1)
  $updated = [regex]::Replace(
    $raw,
    '(?m)^version:\s*\d+\.\d+\.\d+\+\d+\s*$',
    "version: $nextVersion",
    1
  )
  Set-Content -LiteralPath $pubspecPath -Value $updated
  return $nextVersion
}

function Set-EmbeddedSettings(
  [string]$repoRoot,
  [string]$settingsPath
) {
  $embeddedDir = Join-Path $repoRoot "assets\\bootstrap"
  $embeddedPath = Join-Path $embeddedDir "embedded_settings.json"
  New-Item -ItemType Directory -Force -Path $embeddedDir | Out-Null

  if ([string]::IsNullOrWhiteSpace($settingsPath)) {
    if (Test-Path -LiteralPath $embeddedPath) {
      Remove-Item -LiteralPath $embeddedPath -Force
    }
    return $null
  }

  if (-not (Test-Path -LiteralPath $settingsPath)) {
    throw "Settings JSON not found: $settingsPath"
  }

  Copy-Item -LiteralPath $settingsPath -Destination $embeddedPath -Force
  return $embeddedPath
}

function Remove-EmbeddedSettings([string]$embeddedPath) {
  if ([string]::IsNullOrWhiteSpace($embeddedPath)) {
    return
  }
  if (Test-Path -LiteralPath $embeddedPath) {
    Remove-Item -LiteralPath $embeddedPath -Force
  }
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$pubspecPath = Join-Path $repoRoot "pubspec.yaml"
$resolvedOutputDir = Get-ResolvedOutputDir $OutputDir
$embeddedPath = $null

Push-Location $repoRoot
try {
  $version = Update-PubspecVersion $pubspecPath
  $embeddedPath = Set-EmbeddedSettings $repoRoot $SettingsJsonPath

  if (-not $SkipBuild) {
    flutter build apk --release
  }

  $displayVersion = $version.Split("+")[0]
  $namePrefix = if ([string]::IsNullOrWhiteSpace($SettingsJsonPath)) {
    "starflow-tv"
  } else {
    "starflow-tv-config"
  }
  $targetName = "$namePrefix-$displayVersion.apk"
  $sourceApk = Join-Path $repoRoot "build\\app\\outputs\\flutter-apk\\app-release.apk"
  $targetApk = Join-Path $resolvedOutputDir $targetName

  if (-not (Test-Path -LiteralPath $sourceApk)) {
    throw "Build output not found: $sourceApk"
  }

  Copy-Item -LiteralPath $sourceApk -Destination $targetApk -Force
  Write-Output "Version=$version"
  Write-Output "APK=$targetApk"
}
finally {
  Remove-EmbeddedSettings $embeddedPath
  Pop-Location
}
