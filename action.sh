#!/system/bin/sh
# action.sh —— 一键自检 + 采集诊断（KernelSU 管理器里点「操作」触发）
# 输出目录：$MODDIR/diagnostics/
#   integrity.txt  模块文件完整性（sha256sum -c SHA256SUMS，LF 归一化后校验）
#   hashes.txt     生效 APK / HAL 哈希 + 与 payload 期望值比对（match=YES/NO）
#   overlay.txt    metamodule 链接、KSU /system overlay 挂载、provider/cameraserver 存活
#   fps.txt        预览帧率采样（需相机正在运行；未运行/被重开分别记录 none / reset）
#   status.txt     设备/模块/权限/相机进程概览
#   camera-log.txt 关键日志（含 avc denied / linker / CHI 报错）
MODDIR=${0%/*}
MODID=$(basename "$MODDIR")
d="$MODDIR/diagnostics"
mkdir -p "$d"
chmod 0700 "$d"

# 1) 模块完整性（清单已排除安装期文件，正常应全部 OK）
#    注意：清单若带 CRLF，某些 sha256sum 实现会把 \r 当文件名的一部分 —— 这里先做归一化
( cd "$MODDIR" && tr -d '\r' < SHA256SUMS > "$d/SHA256SUMS.lf" && sha256sum -c "$d/SHA256SUMS.lf" ) > "$d/integrity.txt" 2>&1
ok=$(grep -c ': OK$' "$d/integrity.txt" 2>/dev/null)
bad=$(grep -v ': OK$' "$d/integrity.txt" 2>/dev/null | grep -c .)
printf '%s\n' "$ok" > "$d/integrity-count.txt"
printf '%s\n' "$bad" > "$d/integrity-fail.txt"

# 2) 生效哈希 + 与期望值比对
EXP_APK=5e1816cf68ff281985ebec710a5205009e24fec0f4a4b3b0b270dd897cc0c14a
EXP_HAL=240610b0bcb05d0d8d39d799fa1fc27dde8dbf1ede38fb87baa9f834ae5dbebc
got_apk=$(sha256sum /system/priv-app/MiuiCamera/MiuiCamera.apk 2>/dev/null | awk '{print $1}')
got_hal=$(sha256sum /vendor/lib64/hw/camera.qcom.so 2>/dev/null | awk '{print $1}')
apk_ok=NO; hal_ok=NO
[ "$got_apk" = "$EXP_APK" ] && apk_ok=YES
[ "$got_hal" = "$EXP_HAL" ] && hal_ok=YES
{
  echo "# 期望 / 实测（YES = 与 payload 一致）"
  printf 'APK  expect=%s\n     got=%s  match=%s\n' "$EXP_APK" "${got_apk:-<none>}" "$apk_ok"
  printf 'HAL  expect=%s\n     got=%s  match=%s\n' "$EXP_HAL" "${got_hal:-<none>}" "$hal_ok"
  echo "--- 相关库 ---"
  sha256sum /system/lib64/libcamera_algoup_jni.xiaomi.so 2>&1
  sha256sum /system/lib64/libcamera_mianode_jni.xiaomi.so 2>&1
  sha256sum /system/lib64/libgui_shim_miuicamera.so 2>&1
} > "$d/hashes.txt" 2>&1

# 2b) metamodule / overlay 是否真的挂上（相机没生效时先看这里）
{
  echo "--- metamodule ---"
  ls -l /data/adb/metamodule 2>&1
  echo "--- overlay 挂载（应包含本模块目录）---"
  mount 2>/dev/null | grep 'KSU on /system' || echo "未发现 KSU /system overlay"
  echo "--- provider / cameraserver ---"
  prov_pid=$(getprop init.svc_debug_pid.vendor.camera-provider-2-7)
  [ -n "$prov_pid" ] || prov_pid=$(ps -A 2>/dev/null | grep -m1 'camera.provider' | awk '{print $2}')
  if [ -n "$prov_pid" ]; then echo "provider pid=$prov_pid"; else echo "provider 未运行"; fi
  cs_pid=$(pidof cameraserver 2>/dev/null)
  if [ -n "$cs_pid" ]; then echo "cameraserver pid=$cs_pid"; else echo "cameraserver 未运行"; fi
} > "$d/overlay.txt" 2>&1
ovl_ok=NO
grep -q "mnt/$MODID/system" "$d/overlay.txt" && ovl_ok=YES

# 3) 预览帧率采样（3 秒）
sampl() {
  # 取所有 "Frames produced" 的最大值：活跃预览流的计数一定最高且持续增长，
  # 这样不会抓到辅助流/已关闭会话的旧计数
  dumpsys media.camera 2>/dev/null | sed -n 's/.*Frames produced: *\([0-9][0-9]*\).*/\1/p' | sort -n | tail -1
}
f1=$(sampl)
sleep 3
f2=$(sampl)
if [ -z "$f1" ] || [ -z "$f2" ]; then
  printf 'none（相机未在运行或拿不到预览流；先打开相机再点一次 Action）\n' > "$d/fps.txt"
elif [ "$f2" -lt "$f1" ]; then
  printf 'reset（采样期间相机被切换/重开：%s -> %s）\n' "$f1" "$f2" > "$d/fps.txt"
else
  delta=$((f2 - f1))
  printf 'frames %s -> %s in 3s (delta %s, ~%s fps)\n' "$f1" "$f2" "$delta" "$((delta / 3))" > "$d/fps.txt"
fi

# 4) 设备 / 模块 / 权限 / 进程概览
{
  date
  echo "--- props ---"
  getprop ro.product.device
  getprop ro.build.version.sdk
  getprop ro.build.fingerprint
  getenforce
  echo "--- module ---"
  cat "$MODDIR/module.prop"
  echo "--- pm path ---"
  pm path com.android.camera 2>&1
  echo "--- granted (camera) ---"
  dumpsys package com.android.camera 2>/dev/null | grep -E 'android.permission.(CAMERA|RECORD_AUDIO|READ_MEDIA_IMAGES|READ_MEDIA_VIDEO|READ_MEDIA_AUDIO): granted'
  echo "--- processes ---"
  ps -AZ 2>/dev/null | grep -E 'com.android.camera|camera.provider|cameraserver'
} > "$d/status.txt" 2>&1

# 5) 关键日志
logcat -b crash -d -t 200 > "$d/crash.txt" 2>&1
logcat -b all -d -t 4000 2>/dev/null | grep -iE 'com.android.camera|miuicamera|campostproc|mianode|algoup|avc: denied|linker|CameraService|CameraProvider|Invalid logical camera' > "$d/camera-log.txt" 2>&1

chmod 0600 "$d"/*.txt 2>/dev/null
echo "自检完成：$d"
echo "  integrity: $(grep -c ': OK$' "$d/integrity.txt" 2>/dev/null) OK / $(grep -v ': OK$' "$d/integrity.txt" 2>/dev/null | grep -c .) 异常"
echo "  apk/hal : apk=$apk_ok hal=$hal_ok"
echo "  overlay : $ovl_ok"
echo "  fps: $(cat "$d/fps.txt" 2>/dev/null)"
echo "  报告目录: $d"