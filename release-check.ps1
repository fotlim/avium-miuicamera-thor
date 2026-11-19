# release-check.ps1 —— 发布前一键自检
#
# 依次跑：
#   1) verify.ps1          基础 11 项（完整性/哈希/冷启动/前台/预览/拍照/CHI/crash）
#   2) verify-features.ps1 功能矩阵（拍照 / 4K30 / 8K / 超级防抖 + PRO）
#   3) verify-moremodes.ps1 更多模式 12 项巡检（可选，-SkipMoreModes 跳过）
#
# 用法：
#   & F:\thor\rom\avium-miuicamera\release-check.ps1
#   & F:\thor\rom\avium-miuicamera\release-check.ps1 -MODID avium_miuicamera_thor22
#
# 退出码：0 = 全部通过；1 = 有失败

param(
  [string]$MODID = 'avium_miuicamera_thor22',
  [string]$Adb   = 'C:\Users\LinOcean\Downloads\adb-fastboot\adb.exe',
  [switch]$SkipFeatures,
  [switch]$SkipMoreModes
)

$ErrorActionPreference = 'Continue'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$results = New-Object System.Collections.Generic.List[object]

function Run-Step([string]$name, [string]$script, [string[]]$extra) {
  Write-Host ("`n===== {0} =====" -f $name) -ForegroundColor Cyan
  $passArgs = @('-MODID', $MODID, '-Adb', $Adb) + $extra
  $out = & $script @passArgs 2>&1 | Out-String
  $code = $LASTEXITCODE
  $verdict = if ($code -eq 0) { 'PASS' } else { 'FAIL' }
  $results.Add([pscustomobject]@{ 步骤 = $name; 退出码 = $code; 判定 = $verdict })
  ($out -split "`n" | Where-Object { $_ -match '项目|✅|❌|OK|FAIL|报告|结果|^\s*\S+\s+\S+' } | Select-Object -First 24) -join "`n"
  Write-Host ("--> {0} ({1})" -f $verdict, $code) -ForegroundColor $(if ($code -eq 0) { 'Green' } else { 'Red' })
}

Run-Step '基础验证' (Join-Path $here 'verify.ps1') @()
if (-not $SkipFeatures)  { Run-Step '功能矩阵' (Join-Path $here 'verify-features.ps1') @() }
if (-not $SkipMoreModes) { Run-Step '更多模式巡检' (Join-Path $here 'verify-moremodes.ps1') @() }

$fail = @($results | Where-Object { $_.退出码 -ne 0 })
Write-Host "`n===== 汇总 =====" -ForegroundColor Cyan
$results | Format-Table -AutoSize | Out-String | Write-Host

$report = Join-Path $here ('release_check_{0}.md' -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
$md = @('# 发布自检汇总', '', ("- 时间：{0}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')), ("- 模块：{0}" -f $MODID), '')
$md += '| 步骤 | 退出码 | 判定 |'
$md += '|---|---|---|'
foreach ($r in $results) { $md += "| $($r.步骤) | $($r.退出码) | $($r.判定) |" }
$md += ''
$md += $(if ($fail.Count -eq 0) { '**结论：全部通过**' } else { "**结论：{0} 个步骤失败**" -f $fail.Count })
[System.IO.File]::WriteAllText($report, ($md -join "`n") + "`n", (New-Object System.Text.UTF8Encoding($false)))
Write-Host ("报告：{0}" -f $report)
exit $(if ($fail.Count -eq 0) { 0 } else { 1 })