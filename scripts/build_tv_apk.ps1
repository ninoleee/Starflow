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
  $version = & $dart (Join-Path $PSScriptRoot "../tool/release_version.dart") $pubspecPath
  if ($LASTEXITCODE -ne 0) { throw "Release version update failed" }
  return $version
}

function Set-EmbeddedSettings(
  [string]$repoRoot,
  [string]$settingsPath
) {
  $embeddedDir = Join-Path $repoRoot "assets/bootstrap"
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
$bootstrapPath = Join-Path $repoRoot "assets/bootstrap/embedded_settings.json"
$originalSettings = $null
$bootstrapChanged = $false
$staging = $null

if ([string]::IsNullOrWhiteSpace($env:STARFLOW_FLUTTER_SDK) -and (Test-Path (Join-Path $repoRoot ".fvm/flutter_sdk"))) {
  $env:STARFLOW_FLUTTER_SDK = Join-Path $repoRoot ".fvm/flutter_sdk"
}
$flutterName = if ($env:OS -eq "Windows_NT") { "flutter.bat" } else { "flutter" }
$dartName = if ($env:OS -eq "Windows_NT") { "dart.bat" } else { "dart" }
$flutter = if ([string]::IsNullOrWhiteSpace($env:STARFLOW_FLUTTER_SDK)) {
  (Get-Command $flutterName -ErrorAction Stop).Source
} else {
  Join-Path $env:STARFLOW_FLUTTER_SDK "bin/$flutterName"
}
$flutter = (Resolve-Path -LiteralPath $flutter).Path
$dart = Join-Path (Split-Path $flutter) $dartName
$env:STARFLOW_FLUTTER_SDK = Split-Path (Split-Path $flutter)
$env:PATH = "$(Split-Path $flutter)$([IO.Path]::PathSeparator)$env:PATH"
if (-not [string]::IsNullOrWhiteSpace($SettingsJsonPath)) {
  $SettingsJsonPath = (Resolve-Path -LiteralPath $SettingsJsonPath).Path
}

Push-Location $repoRoot
try {
  $preflightArgs = @((Join-Path $repoRoot "tool/verify_tv_release.dart"), "--preflight")
  if (-not [string]::IsNullOrWhiteSpace($SettingsJsonPath)) { $preflightArgs += $SettingsJsonPath }
  & $dart @preflightArgs
  if ($LASTEXITCODE -ne 0) { throw "TV release preflight failed" }
  if (Test-Path -LiteralPath $bootstrapPath) {
    $originalSettings = [IO.File]::ReadAllBytes($bootstrapPath)
  }
  if (-not [string]::IsNullOrWhiteSpace($SettingsJsonPath)) {
    $staging = [IO.Path]::GetTempFileName()
    Copy-Item -LiteralPath $SettingsJsonPath -Destination $staging -Force
    $SettingsJsonPath = $staging
  }
  $bootstrapChanged = $true
  $embeddedPath = Set-EmbeddedSettings $repoRoot $SettingsJsonPath
  $version = Update-PubspecVersion $pubspecPath
  $buildDate = Get-Date -Format "yyyy-MM-dd"

  & $flutter build apk `
    --release `
    --target-platform android-arm,android-arm64 `
    --android-skip-build-dependency-validation `
    --build-name $version `
    --dart-define "STARFLOW_BUILD_DATE=$buildDate"
  if ($LASTEXITCODE -ne 0) {
    throw "flutter build apk failed with exit code $LASTEXITCODE"
  }

  $namePrefix = if ([string]::IsNullOrWhiteSpace($SettingsJsonPath)) {
    "starflow-tv"
  } else {
    "starflow-tv-config"
  }
  $targetName = "$namePrefix-$version.apk"
  $sourceApk = Join-Path $repoRoot "build/app/outputs/flutter-apk/app-release.apk"
  $targetApk = Join-Path $resolvedOutputDir $targetName

  if (-not (Test-Path -LiteralPath $sourceApk)) {
    throw "Build output not found: $sourceApk"
  }

  $verifyArgs = @((Join-Path $repoRoot "tool/verify_tv_release.dart"), $sourceApk, $version)
  if (-not [string]::IsNullOrWhiteSpace($SettingsJsonPath)) { $verifyArgs += $SettingsJsonPath }
  & $dart @verifyArgs
  if ($LASTEXITCODE -ne 0) { throw "TV release artifact verification failed" }
  Copy-Item -LiteralPath $sourceApk -Destination $targetApk -Force
  Write-Output "Version=$version"
  Write-Output "BuildDate=$buildDate"
  Write-Output "APK=$targetApk"
}
finally {
  if ($bootstrapChanged) {
    Remove-EmbeddedSettings $bootstrapPath
    if ($null -ne $originalSettings) { [IO.File]::WriteAllBytes($bootstrapPath, $originalSettings) }
  }
  if ($null -ne $staging) { Remove-Item -LiteralPath $staging -Force }
  Pop-Location
}
