$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$flutter = 'C:\dev\flutter\bin\flutter.bat'
$javaHome = 'C:\Program Files\ojdkbuild\java-17-openjdk-17.0.3.0.6-1'
$proxyPort = 8787

$env:JAVA_HOME = $javaHome
$env:PATH = "$javaHome\bin;C:\dev\flutter\bin;$env:PATH"

$proxy = Start-Process `
  -FilePath 'dart' `
  -ArgumentList @('run', 'tool\web_dev_proxy.dart', "--port=$proxyPort") `
  -WorkingDirectory $root `
  -PassThru

try {
  Start-Sleep -Seconds 2
  & $flutter run -d edge --dart-define=STARFLOW_WEB_PROXY_BASE=http://127.0.0.1:$proxyPort
} finally {
  if ($proxy -and !$proxy.HasExited) {
    Stop-Process -Id $proxy.Id -Force
  }
}
