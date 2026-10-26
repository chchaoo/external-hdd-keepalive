@echo off
setlocal EnableExtensions
title Backup Power Settings - PLANS ONLY

REM ===========================================================================
REM  Backup-PowerSettings-PlansOnly.bat   -- power plans only
REM
REM  Same as Backup-PowerSettings.bat but records ONLY the power plan half:
REM
REM      "Turn off hard disk after"   (AC and DC, every plan)
REM      "USB selective suspend"      (AC and DC, every plan)
REM      which plan is currently active
REM
REM  It does NOT record the per-device checkbox
REM      "Allow the computer to turn off this device to save power"
REM  because that one is not part of any power plan - Windows keeps it in
REM  each device's own registry key.
REM
REM  CONSEQUENCE: Fix-DiskSleep.bat clears that checkbox, and restoring from
REM  a plans-only backup will NOT put it back. If you want a complete undo,
REM  use Backup-PowerSettings.bat (the full one) instead.
REM
REM  Reason you might still want this one: the file stays free of your
REM  hardware VID/PID list, and it applies cleanly to any machine.
REM
REM  Output lands next to this .bat as
REM      PowerSettings-Backup-PlansOnly-YYYYMMDD-HHMMSS.txt
REM
REM  Needs administrator rights (powercfg writes nothing here, but the
REM  wrapper is kept identical to the other scripts for consistency).
REM ===========================================================================

set "SELF=%~f0"
set "KA_PLANSONLY=1"

net session >nul 2>&1
if errorlevel 1 (
    echo Requesting administrator privileges...
    powershell -NoProfile -Command "Start-Process -FilePath $env:SELF -Verb RunAs"
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
$RXGUID   = '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'

$plansOnly = ($env:KA_PLANSONLY -eq '1')

function Get-Values($scheme, $sub, $setting) {
    # hex values always appear as Minimum / Maximum / increment / AC / DC,
    # so take the last two - this does not depend on the display language
    $out = (powercfg /query $scheme $sub $setting 2>$null) -join "`n"
    $hex = @([regex]::Matches($out, '0x[0-9a-fA-F]{8}') | ForEach-Object { $_.Value })
    if ($hex.Count -lt 2) { return @($null, $null) }
    return @([Convert]::ToInt64($hex[-2].Substring(2), 16), [Convert]::ToInt64($hex[-1].Substring(2), 16))
}

$dir = Split-Path -Parent $env:SELF
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$tag = ''
$kind = 'full (power plans + devices)'
if ($plansOnly) { $tag = 'PlansOnly-'; $kind = 'plans-only (no device settings)' }
$file = Join-Path $dir ("PowerSettings-Backup-{0}{1}.txt" -f $tag, $stamp)

Write-Host ''
Write-Host ('  Backup power settings - {0}' -f $kind) -ForegroundColor Cyan
Write-Host '  ------------------------------------------------' -ForegroundColor DarkGray
Write-Host ''

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add('# PowerSettingsBackup v1')
$lines.Add('# Do not edit by hand unless you know what you are doing.')
$lines.Add(('# Type     : {0}' -f $(if ($plansOnly) { 'plans-only' } else { 'full' })))
$lines.Add(('# Saved    : {0}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')))
$lines.Add(('# Computer : {0}' -f $env:COMPUTERNAME))
$lines.Add('#')
$lines.Add('# DISKIDLE / USBIDLE lines are:  GUID | AC value | DC value')
$lines.Add('#   DISKIDLE values are seconds, 0 means Never')
$lines.Add('#   USBIDLE  values are 0 = Disabled, 1 = Enabled')
$lines.Add('# DEVICE lines are:  InstanceName | True(may power off) or False')
$lines.Add('#   These are per device, not per power plan.')
$lines.Add('')

# ---- which plan is active ----
$active = ''
$m = [regex]::Match(((powercfg /getactivescheme) -join ' '), $RXGUID)
if ($m.Success) { $active = $m.Value }
$lines.Add(('ACTIVE=' + $active))

# ---- part A: every power plan ----
$plans = @()
foreach ($line in (powercfg /list)) {
    $g = [regex]::Match($line, $RXGUID)
    if (-not $g.Success) { continue }
    $name = ''
    $n = [regex]::Match($line, '\(([^)]*)\)')
    if ($n.Success) { $name = $n.Groups[1].Value }
    $plans += [pscustomobject]@{ Guid = $g.Value; Name = $name }
}

Write-Host ("  A) Power plans : {0}" -f $plans.Count) -ForegroundColor Cyan
foreach ($p in $plans) {
    $lines.Add(('PLAN={0}|{1}' -f $p.Guid, $p.Name))
    $d = Get-Values $p.Guid $SUB_DISK $DISKIDLE
    $u = Get-Values $p.Guid $SUB_USB  $USBIDLE
    if ($null -ne $d[0]) { $lines.Add(('DISKIDLE={0}|{1}|{2}' -f $p.Guid, $d[0], $d[1])) }
    if ($null -ne $u[0]) { $lines.Add(('USBIDLE={0}|{1}|{2}'  -f $p.Guid, $u[0], $u[1])) }
    $mark = ''
    if ($p.Guid -eq $active) { $mark = '  (active)' }
    Write-Host ("       {0,-26} disk AC={1} DC={2}   usb AC={3} DC={4}{5}" -f `
            $p.Name, $d[0], $d[1], $u[0], $u[1], $mark) -ForegroundColor DarkGray
}

# ---- part B: per device ----
$devCount = 0
if ($plansOnly) {
    Write-Host '  B) Devices     : skipped (plans-only backup)' -ForegroundColor Yellow
    Write-Host '       Restoring from this file will NOT put the device' -ForegroundColor DarkGray
    Write-Host '       checkboxes back. Use the full backup for that.' -ForegroundColor DarkGray
}
else {
    try {
        $items = @(Get-CimInstance -Namespace 'root\WMI' -ClassName 'MSPower_DeviceEnable' -ErrorAction Stop)
    }
    catch {
        $items = @()
        Write-Host '  B) Devices     : WMI not readable - device states NOT saved' -ForegroundColor Yellow
    }
    foreach ($i in $items) {
        if ($i.InstanceName -notmatch '^(USB|USBSTOR|SCSI|SBP2)\\') { continue }
        $lines.Add(('DEVICE={0}|{1}' -f $i.InstanceName, $i.Enable))
        $devCount++
    }
    if ($items.Count -gt 0) { Write-Host ("  B) Devices     : {0}" -f $devCount) -ForegroundColor Cyan }
}

# ---- write ----
try {
    [System.IO.File]::WriteAllLines($file, $lines, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host ''
    Write-Host ("  Saved to: {0}" -f $file) -ForegroundColor Green
    Write-Host ''
    Write-Host '  Restore-PowerSettings.bat reads this back. By default it picks' -ForegroundColor DarkGray
    Write-Host '  the newest PowerSettings-Backup-*.txt in this folder.' -ForegroundColor DarkGray
}
catch {
    Write-Host ''
    Write-Host ("  FAILED to write {0}" -f $file) -ForegroundColor Red
    Write-Host ("  {0}" -f $_.Exception.Message) -ForegroundColor Red
}
