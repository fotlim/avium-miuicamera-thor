#!/system/bin/sh
# 生成「相机应用 → platform_app 域」的 SELinux 映射（模块内副本）
# 思路：保留 ROM 原有所有映射，仅追加一条 com.android.camera 的精确匹配。
# 说明：本机 selinux 没有 platform_app_36 类型，统一用 platform_app。

prepare_camera_contexts() {
  moddir=$1
  src=${2:-/system/etc/selinux/plat_seapp_contexts}
  out="$moddir/system/etc/selinux/plat_seapp_contexts"

  [ -r "$src" ] || return 1

  case "$(getprop ro.build.version.sdk)" in
    36|37) domain=platform_app ;;
    *) return 1 ;;
  esac

  # 前置条件：目标域必须在本机策略里存在
  grep -Eq "domain=$domain([[:space:]]|$)" "$src" || return 1

  mkdir -p "$moddir/system/etc/selinux"

  # 先剔除旧的 camera 行（支持重复安装），再追加唯一一条
  awk '!/name=com[.]android[.]camera([[:space:]]|$)/' "$src" > "$out.tmp" || return 1
  printf '\nuser=_app seinfo=default isPrivApp=true name=com.android.camera domain=%s type=app_data_file levelFrom=user\n' \
    "$domain" >> "$out.tmp" || return 1
  chmod 0644 "$out.tmp" || return 1

  # 继承原文件的 SELinux 标签，避免 setcontext 失败导致开机异常
  label=$(ls -Zd "$src" 2>/dev/null | awk '{print $1}')
  case "$label" in
    u:object_r:*:s0) chcon "$label" "$out.tmp" 2>/dev/null ;;
  esac

  mv -f "$out.tmp" "$out" || return 1
  return 0
}
