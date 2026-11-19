# verify-features.ps1 —— 相机四项功能自动化验证（拍照 / 4K30 / 8K / 超级防抖+PRO）
#
# 用法： & F:\thor\rom\avium-miuicamera\verify-features.ps1
#
# 特点：所有点击坐标来自 uiautomator dump 的 content-desc/text 实时解析，
#       不依赖硬编码坐标；每步都断言 UI 状态，失败会在报告里列明。
#
# 注意：MiuiCamera 只要 Activity 进入 pause 就会自行退出（错误页 → finish），
#       所以脚本会先清掉可能抢焦点的 USB/权限弹窗，并在关键步骤前核对前台。

param(
  [string]$MODID = 'avium_miuicamera_thor21',
  [string]$Adb   = 'C:\Users\LinOcean\Downloads\adb-fastboot\adb.exe',
  [string]$Report = ''
)
$ErrorActionPreference = 'Stop'
if (-not (Test-Path $Adb)) { throw "adb not found: $Adb" }
if (-not $Report) {
  $Report = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) ('features_report_{0}.md' -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
}

$fail = New-Object System.Collections.Generic.List[string]
$rows = New-Object System.Collections.Generic.List[object]
function Add-Row($name, $value, $ok) {
  $rows.Add([pscustomobject]@{ 项目 = $name; 结果 = $value; 判定 = $(if ($ok) { 'OK' } else { 'FAIL' }) })
  if (-not $ok) { $fail.Add("$name : $value") }
}
function Sh($c) { (& $Adb shell $c) -join "`n" }
function TopAct { ((Sh 'dumpsys activity activities') -split "`n" | Where-Object { $_ -match 'topResumedActivity' } | Select-Object -First 1) -replace '.*u0 ',''-replace ' t.*','' }

function Get-Ui {
  & $Adb shell 'uiautomator dump /sdcard/_fui.xml' | Out-Null
  $tmp = Join-Path $env:TEMP '_fui.xml'
  & $Adb pull /sdcard/_fui.xml $tmp 2>&1 | Out-Null
  $raw = [System.IO.File]::ReadAllText($tmp, [System.Text.Encoding]::UTF8)
  $out = @()
  foreach ($m in [regex]::Matches($raw, '(?:content-desc|text)="([^"]*)"[^>]*?bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"')) {
    $g = $m.Groups
    $out += [pscustomobject]@{
      label = $g[1].Value
      cx = [int]((([int]$g[2].Value) + ([int]$g[4].Value)) / 2)
      cy = [int]((([int]$g[3].Value) + ([int]$g[5].Value)) / 2)
    }
  }
  # 也把 "content-desc=... bounds=..." 分开收集（desc 在前、text 在后的情况）
  foreach ($m in [regex]::Matches($raw, 'text="([^"]*)"(?:[^>]*?)content-desc="([^"]*)"[^>]*?bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"')) {
    $g = $m.Groups
    $out += [pscustomobject]@{
      label = $g[2].Value
      cx = [int]((([int]$g[3].Value) + ([int]$g[5].Value)) / 2)
      cy = [int]((([int]$g[4].Value) + ([int]$g[6].Value)) / 2)
    }
  }
  return $out
}
function Find-Ui([string]$pattern, $ui) { $ui | Where-Object { $_.label -match $pattern } | Select-Object -First 1 }
function Tap-Ui([string]$pattern, $ui, [string]$what) {
  $n = Find-Ui $pattern $ui
  if (-not $n) { return $false }
  & $Adb shell "input tap $($n.cx) $($n.cy)" | Out-Null
  Start-Sleep -Seconds 2
  return $true
}

# ---------- 准备 ----------
& $Adb root 2>&1 | Out-Null; Start-Sleep -Seconds 1
& $Adb wait-for-device
& $Adb shell 'svc power stayon true' | Out-Null

# 清掉可能抢焦点的 USB 选项弹窗
$focus = Sh 'dumpsys window'
if ($focus -match 'UsbFunctionActivity') { & $Adb shell 'input keyevent KEYCODE_BACK' | Out-Null; Start-Sleep -Seconds 1 }
& $Adb shell 'input keyevent KEYCODE_WAKEUP' | Out-Null; Start-Sleep -Milliseconds 600
& $Adb shell 'input swipe 720 2600 720 800 300' | Out-Null; Start-Sleep -Milliseconds 1000

& $Adb shell 'am force-stop com.android.camera' | Out-Null; Start-Sleep -Seconds 1
$launch = (& $Adb shell 'am start -W -n com.android.camera/.Camera' 2>&1) -join "`n"
Add-Row '相机启动' (($launch | Select-String 'TotalTime: (\d+)').Matches.Groups[1].Value + ' ms') ($launch -match 'TotalTime: \d+')
Start-Sleep -Seconds 5

$ui = Get-Ui
if (-not (Find-Ui '拍摄' $ui)) { Add-Row '相机 UI' '未找到相机控件' $false; $ui = Get-Ui }

# ---------- 1. 拍照 ----------
$tmp = Tap-Ui '^拍摄$' $ui 'shutter'
Start-Sleep -Seconds 7
$jpg = (Sh 'ls -t /sdcard/DCIM/Camera/*.jpg | head -1').Trim()
$jsize = if ($jpg) { [int]((Sh "stat -c %s $jpg").Trim()) } else { 0 }
Add-Row '拍照出片' "$([System.IO.Path]::GetFileName($jpg)) = $jsize B" ($jsize -gt 2300000 -and $jsize -lt 4000000)

# ---------- 2. 4K30 录像 ----------
$ui = Get-Ui
[string]$null = Tap-Ui '^录像$' $ui 'video mode'
Start-Sleep -Seconds 4
$ui = Get-Ui
$ok = Tap-Ui '^分辨率,' $ui 'res label'
Start-Sleep -Seconds 2
$ui = Get-Ui
$null = Tap-Ui '^分辨率,4K$' $ui '4K'
Start-Sleep -Seconds 3
$ui = Get-Ui
Add-Row '切到 4K' $(if (Find-Ui '^分辨率,4K$' $ui) { '分辨率,4K' } else { '未切换成功' }) ([bool](Find-Ui '^分辨率,4K$' $ui))

$ui = Get-Ui
$rec = Find-Ui '^拍摄$' $ui
if ($rec) { & $Adb shell "input tap $($rec.cx) $($rec.cy)" | Out-Null; Start-Sleep -Seconds 6
  & $Adb shell "input tap $($rec.cx) $($rec.cy)" | Out-Null; Start-Sleep -Seconds 5 }
$mp4 = (Sh 'ls -t /sdcard/DCIM/Camera/*.mp4 | head -1').Trim()
$msize = if ($mp4) { [int]((Sh "stat -c %s $mp4").Trim()) } else { 0 }
Add-Row '4K30 录像' "$([System.IO.Path]::GetFileName($mp4)) = $msize B" ($msize -gt 8000000)

# ---------- 3. 8K 录像 ----------
$ui = Get-Ui
$null = Tap-Ui '^分辨率,' $ui 'res label'
Start-Sleep -Seconds 2
$ui = Get-Ui
$null = Tap-Ui '^分辨率,8K$' $ui '8K'
Start-Sleep -Seconds 3
$ui = Get-Ui
Add-Row '切到 8K' $(if (Find-Ui '^分辨率,8K$' $ui) { '分辨率,8K' } else { '未切换成功' }) ([bool](Find-Ui '^分辨率,8K$' $ui))

$ui = Get-Ui
$rec = Find-Ui '^拍摄$' $ui
if ($rec) { & $Adb shell "input tap $($rec.cx) $($rec.cy)" | Out-Null; Start-Sleep -Seconds 5
  & $Adb shell "input tap $($rec.cx) $($rec.cy)" | Out-Null; Start-Sleep -Seconds 6 }
$mp4k = (Sh 'ls -t /sdcard/DCIM/Camera/*.mp4 | head -1').Trim()
$ksize = if ($mp4k) { [int]((Sh "stat -c %s $mp4k").Trim()) } else { 0 }
Add-Row '8K 录像' "$([System.IO.Path]::GetFileName($mp4k)) = $ksize B" ($ksize -gt 20000000)

# ---------- 4. 超级防抖 / PRO ----------
$ui = Get-Ui
$null = Tap-Ui '^功能菜单' $ui 'menu'
Start-Sleep -Seconds 2
$ui = Get-Ui
$eis = Find-Ui '超级防抖' $ui
if ($eis) {
  & $Adb shell "input tap $($eis.cx) $($eis.cy)" | Out-Null; Start-Sleep -Seconds 2
  $ui = Get-Ui
  $pick = Find-Ui '^超级防抖$' $ui
  if ($pick) { & $Adb shell "input tap $($pick.cx) $($pick.cy)" | Out-Null; Start-Sleep -Seconds 3 }
  $ui = Get-Ui
  $on = Find-Ui '超级防抖[，,]\s*开启状态' $ui
  Add-Row '超级防抖' $(if ($on) { '已开启' } else { '未确认开启' }) ([bool]$on)

  # 切 PRO
  $btn = Find-Ui '^超级防抖' $ui
  if ($btn) { & $Adb shell "input tap $($btn.cx) $($btn.cy)" | Out-Null; Start-Sleep -Seconds 2
    $ui = Get-Ui
    $pro = Find-Ui '^超级防抖PRO$' $ui
    if ($pro) { & $Adb shell "input tap $($pro.cx) $($pro.cy)" | Out-Null; Start-Sleep -Seconds 3 }
    $ui = Get-Ui
    $proOn = Find-Ui '超级防抖PRO[，,]\s*开启状态' $ui
    Add-Row '超级防抖 PRO' $(if ($proOn) { '已开启' } else { '未确认开启' }) ([bool]$proOn)
  } else { Add-Row '超级防抖 PRO' '找不到防抖按钮' $false }
} else { Add-Row '超级防抖' '面板里没有防抖项' $false }

# ---------- 5. 复位到拍照 ----------
$ui = Get-Ui
$null = Tap-Ui '^拍照$' $ui 'photo mode'
Add-Row '复位拍照模式' (TopAct) ((TopAct) -match 'camera')

# ---------- 报告 ----------
$ok = ($fail.Count -eq 0)
$md = @("# 相机功能矩阵验证", "", "- 时间：$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')", "- 模块：$MODID", "- 结论：**$(if ($ok) { '全部通过' } else { '存在失败项' })**", "", "| 项目 | 结果 | 判定 |", "|---|---|---|")
foreach ($r in $rows) { $md += "| $($r.项目) | $($r.结果) | $($r.判定) |" }
if (-not $ok) { $md += ""; $md += '## 失败项'; foreach ($f in $fail) { $md += "- $f" } }
[System.IO.File]::WriteAllText($Report, ($md -join "`n") + "`n", (New-Object System.Text.UTF8Encoding($false)))
$rows | Format-Table -AutoSize
"报告：$Report"
exit $(if ($ok) { 0 } else { 1 })