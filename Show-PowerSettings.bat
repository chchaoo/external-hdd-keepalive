@echo off
setlocal EnableExtensions
title Disk / USB Power Settings - All Plans

REM ===========================================================================
REM  Show-PowerSettings.bat
REM
REM  Shows, for EVERY power plan on this machine, the two settings that make
REM  external drives disconnect while idle:
REM
REM      1. "Turn off hard disk after"
REM      2. "USB selective suspend"
REM
REM  Control Panel hides both on many machines (USB selective suspend is not
REM  shown at all on most OEM builds), so powercfg is the only way to see them.
REM
REM  Output is human readable - no hex. Both settings must be OFF / Never for
REM  an external drive to stay connected.
REM
REM  No administrator rights needed - this only reads.
REM
REM  Portability notes:
REM    * Settings are addressed by GUID, not by the SUB_DISK / DISKIDLE
REM      aliases. Those aliases do not exist on every Windows SKU.
REM    * Values are read as "the last two hex numbers in the query output"
REM      (the order is always Minimum / Maximum / increment / AC / DC), so
REM      parsing does not depend on the display language.
REM ===========================================================================

set "SELF=%~f0"

REM Marker is concatenated on purpose: if the literal string appeared here
REM too, -split would cut at THIS line instead of at the real marker below.
powershell -NoProfile -ExecutionPolicy Bypass -Command "$m='#PS'+'BEGIN'+'#'; $t=(Get-Content -LiteralPath $env:SELF -Raw) -split $m,2; Invoke-Expression $t[1]"

echo.
pause
exit /b

#PSBEGIN#

$ErrorActionPreference = 'Continue'

$SUB_DISK = '0012ee47-9041-4b5d-9b77-535fba8b1442'   # Hard disk
$DISKIDLE = '6738e2c4-e8a5-4a42-b16a-e040e769756e'   # Turn off hard disk after
$SUB_USB  = '2a737441-1930-4402-8d77-b2bebba308a3'   # USB settings
$USBIDLE  = '48e6b7a6-50f5-4782-a5d4-53bb8f07e226'   # USB selective suspend
$RXGUID   = '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'

function Get-Values($scheme, $sub, $setting) {
    $out = (powercfg /query $scheme $sub $setting 2>$null) -join "`n"
    $hex = @([regex]::Matches($out, '0x[0-9a-fA-F]{8}') | ForEach-Object { $_.Value })
    if ($hex.Count -lt 2) { return @($null, $null) }
    $ac = [Convert]::ToInt64($hex[-2].Substring(2), 16)
    $dc = [Convert]::ToInt64($hex[-1].Substring(2), 16)
    return @($ac, $dc)
}

function Format-Idle($sec) {
    if ($null -eq $sec) { return 'not available' }
    if ($sec -eq 0) { return 'Never (disabled)' }
    if ($sec -lt 60) { return ("{0} seconds" -f $sec) }
    if ($sec % 3600 -eq 0) { return ("{0} hours" -f ($sec / 3600)) }
    if ($sec % 60 -eq 0) { return ("{0} minutes" -f ($sec / 60)) }
    return ("{0} seconds ({1} min {2} sec)" -f $sec, [math]::Floor($sec / 60), ($sec % 60))
}

function Format-Suspend($v) {
    if ($null -eq $v) { return 'not available' }
    if ($v -eq 0) { return 'Disabled' }
    if ($v -eq 1) { return 'Enabled' }
    return ("Unknown value {0}" -f $v)
}

function Show-Row($label, $acText, $dcText, $acBad, $dcBad) {
    $acTag = '[OK]'; $acCol = 'Green'
    if ($acBad) { $acTag = '[WILL DROP DRIVES]'; $acCol = 'Red' }
    $dcTag = '[OK]'; $dcCol = 'Green'
    if ($dcBad) { $dcTag = '[WILL DROP DRIVES]'; $dcCol = 'Red' }
    Write-Host ("    {0,-26} plugged in : {1,-22} " -f $label, $acText) -NoNewline
    Write-Host $acTag -ForegroundColor $acCol
    Write-Host ("    {0,-26} on battery : {1,-22} " -f '', $dcText) -NoNewline
    Write-Host $dcTag -ForegroundColor $dcCol
}

# ---------------------------------------------------------------- collect
$active = ''
$m = [regex]::Match(((powercfg /getactivescheme) -join ' '), $RXGUID)
if ($m.Success) { $active = $m.Value }

$plans = @()
foreach ($line in (powercfg /list)) {
    $g = [regex]::Match($line, $RXGUID)
    if (-not $g.Success) { continue }
    $name = ''
    $n = [regex]::Match($line, '\(([^)]*)\)')
    if ($n.Success) { $name = $n.Groups[1].Value }
    $plans += [pscustomobject]@{ Guid = $g.Value; Name = $name }
}

Write-Host ''
Write-Host '  Disk / USB power settings - all power plans' -ForegroundColor Cyan
Write-Host '  ===========================================' -ForegroundColor DarkGray
Write-Host ("  Computer : {0}" -f $env:COMPUTERNAME)
Write-Host ("  Plans    : {0}" -f $plans.Count)
Write-Host ''

$goodPlans = 0
foreach ($p in $plans) {
    $tag = ''
    $col = 'Gray'
    if ($p.Guid -eq $active) { $tag = '   <<< CURRENTLY ACTIVE'; $col = 'Cyan' }
    Write-Host ("  Plan: {0}{1}" -f $p.Name, $tag) -ForegroundColor $col
    Write-Host ("        {0}" -f $p.Guid) -ForegroundColor DarkGray

    $d = Get-Values $p.Guid $SUB_DISK $DISKIDLE
    $u = Get-Values $p.Guid $SUB_USB  $USBIDLE

    $dAcBad = ($null -ne $d[0] -and $d[0] -ne 0)
    $dDcBad = ($null -ne $d[1] -and $d[1] -ne 0)
    $uAcBad = ($null -ne $u[0] -and $u[0] -ne 0)
    $uDcBad = ($null -ne $u[1] -and $u[1] -ne 0)

    Show-Row 'Turn off hard disk after' (Format-Idle $d[0]) (Format-Idle $d[1]) $dAcBad $dDcBad
    Show-Row 'USB selective suspend'    (Format-Suspend $u[0]) (Format-Suspend $u[1]) $uAcBad $uDcBad

    if (-not ($dAcBad -or $dDcBad -or $uAcBad -or $uDcBad)) { $goodPlans++ }
    Write-Host ''
}

# ---------------------------------------------------------------- summary
Write-Host '  -------------------------------------------' -ForegroundColor DarkGray
if ($goodPlans -eq $plans.Count) {
    Write-Host ("  All {0} plan(s) are configured correctly." -f $plans.Count) -ForegroundColor Green
    Write-Host '  External drives will not be powered down while idle.' -ForegroundColor Green
}
else {
    Write-Host ("  {0} of {1} plan(s) still power drives down." -f ($plans.Count - $goodPlans), $plans.Count) -ForegroundColor Yellow
    Write-Host '  Run Fix-DiskSleep.bat (as administrator) to correct every plan.' -ForegroundColor Yellow
}
Write-Host ''
Write-Host '  What the values mean:' -ForegroundColor DarkGray
Write-Host '    Turn off hard disk after = Never (disabled)  -> good. Any other' -ForegroundColor DarkGray
Write-Host '      value is how long Windows waits before spinning the disk down.' -ForegroundColor DarkGray
Write-Host '    USB selective suspend = Disabled -> good. Enabled lets Windows' -ForegroundColor DarkGray
Write-Host '      cut power to idle USB ports, which disconnects the drive.' -ForegroundColor DarkGray
Write-Host '    Both must be correct for plugged in AND on battery.' -ForegroundColor DarkGray
