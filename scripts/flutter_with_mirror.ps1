param(
  [string]$ProxyUrl,
  [switch]$UseOfficialSource,
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$FlutterArgs
)

$ErrorActionPreference = 'Stop'

if (-not $FlutterArgs -or $FlutterArgs.Count -eq 0) {
  $FlutterArgs = @('run')
}

$flutterCandidates = @(
  (Join-Path $PSScriptRoot '..\android\local.properties'),
  (Join-Path $PSScriptRoot '..\..\flutter\bin\flutter.bat'),
  'C:\dev\flutter\bin\flutter.bat'
)

$flutter = $null
foreach ($candidate in $flutterCandidates) {
  if ($candidate -like '*.properties') {
    $resolvedProperties = [System.IO.Path]::GetFullPath($candidate)
    if (Test-Path $resolvedProperties) {
      $flutterSdk = Select-String -Path $resolvedProperties -Pattern '^flutter\.sdk=(.+)$' | Select-Object -First 1
      if ($flutterSdk) {
        $flutterSdkPath = $flutterSdk.Matches[0].Groups[1].Value.Trim()
        $flutterFromSdk = Join-Path $flutterSdkPath 'bin\flutter.bat'
        if (Test-Path $flutterFromSdk) {
          $flutter = $flutterFromSdk
          break
        }
      }
    }
    continue
  }

  $resolved = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot $candidate))
  if (Test-Path $resolved) {
    $flutter = $resolved
    break
  }
}

if (-not $flutter) {
  $command = Get-Command flutter -ErrorAction SilentlyContinue
  if ($command) {
    $flutter = $command.Source
  }
}

if (-not $flutter) {
  throw '未找到 flutter。请先安装 Flutter，或把 flutter\\bin 加入 PATH。'
}

if (-not $UseOfficialSource) {
  $env:PUB_HOSTED_URL = 'https://pub.flutter-io.cn'
  $env:FLUTTER_STORAGE_BASE_URL = 'https://storage.flutter-io.cn'
}

$env:NO_PROXY = 'localhost,127.0.0.1'

if ($ProxyUrl) {
  $proxyUri = [Uri]$ProxyUrl
  $env:HTTP_PROXY = $proxyUri.AbsoluteUri
  $env:HTTPS_PROXY = $proxyUri.AbsoluteUri
  $env:http_proxy = $proxyUri.AbsoluteUri
  $env:https_proxy = $proxyUri.AbsoluteUri
  Write-Host "Using proxy: $($proxyUri.AbsoluteUri)"
}

if ($UseOfficialSource) {
  Write-Host 'Using official Flutter/Pub sources.'
} else {
  Write-Host "PUB_HOSTED_URL=$env:PUB_HOSTED_URL"
  Write-Host "FLUTTER_STORAGE_BASE_URL=$env:FLUTTER_STORAGE_BASE_URL"
}

Write-Host "Running: $flutter $($FlutterArgs -join ' ')"
& $flutter @FlutterArgs
exit $LASTEXITCODE
