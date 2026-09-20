param(
  [string]$SettingsJsonPath = "",
  [string]$OutputDir = "",
  [switch]$SkipBuild
)

$ErrorActionPreference = "Stop"

if ($SkipBuild) {
  throw "SkipBuild cannot produce a release artifact. Build and verify the APK; no version or settings have been changed."
}

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
  $version = & dart (Join-Path $PSScriptRoot "../tool/release_version.dart") $pubspecPath
  if ($LASTEXITCODE -ne 0) { throw "Release version update failed" }
  return $version
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
  & dart (Join-Path $repoRoot "tool/verify_tv_release.dart") --preflight
  if ($LASTEXITCODE -ne 0) { throw "TV release preflight failed" }
  if (-not [string]::IsNullOrWhiteSpace($SettingsJsonPath) -and -not (Test-Path -LiteralPath $SettingsJsonPath)) {
    throw "Settings JSON not found: $SettingsJsonPath"
  }
  $version = Update-PubspecVersion $pubspecPath
  $buildDate = Get-Date -Format "yyyy-MM-dd"
  $embeddedPath = Set-EmbeddedSettings $repoRoot $SettingsJsonPath

  if (-not $SkipBuild) {
    flutter build apk `
      --release `
      --target-platform android-arm,android-arm64 `
      --android-skip-build-dependency-validation `
      --build-name $version `
      --dart-define "STARFLOW_BUILD_DATE=$buildDate"
    if ($LASTEXITCODE -ne 0) {
      throw "flutter build apk failed with exit code $LASTEXITCODE"
    }
  }

  $namePrefix = if ([string]::IsNullOrWhiteSpace($SettingsJsonPath)) {
    "starflow-tv"
  } else {
    "starflow-tv-config"
  }
  $targetName = "$namePrefix-$version.apk"
  $sourceApk = Join-Path $repoRoot "build\\app\\outputs\\flutter-apk\\app-release.apk"
  $targetApk = Join-Path $resolvedOutputDir $targetName

  if (-not (Test-Path -LiteralPath $sourceApk)) {
    throw "Build output not found: $sourceApk"
  }

  $verifyArgs = @((Join-Path $repoRoot "tool/verify_tv_release.dart"), $sourceApk, $version)
  if (-not [string]::IsNullOrWhiteSpace($SettingsJsonPath)) { $verifyArgs += $SettingsJsonPath }
  & dart @verifyArgs
  if ($LASTEXITCODE -ne 0) { throw "TV release artifact verification failed" }
  Copy-Item -LiteralPath $sourceApk -Destination $targetApk -Force
  Write-Output "Version=$version"
  Write-Output "BuildDate=$buildDate"
  Write-Output "APK=$targetApk"
}
finally {
  Remove-EmbeddedSettings $embeddedPath
  Pop-Location
}
