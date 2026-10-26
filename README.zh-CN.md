<div align="center">

<img src="docs/images/logo.svg" width="96" height="96" alt="">

# 移动硬盘防掉线工具

**笔记本插上移动 HDD 就掉线？从电源设置检查到只读保活。**

六个 Windows 批处理脚本：备份、检查、修复、还原与保活。

[![Release](https://img.shields.io/github/v/release/chchaoo/external-hdd-keepalive?color=2f81f7)](https://github.com/chchaoo/external-hdd-keepalive/releases/latest)
[![Windows](https://img.shields.io/badge/platform-Windows-0078d6)](#使用前)
[![License](https://img.shields.io/badge/license-MIT-2ea44f)](LICENSE)

[English](README.md) · **简体中文**

### [⬇ 下载完整工具包](https://github.com/chchaoo/external-hdd-keepalive/releases/latest/download/external-hdd-keepalive.zip)

</div>

---

## 适合什么情况

**部分笔记本连接移动机械硬盘（HDD）后，硬盘会反复断开，或闲置不久就消失；常规修改电源计划仍解决不了。** 本工具进一步处理设备层面的节能设置，并提供持续读取的保活方式。

掉线也可能来自线材、供电、USB 接口、硬盘盒或硬盘本身；本工具针对节能 / 空闲引起的问题，不保证解决所有掉线原因。

## 使用前

- 使用 Windows，需有内置 Windows PowerShell、`powercfg`、Storage / CIM 支持；建议 Windows 10 / 11。部分驱动可能不提供设备电源接口。
- 下载工具包并**完整解压**到有写入权限的文件夹，再运行脚本；不要直接在 ZIP 内运行。
- 将待处理硬盘插好。除查看脚本外，其余脚本会申请管理员权限。
- 修复会更改**所有电源计划**的交流 / 电池设置及可访问的匹配设备电源设置，可能增加耗电。

## 1. 备份 → 检查 → 修复 → 复查

<p align="center"><img src="docs/images/steps-zh.svg" width="900" alt="备份 → 检查 → 修复 → 复查；仍掉线时运行保活"></p>

按顺序双击以下文件，每个运行完再进行下一步：

| 步骤 | 对应文件 | 要做什么 |
|---|---|---|
| **① 备份** | [`Backup-PowerSettings.bat`](Backup-PowerSettings.bat) | 同意 UAC；确认显示 `Saved to:` 并在同目录生成备份文本 |
| **② 检查** | [`Show-PowerSettings.bat`](Show-PowerSettings.bat) | 查看各电源计划的交流 / 电池设置 |
| **③ 修复** | [`Fix-DiskSleep.bat`](Fix-DiskSleep.bat) | 同意 UAC；等待电源计划及设备设置处理完成，查看 `failed` 数量 |
| **④ 复查** | 再运行 `Show-PowerSettings.bat` | 对照下表检查设置，并实际观察硬盘是否还掉线 |

保留 `PowerSettings-Backup-年月日-时分秒.txt`，之后还原要用。确认备份有需要的记录；如果提示 WMI 不可读，设备状态没有被保存，不能依赖它还原设备项。

| 检查项 | 期望值（交流、电池都检查） |
|---|---|
| `Turn off hard disk after` | `Never (disabled)` |
| `USB selective suspend` | `Disabled` |

`[OK]` 仅反映脚本对电源计划值的判断。`not available` 表示读不到，不能视为验证成功；`[WILL DROP DRIVES]` 是脚本对节能设置的提示，不代表已经诊断出掉线原因。**Show 不验证设备层面的设置，也不检测硬盘健康。**

## 2. 修复后仍掉线：只读保活

先换一条可靠数据线、电脑直连 USB 口并排查供电。仍有空闲掉线时，双击 [`KeepAliveAll.bat`](KeepAliveAll.bat)，同意 UAC，**保持窗口打开**。

默认每 **20 秒**对 USB / SD / FireWire 物理磁盘发出一次 **4 KiB 读取**，绕过 Windows 文件缓存；不写入硬盘。每轮重新扫描，新插入的匹配磁盘会自动纳入。

可在工具所在文件夹打开 cmd，自定义参数：

```cmd
KeepAliveAll.bat
KeepAliveAll.bat 15
KeepAliveAll.bat 15 all
```

| 参数 | 含义 |
|---|---|
| 不填 | 每 20 秒，仅 USB / SD / FireWire 磁盘 |
| `15` | 每 15 秒，范围不变 |
| `15 all` | 每 15 秒，**所有物理磁盘，包括内置盘** |

间隔限定为 **2–300 秒**。看到 `attached` 表示目标盘已打开；出现 `cannot be opened` 或 `read failed` 时保活未成功，应查看错误。按 **Ctrl+C** 停止；保活效果只在运行期间存在。它不写磁盘，但仍会产生读取和耗电，不能修复物理故障。

## 3. 想撤销：还原备份

先停止保活，插回需要还原设置的设备，再双击 [`Restore-PowerSettings.bat`](Restore-PowerSettings.bat)。默认使用同目录**修改时间最新**的 `PowerSettings-Backup-*.txt`。

指定备份或列出可用文件（在 cmd 中运行）：

```cmd
Restore-PowerSettings.bat /list
Restore-PowerSettings.bat "C:\Tools\PowerSettings-Backup-20261016-120000.txt"
```

还原会恢复备份里记录的电源计划值、活动计划和可找到的设备状态。已经不存在的计划、当前未连接的设备会被跳过；查看输出的失败 / 跳过计数，再用 Show 复查。

## 六个文件，一张表

| 文件 | 功能 | 管理员 |
|---|---|:---:|
| [`Backup-PowerSettings.bat`](Backup-PowerSettings.bat) | 完整备份：电源计划 + 可读取的匹配设备状态 | ✓ |
| [`Backup-PowerSettings-PlansOnly.bat`](Backup-PowerSettings-PlansOnly.bat) | 只备份电源计划；**无法用于还原设备设置** | ✓ |
| [`Show-PowerSettings.bat`](Show-PowerSettings.bat) | 只读查看各计划的两项设置 | — |
| [`Fix-DiskSleep.bat`](Fix-DiskSleep.bat) | 所有计划禁用磁盘空闲关闭与 USB 选择性暂停，并尝试关闭匹配设备节能 | ✓ |
| [`KeepAliveAll.bat`](KeepAliveAll.bat) | 持续只读保活，Ctrl+C 停止 | ✓ |
| [`Restore-PowerSettings.bat`](Restore-PowerSettings.bat) | 根据备份恢复记录过的设置 | ✓ |

Fix 的设备处理范围按 WMI 实例名的 `USB`、`USBSTOR`、`SCSI`、`SBP2` 前缀匹配，可能涉及其他 USB / SCSI 设备，并非只操作当前外接 HDD。设备设置按实例保存：插入电脑从未识别过的新盘后，如需处理其节能设置，应重新备份并运行 Fix。

备份会记录电脑名；完整备份还含设备实例信息，请自行保管。所有脚本均为原始文件，保留 ASCII / CRLF 格式。

## 许可

[MIT](LICENSE)
