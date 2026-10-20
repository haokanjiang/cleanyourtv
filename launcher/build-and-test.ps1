# Build, install and launch CleanYourTV without taking over the Home button.
# Intended for first-pass device validation on MiTV-MFTR0 and other TVs.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File launcher\build-and-test.ps1 -TvHost 192.168.1.50
#
# The script never disables a package. Installing a HOME-capable APK can make Android forget the
# previous default, so the previous Home component is recorded and restored if installation changes it.
param(
    [string]$TvHost = $env:TV_HOST
)
$ErrorActionPreference = 'Stop'
$OutputEncoding = New-Object System.Text.UTF8Encoding $false
if (-not $TvHost) { throw 'pass -TvHost <tv ip> or set $env:TV_HOST' }
$env:TV_HOST = $TvHost
Set-Location $PSScriptRoot

if (-not $env:JAVA_HOME -or -not (Test-Path "$env:JAVA_HOME\bin\java.exe")) {
    $jbr = Get-ChildItem 'C:\Program Files\Android' -Directory -ErrorAction SilentlyContinue |
        ForEach-Object { Join-Path $_.FullName 'jbr' } |
        Where-Object { Test-Path "$_\bin\java.exe" } |
        Select-Object -First 1
    if (-not $jbr) { throw 'Set JAVA_HOME to a JDK 17+ (Android Studio ships one in its jbr folder)' }
    $env:JAVA_HOME = $jbr
}

$sdk = if ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { "$env:LOCALAPPDATA\Android\Sdk" }
if (-not (Test-Path local.properties)) {
    "sdk.dir=$($sdk -replace '\\', '\\')" | Out-File -Encoding ascii local.properties
}

$py = '..\tools\venv\Scripts\python.exe'
if (-not (Test-Path $py)) {
    throw 'Create tools\venv first: python -m venv tools\venv; tools\venv\Scripts\python.exe -m pip install -r tools\requirements.txt'
}

$homeQuery = 'cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME'
$beforeHome = ((& $py -I ..\tools\tv.py $homeQuery | Select-Object -Last 1) -as [string]).Trim()
Write-Host "Home before install: $beforeHome"

.\gradlew.bat assembleRelease -q --console=plain
if ($LASTEXITCODE -ne 0) { throw 'Gradle build failed' }

$apk = 'app\build\outputs\apk\release\app-release.apk'
& $py -I ..\tools\b64push.py $apk /data/local/tmp/tvhome.apk
if ($LASTEXITCODE -ne 0) { throw 'APK upload failed' }

$out = & $py -I ..\tools\tv.py 'pm install -r /data/local/tmp/tvhome.apk; rm -f /data/local/tmp/tvhome.apk'
Write-Host $out
if ("$out" -notmatch 'Success') { throw 'pm install failed; no launcher settings were changed' }

$afterInstall = ((& $py -I ..\tools\tv.py $homeQuery | Select-Object -Last 1) -as [string]).Trim()
if ($beforeHome -and $beforeHome -ne 'android' -and $afterInstall -ne $beforeHome) {
    Write-Host "Installing another HOME app changed the default to '$afterInstall'; restoring '$beforeHome'."
    & $py -I ..\tools\tv.py "cmd package set-home-activity --user 0 $beforeHome" | Write-Host
    $restored = ((& $py -I ..\tools\tv.py $homeQuery | Select-Object -Last 1) -as [string]).Trim()
    if ($restored -ne $beforeHome) {
        throw "could not restore the previous Home; expected '$beforeHome', got '$restored'"
    }
}

$start = (& $py -I ..\tools\tv.py 'am start -W -n com.gathin.tvhome/.MainActivity') -join "`n"
Write-Host $start
if ($start -notmatch 'Status: ok' -or $start -match '(?m)^Error') {
    throw 'launcher installed but did not start'
}

$finalHome = ((& $py -I ..\tools\tv.py $homeQuery | Select-Object -Last 1) -as [string]).Trim()
Write-Host ""
Write-Host "Validation launcher is running."
Write-Host "Default Home remains: $finalHome"
Write-Host "Pressing Home should return to the original TV launcher."
