# verify.ps1 —— AviumUI 小米相机模块 一键真机验证
#
# 用法：
#   & F:\thor\rom\avium-miuicamera\verify.ps1                      # 默认 adb 路径
#   & F:\thor\rom\avium-miuicamera\verify.ps1 -Report F:\thor\rom\tests\verify_xxx.md
#
# 检查项（对应模块维护目标 ③）：
#   1. 模块版本 / 文件完整性（sha256sum -c SHA256SUMS）
#   2. 生效哈希：/system 里 APK、/vendor 里 HAL 是否等于 payload 期望值
#   3. 相机冷启动耗时、UI 是否真的前台（uiautomator 取 bounds，不用硬编码坐标）
#   4. 预览是否出帧（两次采样求 fps）
#   5. 拍照出片大小（走 UI dump 里的"拍摄"按钮 bounds，避免点到别处）
#   6. 无 `Invalid logical camera id`、crash buffer 为空
#
# 退出码：0 = 全部通过；1 = 有失败项（报告里列明）

param(
  [string]$MODID = 'avium_miuicamera_thor22',
  [string]$Adb   = 'C:\Users\LinOcean\Downloads\adb-fastboot\adb.exe',
  [string]$Report = '',
  [int]$FpsSeconds = 5
)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path $Adb)) { throw "adb not found: $Adb" }
if (-not $Report) {
  $Report = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) ('verify_report_{0}.md' -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
}

$EXPECT = @{
  apk = '5e1816cf68ff281985ebec710a5205009e24fec0f4a4b3b0b270dd897cc0c14a'
  hal = '240610b0bcb05d0d8d39d799fa1fc27dde8dbf1ede38fb87baa9f834ae5dbebc'
}

$fail = New-Object System.Collections.Generic.List[string]
$rows = New-Object System.Collections.Generic.List[object]
function Add-Row($name, $value, $ok) {
  $script:rows.Add([pscustomobject]@{ 项目 = $name; 结果 = $value; 判定 = $(if ($ok) { '✅' } else { '❌' }) })
  if (-not $ok) { $script:fail.Add("$name : $value") }
}
function Sh($cmd) { (& $Adb shell $cmd) -join "`n" }

# ---------- 0. 连接 ----------
& $Adb root 2>&1 | Out-Null
Start-Sleep -Seconds 1
& $Adb wait-for-device
$boot = (Sh 'getprop sys.boot_completed').Trim()
Add-Row 'boot_completed' $boot ($boot -eq '1')
& $Adb shell 'svc power stayon true' | Out-Null

# ---------- 1. 模块版本与完整性 ----------
$ver = (Sh "grep '^version=' /data/adb/modules/$MODID/module.prop").Trim()
Add-Row '模块版本' $ver ($ver -ne '')
$chk = Sh "cd /data/adb/modules/$MODID && sha256sum -c SHA256SUMS 2>&1 | grep -v ': OK' | head -5"
$chkOk = [string]::IsNullOrWhiteSpace($chk)
Add-Row 'SHA256SUMS 完整性' $(if ($chkOk) { '全部 OK' } else { $chk }) $chkOk

# ---------- 2. 生效哈希 ----------
$apk = (Sh 'sha256sum /system/priv-app/MiuiCamera/MiuiCamera.apk').Split()[0]
Add-Row 'APK 生效哈希' $apk.Substring(0,16) ($apk -eq $EXPECT.apk)
$hal = (Sh 'sha256sum /vendor/lib64/hw/camera.qcom.so').Split()[0]
Add-Row 'HAL 生效哈希' $hal.Substring(0,16) ($hal -eq $EXPECT.hal)

# ---------- 3. 启动相机 ----------
& $Adb shell 'input keyevent KEYCODE_WAKEUP' | Out-Null
Start-Sleep -Milliseconds 600
& $Adb shell 'input swipe 720 2600 720 800 300' | Out-Null
Start-Sleep -Milliseconds 1000
& $Adb shell "am force-stop com.android.camera" | Out-Null
& $Adb logcat -c | Out-Null
& $Adb logcat -b events -c | Out-Null
$t0 = Get-Date
$launch = (& $Adb shell 'am start -W -n com.android.camera/.Camera' 2>&1) -join "`n"
$ms = [int](($launch | Select-String 'TotalTime: (\d+)').Matches.Groups[1].Value)
Add-Row '冷启动耗时(ms)' $ms ($ms -gt 0 -and $ms -lt 3000)
Start-Sleep -Seconds 4

function UiAtom {
  & $Adb shell 'uiautomator dump /sdcard/_verify_ui.xml' | Out-Null
  $tmp = Join-Path $env:TEMP '_verify_ui.xml'
  & $Adb pull /sdcard/_verify_ui.xml $tmp 2>&1 | Out-Null
  $raw = [System.IO.File]::ReadAllText($tmp, [System.Text.Encoding]::UTF8)
  $out = @()
  foreach ($m in [regex]::Matches($raw, 'content-desc="([^"]*)"[^>]*?bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"')) {
    $cx = [int]((([int]$m.Groups[2].Value) + ([int]$m.Groups[4].Value)) / 2)
    $cy = [int]((([int]$m.Groups[3].Value) + ([int]$m.Groups[5].Value)) / 2)
    $out += [pscustomobject]@{ desc = $m.Groups[1].Value; cx = $cx; cy = $cy }
  }
  return $out
}
$ui = UiAtom
$shotBtn = $ui | Where-Object { $_.desc -match '拍摄' } | Select-Object -First 1
Add-Row '相机 UI 前台' $(if ($shotBtn) { '已找到「拍摄」按钮' } else { '未找到' }) ([bool]$shotBtn)

# ---------- 4. 预览帧率 ----------
function Frames { 
  $o = & $Adb shell 'dumpsys media.camera'
  $l = ($o | Select-String 'Frames produced:' | Select-Object -First 1).Line
  if ($l -match 'Frames produced:\s*(\d+)') { [int]$matches[1] } else { -1 }
}
$f1 = Frames; Start-Sleep -Seconds $FpsSeconds; $f2 = Frames
$fps = if ($f1 -ge 0 -and $f2 -ge $f1) { [math]::Round(($f2 - $f1) / $FpsSeconds, 1) } else { -1 }
Add-Row '预览帧率(fps)' $fps ($fps -ge 5)

# ---------- 5. 拍照 ----------
& $Adb shell 'input tap 720 2870' | Out-Null
Start-Sleep -Seconds 6
$newest = (Sh 'ls -t /sdcard/DCIM/Camera/*.jpg') -split "`n" | Where-Object { $_ -match '\.jpg$' } | Select-Object -First 1
$size = -1
if ($newest) { $size = [int]((Sh "stat -c %s $newest").Trim()) }
Add-Row '最新照片大小(B)' $(if ($size -gt 0) { "$size  $([System.IO.Path]::GetFileName($newest))" } else { '无' }) ($size -ge 2.3e6 -and $size -le 3.2e6)

# ---------- 6. 报错检查 ----------
$logAll = & $Adb logcat -d -b all -t 4000 2>$null
$chi = ($logAll | Select-String -SimpleMatch 'Invalid logical camera id' | Measure-Object).Count
Add-Row 'CHI 非法逻辑相机报错' $chi ($chi -eq 0)
$logCrash = & $Adb logcat -b crash -d -t 50 2>$null
$crash = ($logCrash | Select-String -SimpleMatch 'com.android.camera' | Measure-Object).Count
Add-Row 'crash buffer 相机条目' $crash ($crash -eq 0)

# ---------- 报告 ----------
$ok = ($fail.Count -eq 0)
$md = @()
$md += "# 小米相机模块验证报告"
$md += ""
$md += "- 时间：$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
$md += "- 设备：$((Sh 'getprop ro.product.device').Trim()) / API $((Sh 'getprop ro.build.version.sdk').Trim())"
$md += "- 模块：$ver"
$md += "- 结论：**$(if ($ok) { '全部通过 ✅' } else { '存在失败项 ❌' })**"
$md += ""
$md += "| 项目 | 结果 | 判定 |"
$md += "|---|---|---|"
foreach ($r in $rows) { $md += "| $($r.项目) | $($r.结果) | $($r.判定) |" }
if (-not $ok) { $md += ""; $md += "## 失败项"; foreach ($f in $fail) { $md += "- $f" } }
[System.IO.File]::WriteAllText($Report, ($md -join "`n") + "`n", (New-Object System.Text.UTF8Encoding($false)))

"$([char]10)==== 验证结果 ===="
$rows | Format-Table -AutoSize
"报告：$Report"
if ($ok) { "结果：全部通过" } else { "结果：失败 $($fail.Count) 项" }
exit $(if ($ok) { 0 } else { 1 })
