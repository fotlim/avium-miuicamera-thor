#!/system/bin/sh
# AviumUI 小米相机模块 —— 安装脚本（由 AviumUI 自行维护）
# 由 KernelSU/Magisk 的安装器 source 执行。

[ "$BOOTMODE" = true ] || abort '请在系统启动后从 KernelSU/Magisk 管理器安装'
[ "$ARCH" = arm64 ] || abort '仅支持 arm64'
[ "$(getprop ro.product.device)" = thor ] || abort '仅适用于 Xiaomi 12S Ultra (thor)'

api=$(getprop ro.build.version.sdk)
case "$api" in
  36|37) ;;
  *) abort "仅支持 Android 16/17 (API 36/37)，当前 API=$api" ;;
esac

ui_print '- AviumUI 小米相机移植模块'
[ -s "$MODPATH/system/priv-app/MiuiCamera/MiuiCamera.apk" ] || abort '缺少 MiuiCamera.apk（payload 未放入）'

# metamodule 守卫：KernelSU 3.x 没有 meta-overlayfs 时，本模块的 /system、/vendor 内容根本不会被挂载，
# 装了也"看起来成功但相机没变化"。这里直接中止并给出明确指引。
if [ ! -e /data/adb/metamodule ]; then
  ui_print '! 未检测到生效的 metamodule'
  ui_print '! KernelSU 3.x 必须先安装 meta-overlayfs（OverlayFS MetaModule），重启后再装本模块'
  ui_print '! 否则模块内容不会被挂载到 /system 与 /vendor（装了等于没装）'
  abort '缺少 meta-overlayfs metamodule，请先安装它并重启'
fi
ui_print "- metamodule: $(ls -l /data/adb/metamodule 2>/dev/null | awk '{print $NF}')"

# 提示：如果镜像里还留着别的相机模块目录，会与本模块抢同一路径
stale=$(ls -1 /data/adb/modules/meta-overlayfs/mnt/ 2>/dev/null | grep -E '^.?avium_miuicamera_thor[0-9]+$' | grep -vx "$(basename "$MODPATH")")
if [ -n "$stale" ]; then
  ui_print '! 检测到镜像里还有其它相机模块目录（可能与本模块冲突）：'
  printf '%s\n' "$stale" | while read -r d; do ui_print "    mnt/$d"; done
  ui_print '! 建议卸载旧模块并删除这些目录后重启'
fi

# 与应用安装冲突检查
existing=$(pm path com.android.camera 2>/dev/null)
case "$existing" in
  '' ) ;;
  package:/system/priv-app/MiuiCamera/MiuiCamera.apk) ;;
  *) abort "com.android.camera 已存在且不是本模块：$existing" ;;
esac

# 记录本机信息，方便排查
{
  printf 'installed_at=%s\n' "$(date)"
  printf 'device=%s\napi=%s\n' "$(getprop ro.product.device)" "$api"
  printf 'rom=%s\n' "$(getprop ro.build.fingerprint)"
  sha256sum "$MODPATH/system/priv-app/MiuiCamera/MiuiCamera.apk"
  sha256sum "$MODPATH/system/vendor/lib64/hw/camera.qcom.so" 2>/dev/null
} > "$MODPATH/install-info.txt" 2>&1

# 权限：目录 0755 / 文件 0644，脚本 0755
set_perm_recursive "$MODPATH" 0 0 0755 0644
for s in post-fs-data.sh service.sh action.sh prepare.sh; do
  [ -f "$MODPATH/$s" ] && set_perm "$MODPATH/$s" 0 0 0755
done

# 给 vendor 侧 HAL/插件打 vendor_file 标签（否则 linker 拒绝加载）
chcon u:object_r:vendor_file:s0 "$MODPATH/system/vendor/lib64/hw/camera.qcom.so" 2>/dev/null
chcon u:object_r:vendor_file:s0 "$MODPATH/system/vendor/lib64/libmis_plugin_vidhance.so" 2>/dev/null

# 生成相机应用的 SELinux 域映射（plat_seapp_contexts 的模块内副本）
if ! . "$MODPATH/prepare.sh" || ! prepare_camera_contexts "$MODPATH"; then
  ui_print '! 无法准备相机域映射，开机后相机可能无法启动'
fi

# privapp 白名单属性
prop="$MODPATH/system.prop"
if ! grep -q 'persist.vendor.camera.privapp.list' "$prop" 2>/dev/null; then
  printf '\npersist.vendor.camera.privapp.list=com.android.camera\n' >> "$prop"
fi

ui_print '- 安装完成，重启后使用'
ui_print '- 若相机图标未出现或闪退，请用 action.sh 收集日志'
