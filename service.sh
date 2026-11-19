#!/system/bin/sh
# service.sh：开机后按需重启 camera provider；并自动授予相机运行时权限
MODDIR=${0%/*}

# 等开机完成
n=0
while [ "$(getprop sys.boot_completed)" != 1 ] && [ $n -lt 150 ]; do
  sleep 2
  n=$((n + 1))
done

# 再等 PMS 真正可用：开机早期 `pm` 会报
#   cmd: Failure calling service package: Failed transaction (2147483646)
pkg_ok=0
n=0
while [ $n -lt 60 ]; do
  if pm path com.android.camera >/dev/null 2>&1; then
    pkg_ok=1
    break
  fi
  sleep 2
  n=$((n + 1))
done

hal=/vendor/lib64/hw/camera.qcom.so
pid=$(getprop init.svc_debug_pid.vendor.camera-provider-2-7)
want=$(stat -c %i "$hal" 2>/dev/null)
got=$(grep " $hal\$" "/proc/$pid/maps" 2>/dev/null | head -n1 | awk '{print $5}')

if [ -n "$want" ] && [ -n "$got" ] && [ "$want" != "$got" ]; then
  setprop ctl.restart vendor.camera-provider-2-7
  setprop ctl.restart cameraserver
  printf 'restarted camera provider (mapped inode %s -> %s)\n' "$got" "$want" > "$MODDIR/reload.log"
fi

# 自动授予运行时权限（系统应用升级后权限会被重置）
# 相机 o7/d->b()（isCameraLaunchPermissions）只认这几项：
#   CAMERA / READ_MEDIA_IMAGES / READ_MEDIA_VIDEO / READ_MEDIA_AUDIO / RECORD_AUDIO
granted=0
denied=0
if [ "$pkg_ok" = 1 ]; then
  for p in CAMERA RECORD_AUDIO READ_MEDIA_IMAGES READ_MEDIA_VIDEO READ_MEDIA_AUDIO \
           READ_MEDIA_VISUAL_USER_SELECTED ACCESS_MEDIA_LOCATION ACCESS_FINE_LOCATION \
           ACCESS_COARSE_LOCATION POST_NOTIFICATIONS; do
    if pm grant com.android.camera "android.permission.$p" 2>/dev/null; then
      granted=$((granted + 1))
    else
      denied=$((denied + 1))
    fi
  done
fi

{
  date
  printf 'device=%s api=%s\n' "$(getprop ro.product.device)" "$(getprop ro.build.version.sdk)"
  printf 'pms_ready=%s grants_ok=%s grants_failed=%s\n' "$pkg_ok" "$granted" "$denied"
  printf 'hal_inode=%s provider_inode=%s\n' "$want" "$got"
  pm path com.android.camera 2>&1
  getenforce
  ls -lZ /system/priv-app/MiuiCamera/MiuiCamera.apk 2>&1
} > "$MODDIR/startup.log" 2>&1