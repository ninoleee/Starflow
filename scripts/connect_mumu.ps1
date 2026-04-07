param(
  [string]$MuMuRoot = "E:\Program Files\Netease\MuMu"
)

$ErrorActionPreference = "Stop"

function Get-AdbPath {
  $candidates = @(
    "C:\Users\ninol\AppData\Local\Android\Sdk\platform-tools\adb.exe",
    (Join-Path $MuMuRoot "nx_main\adb.exe"),
    (Join-Path $MuMuRoot "nx_device\12.0\shell\adb.exe")
  )

  foreach ($candidate in $candidates) {
    if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path -LiteralPath $candidate)) {
      return $candidate
    }
  }

  $resolved = (Get-Command adb -ErrorAction SilentlyContinue | Select-Object -First 1).Source
  if (-not [string]::IsNullOrWhiteSpace($resolved)) {
    return $resolved
  }

  throw "adb.exe not found."
}

function Get-MuMuVmConfigs([string]$root) {
  $vmRoot = Join-Path $root "vms"
  if (-not (Test-Path -LiteralPath $vmRoot)) {
    throw "MuMu VM directory not found: $vmRoot"
  }

  return Get-ChildItem -LiteralPath $vmRoot -Recurse -Filter vm_config.json |
    Sort-Object LastWriteTime -Descending
}

function Get-ConnectTargets([string]$configPath) {
  $content = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
  $guestIp = $content.vm.nat.port_forward.adb.guest_ip
  $hostPort = $content.vm.nat.port_forward.adb.host_port
  $targets = @()

  if (-not [string]::IsNullOrWhiteSpace($guestIp)) {
    $targets += "${guestIp}:5555"
  }

  if (-not [string]::IsNullOrWhiteSpace($hostPort)) {
    $targets += "127.0.0.1:$hostPort"
  }

  return $targets
}

function Try-Connect([string]$adbPath, [string]$target) {
  $output = & $adbPath connect $target 2>&1
  $success = ($LASTEXITCODE -eq 0) -and (
    ($output -match "connected to") -or
    ($output -match "already connected to")
  )

  [PSCustomObject]@{
    Target = $target
    Success = $success
    Output = ($output -join [Environment]::NewLine).Trim()
  }
}

$adbPath = Get-AdbPath
$configs = Get-MuMuVmConfigs $MuMuRoot
$attempts = @()

foreach ($config in $configs) {
  foreach ($target in (Get-ConnectTargets $config.FullName)) {
    if ($attempts.Target -contains $target) {
      continue
    }
    $attempt = Try-Connect $adbPath $target
    $attempts += $attempt
    if ($attempt.Success) {
      Write-Output "ADB=$adbPath"
      Write-Output "TARGET=$target"
      Write-Output "CONFIG=$($config.FullName)"
      Write-Output "RESULT=$($attempt.Output)"
      & $adbPath devices
      exit 0
    }
  }
}

Write-Output "ADB=$adbPath"
foreach ($attempt in $attempts) {
  Write-Output "FAILED_TARGET=$($attempt.Target)"
  Write-Output "FAILED_RESULT=$($attempt.Output)"
}
throw "Unable to connect to any MuMu instance. Confirm MuMu is running and ADB remote connect is enabled."
