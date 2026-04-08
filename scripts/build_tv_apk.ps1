param(
  [string]$SettingsJsonPath = "",
  [string]$OutputDir = "",
  [string]$TargetPlatforms = "android-arm,android-arm64",
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
  $currentMonthInVersion = [int]$match.Groups[2].Value
  $currentSequence = [int]$match.Groups[3].Value
  $build = [int]$match.Groups[4].Value
  $month = (Get-Date).Month
  $nextSequence = if ($currentMonthInVersion -eq $month) {
    $currentSequence + 1
  } else {
    0
  }

  $nextVersion = "{0}.{1}.{2}+{3}" -f $major, $month, $nextSequence, ($build + 1)
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

function Get-AllowedApkAbis([string]$targetPlatforms) {
  $map = @{
    "android-arm" = "armeabi-v7a"
    "android-arm64" = "arm64-v8a"
    "android-x64" = "x86_64"
  }
  $abis = New-Object System.Collections.Generic.List[string]
  foreach ($platform in ($targetPlatforms -split ",")) {
    $normalized = $platform.Trim()
    if ([string]::IsNullOrWhiteSpace($normalized)) {
      continue
    }
    if ($map.ContainsKey($normalized) -and -not $abis.Contains($map[$normalized])) {
      $abis.Add($map[$normalized])
    }
  }
  return $abis.ToArray()
}

function Test-IsApkSignatureEntry([string]$entryName) {
  $normalized = $entryName.Replace("\", "/")
  return $normalized -match '^META-INF/(MANIFEST\.MF|[^/]+\.(SF|RSA|DSA))$'
}

function Optimize-ApkForTargetAbis(
  [string]$apkPath,
  [string[]]$allowedAbis
) {
  if (-not (Test-Path -LiteralPath $apkPath)) {
    throw "APK not found for ABI optimization: $apkPath"
  }
  if ($allowedAbis.Count -eq 0 -or $allowedAbis -contains "x86_64") {
    return
  }

  Add-Type -AssemblyName System.IO.Compression
  Add-Type -AssemblyName System.IO.Compression.FileSystem

  $buildToolsDir = Join-Path $env:ANDROID_SDK_ROOT "build-tools\\35.0.0"
  $zipalignPath = Join-Path $buildToolsDir "zipalign.exe"
  $apksignerPath = Join-Path $buildToolsDir "apksigner.bat"
  $debugKeystorePath = Join-Path $env:USERPROFILE ".android\\debug.keystore"
  if (-not (Test-Path -LiteralPath $zipalignPath)) {
    throw "zipalign not found: $zipalignPath"
  }
  if (-not (Test-Path -LiteralPath $apksignerPath)) {
    throw "apksigner not found: $apksignerPath"
  }
  if (-not (Test-Path -LiteralPath $debugKeystorePath)) {
    throw "debug keystore not found: $debugKeystorePath"
  }

  $tempDir = Join-Path $env:TEMP ("starflow-apk-opt-" + [Guid]::NewGuid().ToString("N"))
  $unsignedApk = Join-Path $tempDir "unsigned.apk"
  $alignedApk = Join-Path $tempDir "aligned.apk"
  $abiSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
  foreach ($abi in $allowedAbis) {
    if (-not [string]::IsNullOrWhiteSpace($abi)) {
      $abiSet.Add($abi) | Out-Null
    }
  }

  New-Item -ItemType Directory -Force -Path $tempDir | Out-Null
  try {
    $sourceArchive = [System.IO.Compression.ZipFile]::OpenRead($apkPath)
    try {
      $destinationStream = [System.IO.File]::Open($unsignedApk, [System.IO.FileMode]::Create)
      try {
        $destinationArchive = [System.IO.Compression.ZipArchive]::new(
          $destinationStream,
          [System.IO.Compression.ZipArchiveMode]::Create,
          $false
        )
        try {
          foreach ($entry in $sourceArchive.Entries) {
            $entryName = $entry.FullName
            if (Test-IsApkSignatureEntry $entryName) {
              continue
            }
            if ($entryName -match '^lib/([^/]+)/') {
              $abi = $Matches[1]
              if (-not $abiSet.Contains($abi)) {
                continue
              }
            }

            $newEntry = $destinationArchive.CreateEntry(
              $entryName,
              [System.IO.Compression.CompressionLevel]::Optimal
            )
            $newEntry.LastWriteTime = $entry.LastWriteTime
            if ($entryName.EndsWith("/")) {
              continue
            }
            $sourceStream = $entry.Open()
            $targetStream = $newEntry.Open()
            try {
              $sourceStream.CopyTo($targetStream)
            }
            finally {
              $targetStream.Dispose()
              $sourceStream.Dispose()
            }
          }
        }
        finally {
          $destinationArchive.Dispose()
        }
      }
      finally {
        $destinationStream.Dispose()
      }
    }
    finally {
      $sourceArchive.Dispose()
    }

    & $zipalignPath -f -p 4 $unsignedApk $alignedApk
    if ($LASTEXITCODE -ne 0) {
      throw "zipalign failed with exit code $LASTEXITCODE"
    }

    & $apksignerPath sign `
      --ks $debugKeystorePath `
      --ks-key-alias androiddebugkey `
      --ks-pass pass:android `
      --key-pass pass:android `
      --v1-signing-enabled true `
      --v2-signing-enabled true `
      --out $apkPath `
      $alignedApk
    if ($LASTEXITCODE -ne 0) {
      throw "apksigner failed with exit code $LASTEXITCODE"
    }
  }
  finally {
    if (Test-Path -LiteralPath $tempDir) {
      Remove-Item -LiteralPath $tempDir -Recurse -Force
    }
  }
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$pubspecPath = Join-Path $repoRoot "pubspec.yaml"
$resolvedOutputDir = Get-ResolvedOutputDir $OutputDir
$embeddedPath = $null
$allowedAbis = Get-AllowedApkAbis $TargetPlatforms

Push-Location $repoRoot
try {
  $version = Update-PubspecVersion $pubspecPath
  $embeddedPath = Set-EmbeddedSettings $repoRoot $SettingsJsonPath

  if (-not $SkipBuild) {
    flutter build apk `
      --release `
      --target-platform $TargetPlatforms `
      --android-skip-build-dependency-validation
    if ($LASTEXITCODE -ne 0) {
      throw "flutter build apk failed with exit code $LASTEXITCODE"
    }
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

  Optimize-ApkForTargetAbis -apkPath $sourceApk -allowedAbis $allowedAbis
  Copy-Item -LiteralPath $sourceApk -Destination $targetApk -Force
  Write-Output "Version=$version"
  Write-Output "TargetPlatforms=$TargetPlatforms"
  Write-Output "APK=$targetApk"
}
finally {
  Remove-EmbeddedSettings $embeddedPath
  Pop-Location
}
