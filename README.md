# AviumUI 小米相机模块（thor）

Xiaomi 12S Ultra（`thor`）/ Android 16 (API 36) 的 MIUI 相机移植模块（KernelSU + meta-overlayfs）。

**模块脚本、SELinux 策略、权限与属性文件、自检与打包流程均由本项目自行维护**；
相机 APK 与相机相关库沿用 **GSQ2004 / thor-miuicamera v0.1.7** 为 Android 16 适配并重签的产物。
（官方原签名 APK 是上游的输入材料，在 A16 上无法出预览 —— 缺 `ZoomMapBridge`，已用 A/B 实验证实。）

- 当前模块：`avium_miuicamera_thor22` / `1.7.7-avium`（versionCode 67）
- 相机 APK：`5e1816cf…`（上游重签版）；HAL：`240610b0…`（由本机原厂 `26adcce…` 打补丁）
- 实测：预览约 17 fps、拍照 3072×4096 出片约 3.1 MB、4K30 / 8K / 超级防抖 / 专业模式可用
- 发布包与校验值见 [Releases](../../releases) 与 `RELEASE.txt`

## 目录结构
```
├── module.prop                    模块信息（必须无 BOM）
├── customize.sh                   安装逻辑（metamodule 守卫 / 环境校验 / 落位权限 / 域映射准备）
├── prepare.sh                     生成相机域映射（plat_seapp_contexts 模块内副本）
├── post-fs-data.sh                zygote 前刷新域映射
├── service.sh                     开机后等包就绪再自动授权运行时权限
├── action.sh                      一键自检 + 收集诊断（管理器「操作」按钮）
├── sepolicy.rule                  应用侧 SELinux 规则
├── system.prop                    MIUI 标识 + privapp 白名单兜底
├── build.ps1 / build.sh           打包（7-Zip + LF 写出的 SHA256SUMS）
├── verify*.ps1 / release-check.ps1  真机验证脚本
├── INSTALL-CN.md                  刷入说明（随包分发）
├── STATUS.md                      开发状态 / 优化记录 / 已知问题
├── CREDITS.md                     致谢与 payload 出处
└── payload/                       ← 不入库，需自行从上游获取（见下）
    ├── system/priv-app/MiuiCamera/MiuiCamera.apk
    ├── system/lib64/              algoup/mianode JNI、campostproc 客户端、gui shim
    ├── system/vendor/lib64/hw/camera.qcom.so
    ├── system/vendor/lib64/libmis_plugin_vidhance.so
    ├── system/product/etc/device_features/thor.xml
    ├── system/product/overlay/MiuiCameraOverlayLeicaed/…
    └── system_ext/framework/miui-cameraopt.jar
```

## payload 出处
| 文件 | 出处 |
|---|---|
| MiuiCamera.apk | Xiaomi 官方 ROM + **GSQ2004/thor-miuicamera v0.1.7 的 A16 适配重签版** |
| libcamera_algoup_jni / mianode / libgui_shim | Xiaomi 官方 + 上游 ABI 补丁 |
| libmicampostproc_client / campostproc@1.0 | Xiaomi 官方 + 上游适配 |
| camera.qcom.so（`240610b0`） | 本机原厂 vendor `26adcce…` + 上游补丁 |
| libmis_plugin_vidhance / thor.xml / Leica overlay / miui-cameraopt.jar | Xiaomi 官方 ROM（随上游模块分发） |

> **仓库不含 payload**（体积 + 权利归属都在上游）。要自行构建：从上游
> [GSQ2004/thor-miuicamera](https://github.com/GSQ2004/thor-miuicamera) 取 v0.1.7 的模块 zip，
> 解出 `system/`、`system_ext/`、`product/`、`vendor/` 到本仓库 `payload/` 下即可；
> 或直接用 [Releases](../../releases) 里已打好的包。

## 打包 / 部署（Windows，无需 WSL）
```powershell
.\build.ps1
adb push .\avium_miuicamera_thor-1.7.7-avium.zip /data/local/tmp/avium_cam.zip
adb shell "/data/adb/ksud module install /data/local/tmp/avium_cam.zip"
# 换 payload 内容务必换新模块 id，并清掉旧镜像目录：
adb shell "rm -rf /data/adb/modules/meta-overlayfs/mnt/<旧id>"
adb reboot
```

## 验证
优先用设备端自检（KernelSU 管理器 → 模块 → 操作），会在模块目录生成 `diagnostics/`：
`integrity.txt`（`sha256sum -c`，应全 OK）、`hashes.txt`（APK/HAL 与期望值比对）、
`overlay.txt`（挂载 + provider/cameraserver）、`fps.txt`（预览帧率）、`crash.txt`。

手动验证要点：
```powershell
adb shell "sha256sum /system/priv-app/MiuiCamera/MiuiCamera.apk"   # 应等于 payload APK 哈希
adb shell "dumpsys media.camera | grep -E 'Frames produced'"       # 预览流应持续增长
adb shell "am start -n com.android.camera/.Camera"                 # 然后点快门，看 DCIM 里新文件大小
```

> ⚠️ **不要用 `input keyevent 27` 当快门** —— 那是录像键，会直接把相机界面关掉，看起来像崩溃。
> 用 `input tap <快门坐标>` 或直接手点。

> 若取景全黑且 `dumpsys media.camera` 显示 `Frames produced: 0`，几乎必然是 payload 被换成了
> 官方原签名 APK（缺预览桥 `ZoomMapBridge`）。

## 已知问题
**慢动作**（模式 id `0xac`）会让 `camera-provider` 在 `libSNPE.so` 内 SIGSEGV、cameraserver 重启。
已确认本机官方 stock HAL（`26adcce`）同样崩溃 → 非本模块 payload 引入；配置类手段（`vsquality`、
关 AI/美颜/HDR、`resetprop` 各算法开关）与纯 prefs 隐藏入口均无效。真修需改 APK 或 provider/`libSNPE` 二进制。