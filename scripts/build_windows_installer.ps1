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

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$resolvedOutputDir = Get-ResolvedOutputDir $OutputDir
$issPath = Join-Path $repoRoot "windows\\installer\\starflow_windows_installer.iss"
$windowsBuildDir = Join-Path $repoRoot "build\\windows\\x64\\runner\\Release"
$installerBuildDir = Join-Path $repoRoot "build\\windows\\installer"
$isccPath = Get-InnoSetupCompilerPath

Push-Location $repoRoot
try {
  flutter build windows
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

  Write-Output "WINDOWS_RELEASE=$windowsBuildDir"
  Write-Output "INSTALLER=$targetInstaller"
}
finally {
  Pop-Location
}
