@echo off
setlocal EnableExtensions
title Restore Disk / USB Power Settings

REM ===========================================================================
REM  Restore-PowerSettings.bat
REM
REM  Puts the machine back the way Backup-PowerSettings.bat recorded it -
REM  i.e. undoes Fix-DiskSleep.bat.
REM
REM  USAGE
REM     Restore-PowerSettings.bat
REM         uses the NEWEST PowerSettings-Backup-*.txt in this folder
REM
REM     Restore-PowerSettings.bat "C:\somewhere\PowerSettings-Backup-....txt"
REM         uses that file
REM
REM     Restore-PowerSettings.bat /list
REM         just lists the backup files it can see, changes nothing
REM
REM  It restores, for every plan recorded in the file:
REM      * "Turn off hard disk after"  (AC and DC)
REM      * "USB selective suspend"     (AC and DC)
REM      * which plan is active
REM      * per-device "Allow the computer to turn off this device"
REM
REM  Plans or devices in the file that no longer exist are skipped and
REM  reported - they do not stop the rest of the restore.
REM
REM  Needs administrator rights. It will ask for them.
REM ===========================================================================

set "SELF=%~f0"
set "KA_FILE=%~1"

net session >nul 2>&1
if errorlevel 1 (
    echo Requesting administrator privileges...
    set "ARGS=%*"
    powershell -NoProfile -Command "if ($env:ARGS) { Start-Process -FilePath $env:SELF -ArgumentList $env:ARGS -Verb RunAs } else { Start-Process -FilePath $env:SELF -Verb RunAs }"
    exit /b
)

REM Marker is concatenated on purpose - see the other scripts for why.
powershell -NoProfile -ExecutionPolicy Bypass -Command "$m='#PS'+'BEGIN'+'#'; $t=(Get-Content -LiteralPath $env:SELF -Raw) -split $m,2; Invoke-Expression $t[1]"

echo.
pause
exit /b

#PSBEGIN#

$ErrorActionPreference = 'Continue'

$SUB_DISK = '0012ee47-9041-4b5d-9b77-535fba8b1442'
$DISKIDLE = '6738e2c4-e8a5-4a42-b16a-e040e769756e'
$SUB_USB  = '2a737441-1930-4402-8d77-b2bebba308a3'
$USBIDLE  = '48e6b7a6-50f5-4782-a5d4-53bb8f07e226'

$dir = Split-Path -Parent $env:SELF
$arg = $env:KA_FILE

Write-Host ''
Write-Host '  Restore disk / USB power settings' -ForegroundColor Cyan
Write-Host '  ---------------------------------' -ForegroundColor DarkGray
Write-Host ''

$backups = @(Get-ChildItem -LiteralPath $dir -Filter 'PowerSettings-Backup-*.txt' -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending)

if ($arg -eq '/list' -or $arg -eq '-list') {
    if ($backups.Count -eq 0) { Write-Host '  No backup files in this folder.' -ForegroundColor Yellow; return }
    Write-Host ("  {0} backup file(s), newest first:" -f $backups.Count)
    foreach ($b in $backups) {
        Write-Host ("    {0:yyyy-MM-dd HH:mm:ss}   {1}" -f $b.LastWriteTime, $b.Name)
    }
    return
}

# ---- pick the file ----
$file = ''
if ($arg -and $arg -ne '') {
    if (Test-Path -LiteralPath $arg -PathType Leaf) { $file = (Get-Item -LiteralPath $arg).FullName }
    else { Write-Host ("  File not found: {0}" -f $arg) -ForegroundColor Red; return }
}
else {
    if ($backups.Count -eq 0) {
        Write-Host '  No PowerSettings-Backup-*.txt found in this folder.' -ForegroundColor Red
        Write-Host '  Run Backup-PowerSettings.bat first, or pass a file path.' -ForegroundColor Yellow
        return
    }
    $file = $backups[0].FullName
}

Write-Host ("  Using: {0}" -f $file) -ForegroundColor Cyan
$raw = @(Get-Content -LiteralPath $file -Encoding UTF8 -ErrorAction SilentlyContinue)
if ($raw.Count -eq 0) { Write-Host '  File is empty.' -ForegroundColor Red; return }
if ($raw[0] -notmatch 'PowerSettingsBackup') {
    Write-Host '  This does not look like a PowerSettingsBackup file.' -ForegroundColor Red
    return
}
foreach ($l in $raw) { if ($l -match '^#\s*(Type|Saved|Computer)') { Write-Host ("  {0}" -f $l.TrimStart('#', ' ')) -ForegroundColor DarkGray } }

# A plans-only backup has no DEVICE lines, so say so up front rather than
# letting the user assume the device checkboxes were put back too.
$hasDevice = @($raw | Where-Object { $_ -match '^DEVICE=' }).Count
if ($hasDevice -eq 0) {
    Write-Host '  This is a PLANS-ONLY backup - it has no device records.' -ForegroundColor Yellow
    Write-Host '  Power plan values will be restored; the per-device checkbox' -ForegroundColor Yellow
    Write-Host '  "Allow the computer to turn off this device" will NOT be.' -ForegroundColor Yellow
}
else {
    Write-Host ("  Full backup - {0} device record(s) to restore as well." -f $hasDevice) -ForegroundColor DarkGray
}
Write-Host ''

# ---- existing plans, so we can skip ones that are gone ----
$rxGuid = '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'
$existing = @{}
foreach ($line in (powercfg /list)) {
    $g = [regex]::Match($line, $rxGuid)
    if ($g.Success) { $existing[$g.Value.ToLower()] = $true }
}

$okPlan = 0; $skipPlan = 0
$activeWanted = ''

foreach ($l in $raw) {
    if ($l -match '^ACTIVE=(.+)$') { $activeWanted = $matches[1].Trim(); continue }

    if ($l -match '^DISKIDLE=([^|]+)\|([^|]+)\|(.+)$') {
        $g = $matches[1].Trim(); $ac = $matches[2].Trim(); $dc = $matches[3].Trim()
        if (-not $existing.ContainsKey($g.ToLower())) { $skipPlan++; continue }
        powercfg /setacvalueindex $g $SUB_DISK $DISKIDLE $ac 2>$null
        powercfg /setdcvalueindex $g $SUB_DISK $DISKIDLE $dc 2>$null
        Write-Host ("    disk idle  {0}  AC={1}s DC={2}s" -f $g, $ac, $dc) -ForegroundColor DarkGray
        $okPlan++
        continue
    }

    if ($l -match '^USBIDLE=([^|]+)\|([^|]+)\|(.+)$') {
        $g = $matches[1].Trim(); $ac = $matches[2].Trim(); $dc = $matches[3].Trim()
        if (-not $existing.ContainsKey($g.ToLower())) { continue }
        powercfg /setacvalueindex $g $SUB_USB $USBIDLE $ac 2>$null
        powercfg /setdcvalueindex $g $SUB_USB $USBIDLE $dc 2>$null
        Write-Host ("    usb susp.  {0}  AC={1} DC={2}" -f $g, $ac, $dc) -ForegroundColor DarkGray
        continue
    }
}

Write-Host ''
Write-Host ("  Power plan settings restored: {0} plan(s), skipped {1} (plan no longer exists)" -f $okPlan, $skipPlan)

# ---- devices ----
$want = @{}
foreach ($l in $raw) {
    if ($l -match '^DEVICE=(.+)\|(True|False)\s*$') { $want[$matches[1]] = ($matches[2] -eq 'True') }
}

$dOk = 0; $dSame = 0; $dGone = 0; $dFail = 0
if ($want.Count -gt 0) {
    try { $items = @(Get-CimInstance -Namespace 'root\WMI' -ClassName 'MSPower_DeviceEnable' -ErrorAction Stop) }
    catch { $items = @(); Write-Host '  WMI class MSPower_DeviceEnable not available' -ForegroundColor Yellow }

    $present = @{}
    foreach ($i in $items) { $present[$i.InstanceName] = $i }

    foreach ($k in $want.Keys) {
        if (-not $present.ContainsKey($k)) { $dGone++; continue }
        $inst = $present[$k]
        if ($inst.Enable -eq $want[$k]) { $dSame++; continue }
        try { Set-CimInstance -InputObject $inst -Property @{ Enable = $want[$k] } -ErrorAction Stop; $dOk++ }
        catch { $dFail++ }
    }
    Write-Host ("  Device settings restored    : {0} changed, {1} already correct, {2} not attached, {3} failed" -f $dOk, $dSame, $dGone, $dFail)
}
else {
    Write-Host '  Device settings             : none in this backup (plans-only)' -ForegroundColor DarkGray
}

# ---- active plan last, which also applies the values ----
if ($activeWanted -and $existing.ContainsKey($activeWanted.ToLower())) {
    powercfg /setactive $activeWanted 2>$null
    Write-Host ("  Active plan restored        : {0}" -f $activeWanted)
}
else {
    powercfg /setactive SCHEME_CURRENT 2>$null
}

Write-Host ''
Write-Host '  Done. Run Show-PowerSettings.bat to confirm the values are back.' -ForegroundColor Green
