param([switch]$Run, [switch]$Release)
$ErrorActionPreference = 'Stop'
$originalPath = $env:PATH
if (!(Get-Command java -ErrorAction SilentlyContinue)) {
    $javaHomes = @($env:JAVA_HOME)
    $adoptium = Join-Path $env:ProgramFiles 'Eclipse Adoptium'
    if (Test-Path -LiteralPath $adoptium) {
        $javaHomes += Get-ChildItem -LiteralPath $adoptium -Directory | Sort-Object Name -Descending | Select-Object -ExpandProperty FullName
    }
    $javaHome = $javaHomes | Where-Object { $_ -and (Test-Path -LiteralPath (Join-Path $_ 'bin\java.exe')) } | Select-Object -First 1
    if (!$javaHome) { throw 'Java was not found. Install a JDK or set JAVA_HOME.' }
    $env:PATH = (Join-Path $javaHome 'bin') + ';' + $env:PATH
}
$sdkConfig = Join-Path $env:APPDATA 'Garmin\ConnectIQ\current-sdk.cfg'
if (!(Test-Path -LiteralPath $sdkConfig)) { throw 'Install and select a Connect IQ SDK in SDK Manager first.' }
$sdk = (Get-Content -LiteralPath $sdkConfig -Raw).Trim()
$key = Join-Path $PSScriptRoot 'developer_key'
if (!(Test-Path -LiteralPath $key)) { throw 'Place your Connect IQ developer signing key at developer_key.' }
$output = Join-Path $PSScriptRoot 'bin\EmptyApp.prg'
New-Item -ItemType Directory -Force -Path (Split-Path $output) | Out-Null
Push-Location $PSScriptRoot
try {
    $compilerArgs = @('-f', 'monkey.jungle', '-d', 'fenix7pro', '-o', $output, '-y', $key, '-w')
    if ($Release) { $compilerArgs += '-r' }
    & (Join-Path $sdk 'bin\monkeyc.bat') @compilerArgs
    if ($LASTEXITCODE -ne 0) { throw "Monkey C build failed ($LASTEXITCODE)." }
    if ($Run) {
        if (!(Get-Process simulator -ErrorAction SilentlyContinue)) {
            Start-Process -FilePath (Join-Path $sdk 'bin\simulator.exe') -WindowStyle Normal
            Start-Sleep -Seconds 3
        }
        $runnerArgs = @($output, 'fenix7pro')
        & (Join-Path $sdk 'bin\monkeydo.bat') @runnerArgs
        if ($LASTEXITCODE -ne 0) { throw "Simulator launch failed ($LASTEXITCODE)." }
    }
} finally {
    Pop-Location
    $env:PATH = $originalPath
}
