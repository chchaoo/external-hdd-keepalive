<div align="center">

<img src="docs/images/logo.svg" width="96" height="96" alt="">

# External HDD Keep-Alive

**External HDD keeps disconnecting from your laptop? Check power settings, then keep it awake.**

Six Windows batch scripts to back up, inspect, fix, restore and keep drives active.

[![Release](https://img.shields.io/github/v/release/chchaoo/external-hdd-keepalive?color=2f81f7)](https://github.com/chchaoo/external-hdd-keepalive/releases/latest)
[![Windows](https://img.shields.io/badge/platform-Windows-0078d6)](#before-you-start)
[![License](https://img.shields.io/badge/license-MIT-2ea44f)](LICENSE)

**English** · [简体中文](README.zh-CN.md)

### [⬇ Download the complete toolkit](https://github.com/chchaoo/external-hdd-keepalive/releases/latest/download/external-hdd-keepalive.zip)

</div>

---

## Who this is for

**Some laptops repeatedly disconnect an external mechanical hard drive (HDD), or lose it shortly after it becomes idle, even after the usual power-plan changes.** This toolkit also addresses device-level power settings and offers periodic reads to keep drives active.

Disconnects can also come from cables, power delivery, USB ports, enclosures or the drive itself. These tools target power-saving / idle behavior; they cannot guarantee a fix for every cause.

## Before you start

- Requires Windows with built-in Windows PowerShell, `powercfg`, and Storage / CIM support. Windows 10 / 11 is recommended. Some drivers do not expose device power settings.
- Download and **extract the complete ZIP** into a writable folder. Do not run scripts inside the ZIP.
- Connect the affected drive. All scripts except the viewer request administrator rights.
- Fix changes **every power plan**, for AC and battery, plus accessible matching device power settings. This can increase power consumption.

## 1. Back up → inspect → fix → check

<p align="center"><img src="docs/images/steps-en.svg" width="900" alt="Back up → Inspect → Fix → Check; keep alive if needed"></p>

Double-click these files in order, letting each finish before proceeding:

| Step | File | What to do |
|---|---|---|
| **① Back up** | [`Backup-PowerSettings.bat`](Backup-PowerSettings.bat) | Accept UAC; confirm `Saved to:` and a backup text file beside the scripts |
| **② Inspect** | [`Show-PowerSettings.bat`](Show-PowerSettings.bat) | Review each plan's AC and battery settings |
| **③ Fix** | [`Fix-DiskSleep.bat`](Fix-DiskSleep.bat) | Accept UAC; wait for plan and device processing; review the `failed` count |
| **④ Check** | Run `Show-PowerSettings.bat` again | Compare with the table below and observe whether the drive stays connected |

Keep `PowerSettings-Backup-YYYYMMDD-HHMMSS.txt` for restoration. Check that the backup contains the records you need. If WMI is unreadable, device states were not saved and cannot be restored from that backup.

| Setting | Expected value, on both AC and battery |
|---|---|
| `Turn off hard disk after` | `Never (disabled)` |
| `USB selective suspend` | `Disabled` |

`[OK]` reflects the script's assessment of power-plan values only. `not available` means unreadable, not verified. `[WILL DROP DRIVES]` is the script's label for a power-saving setting, not a diagnosis of your disconnects. **Show does not verify device-level settings or drive health.**

## 2. Still disconnecting? Keep it awake with reads

First try a reliable data cable, a direct PC USB port and adequate power. If idle disconnects remain, double-click [`KeepAliveAll.bat`](KeepAliveAll.bat), accept UAC and **leave the window open**.

By default it issues one **4 KiB read every 20 seconds** to each USB / SD / FireWire physical disk, bypassing the Windows file cache. It never writes to the disks. Targets are rescanned each cycle, including newly connected matching drives.

For custom options, open cmd in the toolkit folder:

```cmd
KeepAliveAll.bat
KeepAliveAll.bat 15
KeepAliveAll.bat 15 all
```

| Arguments | Behavior |
|---|---|
| None | Every 20 seconds, USB / SD / FireWire disks only |
| `15` | Every 15 seconds, same scope |
| `15 all` | Every 15 seconds, **all physical disks, including internal drives** |

The interval is clamped to **2–300 seconds**. `attached` means a target was opened; `cannot be opened` or `read failed` means keep-alive was unsuccessful for that operation. Press **Ctrl+C** to stop. Keep-alive works only while running. It adds read activity and power use, and cannot repair physical faults.

## 3. Undo changes: restore your backup

Stop keep-alive, reconnect devices whose settings you want to restore, then double-click [`Restore-PowerSettings.bat`](Restore-PowerSettings.bat). It chooses the `PowerSettings-Backup-*.txt` with the **newest modification time** in its folder.

To list backups or select one explicitly, run in cmd:

```cmd
Restore-PowerSettings.bat /list
Restore-PowerSettings.bat "C:\Tools\PowerSettings-Backup-20261016-120000.txt"
```

Restore reapplies recorded plan values, the active plan and available recorded device states. Missing plans and disconnected devices are skipped. Review failures / skipped counts and run Show to check plan values afterward.

## All six files

| File | Purpose | Admin |
|---|---|:---:|
| [`Backup-PowerSettings.bat`](Backup-PowerSettings.bat) | Full backup: plans plus readable matching device states | ✓ |
| [`Backup-PowerSettings-PlansOnly.bat`](Backup-PowerSettings-PlansOnly.bat) | Plans only; **cannot restore device settings** | ✓ |
| [`Show-PowerSettings.bat`](Show-PowerSettings.bat) | Read-only view of the two settings in each plan | — |
| [`Fix-DiskSleep.bat`](Fix-DiskSleep.bat) | Disable disk idle shutdown and USB selective suspend in all plans; attempt to disable matching device power saving | ✓ |
| [`KeepAliveAll.bat`](KeepAliveAll.bat) | Periodic read-only keep-alive; Ctrl+C stops it | ✓ |
| [`Restore-PowerSettings.bat`](Restore-PowerSettings.bat) | Restore settings recorded in a backup | ✓ |

Fix matches WMI instance-name prefixes `USB`, `USBSTOR`, `SCSI` and `SBP2`. This may include other USB / SCSI devices, not just the affected external HDD. Device settings are stored per instance: after connecting a previously unseen drive, back up again and rerun Fix if you need to adjust its power settings.

Backups contain the computer name; full backups also include device instance information. Keep them private. The six original scripts retain their ASCII encoding and CRLF line endings.

## License

[MIT](LICENSE)
