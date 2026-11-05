@echo off
setlocal EnableExtensions
title Disk Keep-Alive (all removable disks, read only)

REM ===========================================================================
REM  KeepAliveAll.bat
REM
REM  Keeps EVERY attached USB / removable disk from dropping off the bus.
REM  Re-scans on every cycle, so drives you plug in later are picked up
REM  automatically and drives you unplug are dropped without errors.
REM
REM  How it works: every N seconds it issues one 4 KB READ to each physical
REM  disk, with FILE_FLAG_NO_BUFFERING so the I/O actually reaches the
REM  hardware instead of being served out of the Windows file cache. The
REM  read offset rotates over a 256 MB window so the drive's own onboard
REM  cache cannot absorb it either.
REM
REM  IT NEVER WRITES. Handles are opened read-only; the only calls made are
REM  Seek and Read. Safe to run against a drive you are recovering data from,
REM  and safe to run while R-Studio or any other tool has the disk open.
REM
REM  USAGE
REM     KeepAliveAll.bat           every 20s, all USB / removable disks
REM     KeepAliveAll.bat 15        every 15s
REM     KeepAliveAll.bat 15 all    every 15s, EVERY physical disk incl. internal
REM
REM  Requires administrator rights (raw disk access). It will ask for them.
REM  Press Ctrl+C to stop.
REM ===========================================================================

set "SELF=%~f0"
set "KA_INTERVAL=20"
set "KA_SCOPE=removable"
if not "%~1"=="" set "KA_INTERVAL=%~1"
if /I "%~2"=="all" set "KA_SCOPE=all"

net session >nul 2>&1
if errorlevel 1 (
    echo Requesting administrator privileges...
    set "ARGS=%*"
    powershell -NoProfile -Command "if ($env:ARGS) { Start-Process -FilePath $env:SELF -ArgumentList $env:ARGS -Verb RunAs } else { Start-Process -FilePath $env:SELF -Verb RunAs }"
    exit /b
)

REM Marker is concatenated on purpose - see Fix-DiskSleep.bat for why.
powershell -NoProfile -ExecutionPolicy Bypass -Command "$m='#PS'+'BEGIN'+'#'; $t=(Get-Content -LiteralPath $env:SELF -Raw) -split $m,2; Invoke-Expression $t[1]"

echo.
echo Keep-alive has stopped.
pause
exit /b

#PSBEGIN#

$ErrorActionPreference = 'Stop'

$NOBUF = 0x20000000        # FILE_FLAG_NO_BUFFERING - bypass the Windows cache
$READSZ = 4096              # must be a multiple of the sector size
$SPANMB = 256               # offset rotation window, in MB

$interval = 20
if ($env:KA_INTERVAL) { $interval = [int]$env:KA_INTERVAL }
if ($interval -lt 2) { $interval = 2 }
if ($interval -gt 300) { $interval = 300 }
$allDisks = ($env:KA_SCOPE -eq 'all')

function Stamp($text, $color) {
    Write-Host ("[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $text) -ForegroundColor $color
}

function Get-TargetDisks {
    try { $d = @(Get-Disk -ErrorAction Stop) } catch { return @() }
    if ($allDisks) { return $d }
    return @($d | Where-Object { $_.BusType -eq 'USB' -or $_.BusType -eq 'SD' -or $_.BusType -eq '1394' })
}

function Open-RawRead($number) {
    # FileAccess::Read       -> read only, write access is never requested
    # FileShare::ReadWrite   -> other tools can hold the disk open at the same time
    New-Object System.IO.FileStream(
        "\\.\PhysicalDrive$number",
        [System.IO.FileMode]::Open,
        [System.IO.FileAccess]::Read,
        [System.IO.FileShare]::ReadWrite,
        $READSZ,
        [System.IO.FileOptions]$NOBUF)
}

Write-Host ''
Write-Host '  Disk Keep-Alive  --  READ ONLY, never writes' -ForegroundColor Cyan
Write-Host '  --------------------------------------------' -ForegroundColor DarkGray
Write-Host ("  Interval : {0} s" -f $interval)
Write-Host ("  Scope    : {0}" -f $(if ($allDisks) { 'ALL physical disks' } else { 'USB / SD / FireWire disks' }))
Write-Host ("  Rotation : {0} MB window, 1 MB steps" -f $SPANMB)
Write-Host '  New drives are picked up automatically. Ctrl+C to stop.' -ForegroundColor DarkGray
Write-Host ''

$buf = New-Object byte[] $READSZ
$open = @{}        # disk number -> @{ Stream; Slots; Label }
$tick = 0
$okCount = 0
$failCount = 0
$lastReport = 0
$started = Get-Date

try {
    while ($true) {
        $disks = Get-TargetDisks
        $present = @{}
        foreach ($d in $disks) { $present[[int]$d.Number] = $d }

        # --- drop disks that went away ---
        foreach ($n in @($open.Keys)) {
            if (-not $present.ContainsKey($n)) {
                try { $open[$n].Stream.Dispose() } catch { }
                Stamp ("-- disk {0} gone ({1})" -f $n, $open[$n].Label) 'Yellow'
                $open.Remove($n)
            }
        }

        # --- attach disks that appeared ---
        foreach ($n in $present.Keys) {
            if ($open.ContainsKey($n)) { continue }
            $d = $present[$n]
            try {
                $st = Open-RawRead $n
                $span = [math]::Min([int64]$SPANMB * 1MB, [int64]$d.Size - 1MB)
                $slots = [math]::Max(1, [int]($span / 1MB))
                $label = ("{0} ({1} GB, {2})" -f $d.FriendlyName, [math]::Round($d.Size / 1GB, 2), $d.BusType)
                $open[$n] = @{ Stream = $st; Slots = $slots; Label = $label }
                Stamp ("++ disk {0} attached: {1}" -f $n, $label) 'Green'
            }
            catch {
                Stamp ("!! disk {0} cannot be opened: {1}" -f $n, $_.Exception.Message) 'Red'
            }
        }

        if ($open.Count -eq 0) {
            if ($tick % 10 -eq 0) { Stamp 'no target disk attached - waiting...' 'Yellow' }
        }

        # --- one tiny read per disk ---
        foreach ($n in @($open.Keys)) {
            $e = $open[$n]
            try {
                # 1 MB aligned offsets satisfy the NO_BUFFERING alignment rule
                $offset = [int64]($tick % $e.Slots) * 1MB
                [void]$e.Stream.Seek($offset, [System.IO.SeekOrigin]::Begin)
                [void]$e.Stream.Read($buf, 0, $READSZ)
                $okCount++
            }
            catch {
                $failCount++
                try { $e.Stream.Dispose() } catch { }
                $open.Remove($n)
                Stamp ("!! disk {0} read failed, will retry: {1}" -f $n, $_.Exception.Message) 'Red'
            }
        }

        # --- heartbeat every ~5 minutes ---
        $elapsed = (Get-Date) - $started
        if ($elapsed.TotalSeconds - $lastReport -ge 300) {
            $lastReport = $elapsed.TotalSeconds
            Stamp ("alive - {0} disk(s), ok {1} / failed {2}, running {3:hh\:mm\:ss}" -f `
                    $open.Count, $okCount, $failCount, $elapsed) 'DarkGray'
        }

        $tick++
        Start-Sleep -Seconds $interval
    }
}
finally {
    foreach ($n in @($open.Keys)) { try { $open[$n].Stream.Dispose() } catch { } }
    Write-Host ''
    Stamp ("stopped - ok {0} / failed {1}" -f $okCount, $failCount) 'Cyan'
}
