param(
  [string]$OutputDir = ""
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

function Get-InnoSetupCompilerPath {
  $candidates = @(
    "E:\Program Files (x86)\Inno Setup 6\ISCC.exe",
    "E:\Program Files\Inno Setup 6\ISCC.exe",
    "C:\Program Files (x86)\Inno Setup 6\ISCC.exe",
    "C:\Program Files\Inno Setup 6\ISCC.exe"
  )

  foreach ($candidate in $candidates) {
    if (Test-Path -LiteralPath $candidate) {
      return $candidate
    }
  }

  $resolved = (Get-Command ISCC.exe -ErrorAction SilentlyContinue | Select-Object -First 1).Source
  if (-not [string]::IsNullOrWhiteSpace($resolved)) {
    return $resolved
  }

  throw "ISCC.exe not found. Please install Inno Setup 6 first."
}

function Update-PubspecVersion([string]$pubspecPath) {
  $raw = Get-Content -LiteralPath $pubspecPath -Raw
  $match = [regex]::Match($raw, '(?m)^version:\s*(\d+)\.(\d+)\.(\d+)(?:\+\d+)?\s*$')
  if (-not $match.Success) {
    throw "Unable to parse version from $pubspecPath"
  }

  $major = [int]$match.Groups[1].Value
  $currentMonthInVersion = [int]$match.Groups[2].Value
  $currentSequence = [int]$match.Groups[3].Value
  $month = (Get-Date).Month
  $nextSequence = if ($currentMonthInVersion -eq $month) {
    $currentSequence + 1
  } else {
    0
  }

  $nextVersion = "{0}.{1}.{2}" -f $major, $month, $nextSequence
  $updated = [regex]::Replace(
    $raw,
    '(?m)^version:\s*\d+\.\d+\.\d+(?:\+\d+)?\s*$',
    "version: $nextVersion",
    1
  )
  Set-Content -LiteralPath $pubspecPath -Value $updated
  return $nextVersion
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$pubspecPath = Join-Path $repoRoot "pubspec.yaml"
$resolvedOutputDir = Get-ResolvedOutputDir $OutputDir
$issPath = Join-Path $repoRoot "windows\\installer\\starflow_windows_installer.iss"
$windowsBuildDir = Join-Path $repoRoot "build\\windows\\x64\\runner\\Release"
$installerBuildDir = Join-Path $repoRoot "build\\windows\\installer"
$isccPath = Get-InnoSetupCompilerPath

Push-Location $repoRoot
try {
  $version = Update-PubspecVersion $pubspecPath
  $buildDate = Get-Date -Format "yyyy-MM-dd"

  flutter build windows `
    --dart-define "STARFLOW_BUILD_DATE=$buildDate"
  if ($LASTEXITCODE -ne 0) {
    throw "flutter build windows failed with exit code $LASTEXITCODE"
  }

  & $isccPath $issPath
  if ($LASTEXITCODE -ne 0) {
    throw "ISCC.exe failed with exit code $LASTEXITCODE"
  }

  $installer = Get-ChildItem -LiteralPath $installerBuildDir -Filter "*.exe" |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
  if ($null -eq $installer) {
    throw "Installer output not found in $installerBuildDir"
  }

  $targetInstaller = Join-Path $resolvedOutputDir $installer.Name
  Copy-Item -LiteralPath $installer.FullName -Destination $targetInstaller -Force

  Write-Output "Version=$version"
  Write-Output "BuildDate=$buildDate"
  Write-Output "WINDOWS_RELEASE=$windowsBuildDir"
  Write-Output "INSTALLER=$targetInstaller"
}
finally {
  Pop-Location
}
