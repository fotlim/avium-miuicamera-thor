#!/system/bin/sh
# post-fs-data：在 zygote 之前刷新相机域映射（rom 升级后也保持一致）
MODDIR=${0%/*}
. "$MODDIR/prepare.sh"
if ! prepare_camera_contexts "$MODDIR"; then
  printf '%s\n' 'AviumUI camera: 刷新域映射失败，请停用模块并重启' > "$MODDIR/prepare-error.log"
fi
