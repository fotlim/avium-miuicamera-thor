#!/bin/bash
# AviumUI 小米相机模块 —— 打包脚本（我们自己的）
# 用法: ./build.sh [payload 目录]
#   payload 目录需包含: system/priv-app/MiuiCamera/MiuiCamera.apk 等（见 README）
# 产物: avium_miuicamera_thor-<version>.zip
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
PAYLOAD=${1:-$HERE/payload}
VER=$(grep -m1 '^version=' "$HERE/module.prop" | cut -d= -f2)
OUT="$HERE/avium_miuicamera_thor-${VER}.zip"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# 1) 先拷入骨架（脚本/策略/属性）
cp -a "$HERE"/module.prop "$HERE"/customize.sh "$HERE"/prepare.sh \
      "$HERE"/post-fs-data.sh "$HERE"/service.sh "$HERE"/action.sh \
      "$HERE"/sepolicy.rule "$HERE"/system.prop "$WORK"/

# 2) 合并 system/ 树：骨架自带 etc/permissions 等，payload 补充 APK/库
mkdir -p "$WORK/system"
if [ -d "$HERE/system" ]; then cp -a "$HERE/system/." "$WORK/system/"; fi
if [ -d "$PAYLOAD/system" ]; then cp -a "$PAYLOAD/system/." "$WORK/system/"; fi

# 3) 必检项
need="system/priv-app/MiuiCamera/MiuiCamera.apk"
if [ ! -s "$WORK/$need" ]; then echo "缺少 $need（payload 未提供）" >&2; exit 2; fi

# 4) 归档校验（信息用，不做安装期硬校验）
(cd "$WORK" && find . -type f ! -name SHA256SUMS -printf '%P\n' | sort > /tmp/_fl.txt
 while IFS= read -r f; do sha256sum "$f"; done < /tmp/_fl.txt > SHA256SUMS)

# 5) 打包
rm -f "$OUT"
( cd "$WORK" && zip -qr9 "$OUT" . -x '*.log' )
echo "OK: $OUT"
ls -l "$OUT"
