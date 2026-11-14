param(
    [ValidateSet('fenix7pro', 'instinct2')][string]$Device = 'fenix7pro',
    [switch]$Run,
    [switch]$Release,
    [switch]$Test,
    [string[]]$TestName,
    [ValidateRange(0, 60)][int]$TestAlarmMinutes = 0,
    [string]$Key = (Join-Path $PSScriptRoot 'developer_key')
)
$ErrorActionPreference = 'Stop'
if ($Release -and $Test) { throw 'Use a debug build for simulator tests.' }
if ($TestName -and !$Test) { throw 'TestName requires -Test.' }
if ($Test -and $TestAlarmMinutes) { throw 'TestAlarmMinutes is for sideload/simulator app builds, not unit tests.' }
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
if (!(Test-Path -LiteralPath $Key)) { throw 'Place your signing key at developer_key or supply -Key <path>.' }
$devicePackage = Join-Path $env:APPDATA "Garmin\ConnectIQ\Devices\$Device\compiler.json"
if (!(Test-Path -LiteralPath $devicePackage)) { throw "Install the $Device device package in Garmin SDK Manager first." }
$outputName = if ($Test) { 'JumpStart-tests.prg' } else { 'JumpStart.prg' }
$output = Join-Path $PSScriptRoot "bin\$Device\$outputName"
New-Item -ItemType Directory -Force -Path (Split-Path $output) | Out-Null
$jungle = 'monkey.jungle'
if ($TestAlarmMinutes) {
    $deadline = [DateTimeOffset]::Now.AddMinutes($TestAlarmMinutes)
    $deadline = [DateTimeOffset]::FromUnixTimeSeconds([long]([Math]::Ceiling($deadline.ToUnixTimeSeconds() / 60.0) * 60))
    $generated = Join-Path $PSScriptRoot "build\alarm-$Device"
    New-Item -ItemType Directory -Force -Path "$generated\resources" | Out-Null
    "<properties><property id=`"SideloadTestAt`" type=`"number`">$($deadline.ToUnixTimeSeconds())</property></properties>" |
        Set-Content -LiteralPath "$generated\resources\properties.xml" -Encoding utf8
    $rootPath = $PSScriptRoot.Replace('\', '/')
    $generatedPath = $generated.Replace('\', '/')
    @("project.manifest = $rootPath/manifest.xml",
      "base.sourcePath = $rootPath/source/common;$rootPath/test",
      "fenix7pro.sourcePath = `$(base.sourcePath);$rootPath/source/fenix7pro",
      "instinct2.sourcePath = `$(base.sourcePath);$rootPath/source/instinct2",
      "instinct2.resourcePath = `$(base.resourcePath);$rootPath/resources-instinct2",
      "base.resourcePath = $rootPath/resources;$generatedPath/resources") |
        Set-Content -LiteralPath "$generated\sideload.jungle" -Encoding utf8
    $jungle = "$generated\sideload.jungle"
    Write-Host "One-off test alarm: $($deadline.ToString('yyyy-MM-dd HH:mm:ss zzz')). Open the app on the watch before then."
}
Push-Location $PSScriptRoot
try {
    $compilerArgs = @('-f', $jungle, '-d', $Device, '-o', $output, '-y', $Key, '-l', '1', '-w')
    if ($Release) { $compilerArgs += '-r' }
    if ($Test) { $compilerArgs += '--unit-test' }
    & (Join-Path $sdk 'bin\monkeyc.bat') @compilerArgs
    if ($LASTEXITCODE -ne 0) { throw "Monkey C build failed ($LASTEXITCODE)." }
    if ($Run -or $Test) {
        if (!(Get-Process simulator -ErrorAction SilentlyContinue)) {
            $windowStyle = if ($Test) { 'Hidden' } else { 'Normal' }
            Start-Process -FilePath (Join-Path $sdk 'bin\simulator.exe') -WindowStyle $windowStyle
            Start-Sleep -Seconds 3
        }
        $runnerArgs = @($output, $Device)
        if ($Test) {
            $runnerArgs += '/t'
            if ($TestName) { $runnerArgs += $TestName }
            $logPath = Join-Path (Split-Path $output) 'test-results.txt'
            $testOutput = & (Join-Path $sdk 'bin\monkeydo.bat') @runnerArgs 2>&1
            $testOutput | Tee-Object -FilePath $logPath
            # SDK releases differ in their test runner exit codes; use its summary.
            if (!(($testOutput -join "`n") -match '(?m)^PASSED \(passed=\d+, failed=0, errors=0\)')) {
                throw "Simulator tests failed; see $logPath"
            }
        } else {
            & (Join-Path $sdk 'bin\monkeydo.bat') @runnerArgs
            if ($LASTEXITCODE -ne 0) { throw "Simulator launch failed ($LASTEXITCODE)." }
        }
    }
} finally {
    Pop-Location
    $env:PATH = $originalPath
}
