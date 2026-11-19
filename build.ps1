param(
  [string]$Payload = "",
  [string]$OutFile = ""
)
# AviumUI camera module builder (Windows native, 7-Zip)
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $Payload) { $Payload = Join-Path $here 'payload' }
$sevenZip = 'C:\Program Files\7-Zip\7z.exe'
if (-not (Test-Path $sevenZip)) { throw 'need 7-Zip' }

$ver = (Select-String -Path (Join-Path $here 'module.prop') -Pattern '^version=(.*)$').Matches[0].Groups[1].Value
if (-not $OutFile) { $OutFile = Join-Path $here ("avium_miuicamera_thor-{0}.zip" -f $ver) }

$work = Join-Path $env:TEMP ("avium_mod_" + [guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Force -Path $work | Out-Null
try {
  foreach ($f in 'module.prop','customize.sh','prepare.sh','post-fs-data.sh','service.sh','action.sh','sepolicy.rule','system.prop') {
    if (-not (Test-Path (Join-Path $here $f))) { continue }
    Copy-Item (Join-Path $here $f) (Join-Path $work $f) -Force
  }

  # 顶层文档（CREDITS / README / STATUS / INSTALL-CN）一并打包
  foreach ($doc in @('CREDITS.md','README.md','STATUS.md','INSTALL-CN.md')) {
    if (Test-Path (Join-Path $here $doc)) { Copy-Item (Join-Path $here $doc) (Join-Path $work $doc) -Force }
  }
  $skelSys = Join-Path $here 'system'
  if (Test-Path $skelSys) { Copy-Item $skelSys (Join-Path $work 'system') -Recurse -Force }

  $paySys = Join-Path $Payload 'system'
  if (-not (Test-Path $paySys)) { throw "payload missing: $paySys" }
  New-Item -ItemType Directory -Force -Path (Join-Path $work 'system') | Out-Null
  Copy-Item (Join-Path $paySys '*') (Join-Path $work 'system') -Recurse -Force

  # extra top-level partition trees in payload: system_ext / product / vendor
  foreach ($part in @('system_ext','product','vendor')) {
    $pp = Join-Path $Payload $part
    if (Test-Path $pp) {
      $dstp = Join-Path $work $part
      New-Item -ItemType Directory -Force -Path $dstp | Out-Null
      Copy-Item (Join-Path $pp '*') $dstp -Recurse -Force
    }
  }

  $apk = Join-Path $work 'system\priv-app\MiuiCamera\MiuiCamera.apk'
  if (-not (Test-Path $apk)) { throw 'missing MiuiCamera.apk in payload' }

  Push-Location $work
  try {
    # 校验清单只覆盖"装机后仍然存在"的文件：
#   customize.sh 是安装期脚本（KernelSU 安装完会删除），README.md 装后亦不保留 —— 纳入清单会造成 sha256sum -c 误报
$exclude = @('SHA256SUMS','customize.sh','README.md')
$lines = Get-ChildItem -Recurse -File | Where-Object { $exclude -notcontains $_.Name } | ForEach-Object {
      $rel = $_.FullName.Substring($work.Length + 1).Replace('\','/')
      '{0}  {1}' -f (Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLower(), $rel
    }
    # 关键：SHA256SUMS 必须用 LF。Windows 的 CRLF 会让设备端 sha256sum -c 把 \r 当成文件名的一部分而全 FAIL
  $sumText = (($lines -join "`n") + "`n") -replace "`r`n", "`n"
  [System.IO.File]::WriteAllText((Join-Path $work 'SHA256SUMS'), $sumText, (New-Object System.Text.ASCIIEncoding))
  } finally { Pop-Location }

  if (Test-Path $OutFile) { Remove-Item $OutFile -Force }
& $sevenZip a -tzip -mcu=on -mx=5 $OutFile (Join-Path $work '*') | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "7z failed: $LASTEXITCODE" }
  Write-Host ("OK: {0} ({1:N1} MB)" -f $OutFile, ((Get-Item $OutFile).Length/1MB))
} finally {
  Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
}

