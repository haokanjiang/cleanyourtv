# Enable/disable the experimental MFTR0 Home override without changing the Android default HOME.
# Usage:
#   powershell -ExecutionPolicy Bypass -File launcher\test-home-override.ps1 -TvHost 192.168.1.50
#   powershell -ExecutionPolicy Bypass -File launcher\test-home-override.ps1 -TvHost 192.168.1.50 -Disable
param(
    [string]$TvHost = $env:TV_HOST,
    [switch]$Disable
)

$ErrorActionPreference = 'Stop'
$OutputEncoding = New-Object System.Text.UTF8Encoding $false
if (-not $TvHost) { throw 'pass -TvHost <tv ip> or set $env:TV_HOST' }
$env:TV_HOST = $TvHost
Set-Location $PSScriptRoot

$py = '..\tools\venv\Scripts\python.exe'
if (-not (Test-Path $py)) {
    throw 'Create tools\venv first: python -m venv tools\venv; tools\venv\Scripts\python.exe -m pip install -r tools\requirements.txt'
}

function Tv([string]$Command) {
    $out = & $py -I ..\tools\tv.py $Command
    if ($LASTEXITCODE -ne 0) { throw "TV command failed: $Command" }
    return (($out -join "`n").Trim())
}

$model = Tv 'getprop ro.product.model'
$device = Tv 'getprop ro.product.device'
if ($model -ne 'MiTV-MFTR0' -or $device -ne 'freeguy') {
    throw "This experiment is gated to MiTV-MFTR0/freeguy; got '$model/$device'"
}

$pkg = Tv 'pm path com.gathin.tvhome'
if ($pkg -notmatch '^package:') {
    throw 'CleanYourTV is not installed. Run launcher\build-and-test.ps1 first.'
}

$service = 'com.gathin.tvhome/com.gathin.tvhome.HomeKeyService'
$current = Tv 'settings get secure enabled_accessibility_services'
if ($current -eq 'null') { $current = '' }

$items = @()
if ($current) {
    $items = @($current -split ':' | Where-Object { $_ -and $_ -ne $service })
}

if ($Disable) {
    $next = $items -join ':'
    if ($next) {
        Tv "settings put secure enabled_accessibility_services $next" | Out-Null
        Tv 'settings put secure accessibility_enabled 1' | Out-Null
    } else {
        Tv 'settings delete secure enabled_accessibility_services' | Out-Null
        Tv 'settings put secure accessibility_enabled 0' | Out-Null
    }
    Write-Host 'MFTR0 Home override disabled.'
    Write-Host 'The Android default Home was not changed.'
    exit 0
}

$nextItems = @($items + $service)
$next = $nextItems -join ':'
Tv "settings put secure enabled_accessibility_services $next" | Out-Null
Tv 'settings put secure accessibility_enabled 1' | Out-Null

Tv 'am force-stop com.gathin.tvhome' | Out-Null
Start-Sleep -Milliseconds 400
Tv 'am start -W -a android.intent.action.MAIN -c android.intent.category.HOME -n com.gathin.tvhome/.MainActivity' | Write-Host
Start-Sleep -Seconds 1

$enabled = Tv 'settings get secure enabled_accessibility_services'
if ($enabled -notmatch [regex]::Escape($service)) {
    throw 'HomeKeyService is not listed in enabled_accessibility_services.'
}

Write-Host ''
Write-Host 'MFTR0 Home override enabled for testing.'
Write-Host 'Do NOT disable com.mitv.tvhome or com.xiaomi.mitv.settings.'
Write-Host ''
Write-Host 'Now press the physical Home button from another app 3 times.'
Write-Host 'Expected: Xiaomi/FallbackHome may flash briefly, then CleanYourTV returns.'
Write-Host ''
Write-Host 'Rollback:'
Write-Host "powershell -ExecutionPolicy Bypass -File launcher\test-home-override.ps1 -TvHost $TvHost -Disable"
Write-Host ''
Write-Host 'If Home does not redirect, capture dumpsys accessibility and logcat before changing anything else.'
