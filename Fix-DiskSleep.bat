@echo off
setlocal EnableExtensions
title Fix Disk Sleep / USB Auto-Disconnect

REM ===========================================================================
REM  Fix-DiskSleep.bat
REM
REM  Stops Windows from spinning down / powering off disks and USB ports,
REM  which is what makes external drives drop off the bus while idle.
REM
REM  It changes THREE things, for EVERY power plan on the machine (not just
REM  the active one) and for both AC and battery:
REM
REM    1. "Turn off hard disk after"   -> Never
REM    2. "USB selective suspend"      -> Disabled
REM    3. Per-device "Allow the computer to turn off this device to save
REM       power" -> unchecked, for every USB / USB storage / disk device
REM       currently attached.
REM
REM  Items 1 and 2 are global and apply to ANY drive you plug in later.
REM  Item 3 is stored per device instance, so re-run this after plugging in
REM  a drive you have never used on this machine before.
REM
REM  Requires administrator rights. It will ask for them.
REM ===========================================================================

set "SELF=%~f0"

net session >nul 2>&1
if errorlevel 1 (
    echo Requesting administrator privileges...
    powershell -NoProfile -Command "Start-Process -FilePath $env:SELF -Verb RunAs"
    exit /b
)

REM The marker below is concatenated on purpose: if the literal string also
REM appeared on this line, -split would cut here instead of at the real marker.
powershell -NoProfile -ExecutionPolicy Bypass -Command "$m='#PS'+'BEGIN'+'#'; $t=(Get-Content -LiteralPath $env:SELF -Raw) -split $m,2; Invoke-Expression $t[1]"

echo.
pause
exit /b

#PSBEGIN#

$ErrorActionPreference = 'Continue'

# GUIDs are stable across Windows versions and locales, so use them rather
# than the friendly aliases (aliases are not present on every SKU).
$SUB_DISK = '0012ee47-9041-4b5d-9b77-535fba8b1442'   # Hard disk
$DISKIDLE = '6738e2c4-e8a5-4a42-b16a-e040e769756e'   # Turn off hard disk after
$SUB_USB = '2a737441-1930-4402-8d77-b2bebba308a3'   # USB settings
$USBIDLE = '48e6b7a6-50f5-4782-a5d4-53bb8f07e226'   # USB selective suspend

Write-Host ''
Write-Host '  Fix Disk Sleep / USB Auto-Disconnect' -ForegroundColor Cyan
Write-Host '  ------------------------------------' -ForegroundColor DarkGray
Write-Host ''

# ---------------------------------------------------------- power schemes
Write-Host '[1/3] Power plans: "Turn off hard disk after" -> Never' -ForegroundColor Cyan
Write-Host '[2/3] Power plans: "USB selective suspend"    -> Disabled' -ForegroundColor Cyan

$schemes = @()
foreach ($line in (powercfg /list)) {
    $m = [regex]::Match($line, '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})')
    if ($m.Success) {
        $name = ''
        $n = [regex]::Match($line, '\(([^)]*)\)')
        if ($n.Success) { $name = $n.Groups[1].Value }
        $schemes += [pscustomobject]@{ Guid = $m.Groups[1].Value; Name = $name }
    }
}
Write-Host ("      found {0} power plan(s)" -f $schemes.Count)

foreach ($s in $schemes) {
    powercfg /setacvalueindex $s.Guid $SUB_DISK $DISKIDLE 0  2>$null
    powercfg /setdcvalueindex $s.Guid $SUB_DISK $DISKIDLE 0  2>$null
    powercfg /setacvalueindex $s.Guid $SUB_USB  $USBIDLE  0  2>$null
    powercfg /setdcvalueindex $s.Guid $SUB_USB  $USBIDLE  0  2>$null
    Write-Host ("      done: {0}  {1}" -f $s.Guid, $s.Name) -ForegroundColor DarkGray
}
# re-activating the current plan is what makes the new values take effect now
powercfg /setactive SCHEME_CURRENT 2>$null

# ---------------------------------------------------------- per device
Write-Host ''
Write-Host '[3/3] Devices: uncheck "Allow the computer to turn off this device"' -ForegroundColor Cyan

$changed = 0; $already = 0; $failed = 0
try {
    $items = @(Get-CimInstance -Namespace 'root\WMI' -ClassName 'MSPower_DeviceEnable' -ErrorAction Stop)
}
catch {
    $items = @()
    Write-Host '      WMI class MSPower_DeviceEnable not available on this system' -ForegroundColor Yellow
}

foreach ($i in $items) {
    # Only touch USB / USB storage / disk devices. Leave NICs, mice etc. alone.
    if ($i.InstanceName -notmatch '^(USB|USBSTOR|SCSI|SBP2)\\') { continue }
    if (-not $i.Enable) { $already++; continue }
    try {
        Set-CimInstance -InputObject $i -Property @{ Enable = $false } -ErrorAction Stop
        $changed++
    }
    catch { $failed++ }
}
Write-Host ("      changed {0}, already off {1}, failed {2}" -f $changed, $already, $failed)

# ---------------------------------------------------------- verify
Write-Host ''
Write-Host '===== Verify =====' -ForegroundColor Cyan
$q = powercfg /query SCHEME_CURRENT $SUB_DISK $DISKIDLE
foreach ($line in $q) {
    if ($line -match '0x[0-9a-fA-F]{8}') { Write-Host ("  Disk idle : {0}" -f $line.Trim()) }
}
$q2 = powercfg /query SCHEME_CURRENT $SUB_USB $USBIDLE
foreach ($line in $q2) {
    if ($line -match '0x[0-9a-fA-F]{8}') { Write-Host ("  USB susp. : {0}" -f $line.Trim()) }
}
Write-Host ''
Write-Host '  0x00000000 on every line above means it is fixed.' -ForegroundColor Green
Write-Host ''
Write-Host '  Note: steps 1 and 2 are global and cover any drive you plug in' -ForegroundColor DarkGray
Write-Host '  later. Step 3 is per device, so run this again after connecting' -ForegroundColor DarkGray
Write-Host '  a drive this PC has never seen before.' -ForegroundColor DarkGray
