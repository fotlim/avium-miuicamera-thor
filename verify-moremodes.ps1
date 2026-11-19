# verify-moremodes.ps1 —— 「更多模式」12 项巡检
#
# 对每个「更多模式」：打开模式面板 → 点进去 → 检查是否仍在相机前台 + 预览是否出帧；
# 若有异常退出/不出帧，记录为 FAIL 并附上前台是谁。
#
# 用法： & F:\thor\rom\avium-miuicamera\verify-moremodes.ps1

param(
  [string]$MODID = 'avium_miuicamera_thor22',
  [string]$Adb = 'C:\Users\LinOcean\Downloads\adb-fastboot\adb.exe',
  [string]$Report = '',
  [int]$WaitSeconds = 5
)
$ErrorActionPreference = 'Stop'
if (-not (Test-Path $Adb)) { throw "adb not found: $Adb" }
if (-not $Report) {
  $Report = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) ('moremodes_report_{0}.md' -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
}

$MODES = @('超清','夜景','慢动作','延时摄影','长曝光','全景','超级月亮','微电影','电影镜头','魔法分身','AI水印','编辑')

$rows = New-Object System.Collections.Generic.List[object]
function Sh($c) { (& $Adb shell $c) -join "`n" }
function TopAct { ((Sh 'dumpsys activity activities') -split "`n" | Where-Object { $_ -match 'topResumedActivity' } | Select-Object -First 1) -replace '.*u0 ',''-replace ' t.*','' }
function Frames { $l = (Sh 'dumpsys media.camera') -split "`n" | Where-Object { $_ -match 'Frames produced:' } | Select-Object -First 1; if ($l -match '(\d+)') { [int]$matches[1] } else { -1 } }

function Ui {
  & $Adb shell 'uiautomator dump /sdcard/_m.xml' | Out-Null
  $tmp = Join-Path $env:TEMP '_m.xml'
  Remove-Item $tmp -ErrorAction SilentlyContinue
  & $Adb pull /sdcard/_m.xml $tmp 2>&1 | Out-Null
  if (-not (Test-Path $tmp)) { return @() }
  $raw = [System.IO.File]::ReadAllText($tmp, [System.Text.Encoding]::UTF8)
  $out = @()
  foreach ($m in [regex]::Matches($raw, 'text="([^"]*)"[^>]*?bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"')) {
    $g = $m.Groups
    $out += [pscustomobject]@{ label = $g[1].Value; cx = [int]((([int]$g[2].Value) + ([int]$g[4].Value)) / 2); cy = [int]((([int]$g[3].Value) + ([int]$g[5].Value)) / 2) }
  }
  foreach ($m in [regex]::Matches($raw, 'content-desc="([^"]*)"[^>]*?bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"')) {
    $g = $m.Groups
    $out += [pscustomobject]@{ label = $g[1].Value; cx = [int]((([int]$g[2].Value) + ([int]$g[4].Value)) / 2); cy = [int]((([int]$g[3].Value) + ([int]$g[5].Value)) / 2) }
  }
  return $out
}

# ---------- 准备 ----------
& $Adb root 2>&1 | Out-Null; Start-Sleep -Seconds 1
& $Adb wait-for-device
& $Adb shell 'svc power stayon true' | Out-Null
$focus = Sh 'dumpsys window'
if ($focus -match 'UsbFunctionActivity|UsbDebuggingActivity') { & $Adb shell 'input keyevent KEYCODE_BACK' | Out-Null; Start-Sleep -Seconds 1 }
& $Adb shell 'input keyevent KEYCODE_WAKEUP' | Out-Null; Start-Sleep -Milliseconds 600
& $Adb shell 'input swipe 720 2600 720 800 300' | Out-Null; Start-Sleep -Milliseconds 900
& $Adb shell 'am force-stop com.android.camera' | Out-Null; Start-Sleep -Seconds 1
& $Adb shell 'am start -W -n com.android.camera/.Camera' | Out-Null; Start-Sleep -Seconds 5

# 面板是固定 3×4 网格（实测 x=285/720/1154，y=1850/2236/2622/3008），进入 more-mode 后状态会变，
# 所以每个模式都「强制重启相机 → 上滑开面板 → 按标签点」来保证一致起点。
$GRID = @{
  '超清'=@(285,1850); '夜景'=@(720,1850); '慢动作'=@(1154,1850)
  '延时摄影'=@(285,2236); '长曝光'=@(720,2236); '全景'=@(1154,2236)
  '超级月亮'=@(285,2622); '微电影'=@(720,2622); '电影镜头'=@(1154,2622)
  '魔法分身'=@(285,3008); 'AI水印'=@(720,3008)
}

foreach ($mode in $MODES) {
  # 干净起点
  & $Adb shell 'am force-stop com.android.camera' | Out-Null
  Start-Sleep -Seconds 1
  & $Adb shell 'am start -W -n com.android.camera/.Camera' | Out-Null
  Start-Sleep -Seconds 4

  # 打开「更多模式」面板
  & $Adb shell 'input swipe 720 2600 720 1400 400' | Out-Null
  Start-Sleep -Seconds 2

  $ui = Ui
  $node = $ui | Where-Object { $_.label -eq $mode } | Select-Object -First 1
  if (-not $node -and $GRID.ContainsKey($mode)) {
    $g = $GRID[$mode]; $node = [pscustomobject]@{ label = $mode; cx = $g[0]; cy = $g[1] }
  }
  if (-not $node) {
    $rows.Add([pscustomobject]@{ 模式 = $mode; 前台 = '面板里找不到该模式'; fps = '-'; 判定 = 'FAIL' })
    continue
  }

  & $Adb shell "input tap $($node.cx) $($node.cy)" | Out-Null
  Start-Sleep -Seconds $WaitSeconds

  $act = TopAct
  $f1 = Frames; Start-Sleep -Seconds 2; $f2 = Frames
  $fps = if ($f1 -ge 0 -and $f2 -ge $f1) { [math]::Round(($f2 - $f1) / 2, 1) } else { -1 }
  $alive = ($act -match 'camera')
  $moving = ($fps -ge 3)
  $ok = $alive -and $moving
  $rows.Add([pscustomobject]@{
    模式 = $mode
    前台 = $(if ($alive) { '相机' } else { $act })
    fps  = $fps
    判定 = $(if ($ok) { 'OK' } elseif ($alive) { 'NO-FRAMES' } else { 'EXIT' })
  })
}
# 收尾：回拍照模式
$ui = Ui
$photo = $ui | Where-Object { $_.label -eq '拍照' } | Select-Object -First 1
if ($photo) { & $Adb shell "input tap $($photo.cx) $($photo.cy)" | Out-Null; Start-Sleep -Seconds 2 }

# ---------- 报告 ----------
$bad = @($rows | Where-Object { $_.判定 -ne 'OK' })
$md = @("# 更多模式巡检", "", "- 时间：$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')", "- 结论：**$($rows.Count - $bad.Count)/$($rows.Count) 正常**", "", "| 模式 | 前台 | fps | 判定 |", "|---|---|---|---|")
foreach ($r in $rows) { $md += "| $($r.模式) | $($r.前台) | $($r.fps) | $($r.判定) |" }
[System.IO.File]::WriteAllText($Report, ($md -join "`n") + "`n", (New-Object System.Text.UTF8Encoding($false)))
$rows | Format-Table -AutoSize
"报告：$Report"
exit $(if ($bad.Count -eq 0) { 0 } else { 1 })