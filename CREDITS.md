# CREDITS / 来源声明

本模块（AviumUI Xiaomi Camera for thor）由 **AviumUI** 打包与维护：
`module.prop`、`customize.sh`、`prepare.sh`、`post-fs-data.sh`、`service.sh`、`action.sh`、
`sepolicy.rule`、`system.prop`、priv-app 权限清单、hiddenapi/default-permissions 配置、
`build.ps1` 等脚本与策略均为 AviumUI 自行编写。

## 为什么 payload 里不是「官方原签名 APK」

上游项目 **GSQ2004 / thor-miuicamera**（<https://github.com/GSQ2004/thor-miuicamera>，v0.1.7）
把 Xiaomi 官方原签名 MiuiCamera（`sha256 = dfb0c5fe…`）**当作输入材料**，
必须打补丁后才能跑在 Android 16/17 类原生系统上，补丁包括：

- 补齐新版 `CaptureResultExtras` 接口（首次权限流程、图库跳转）；
- 修补应用端 JNI 的 libgui ABI 差异并补入兼容 shim；
- 用 ImageReader / ImageWriter 桥接保留原始尺寸辅助流（长焦取景小窗）；
- 相应 HAL 补丁与 Vidhance MIS 插件。

改 APK 就必然重签，因此**本模块的相机 APK 用的是上游产出（重签版），不是官方原签名版**。
官方原签名 APK 在 A16 上无法出预览（实机 A/B 已证实，详见
`rom\devtree\final\MiuiCamera_CTA与黑屏_根因调查_2026-11-17.md`）。
上游 `sources.json` 自身即记录：`input_apk_sha256 = dfb0c5fe…`、
`input_apk_version_code = 610006100` → `output_apk_version_code = 610006107`。

## 第三方组件与出处

| 组件 | 出处 / 作者 | 说明 |
|---|---|---|
| `MiuiCamera.apk`（`5e1816cf…`） | **Xiaomi（小米）** 官方 ROM 提取，经 **GSQ2004 / thor-miuicamera v0.1.7** 为 Android 16/17 适配并重签（签名 `CN=Thor Camera Development`） | 官方原签名输入件 `dfb0c5fe…` 见 `rom\official\off2\prod\MiuiCamera.apk` |
| `libcamera_algoup_jni.xiaomi.so`、`libcamera_mianode_jni.xiaomi.so` | Xiaomi 官方 ROM（system_ext/lib64）；由 **GSQ2004 / thor-miuicamera v0.1.7** 修补 ABI 差异 | 原厂输入件 `d879481f…` / `b08f787c…` |
| `camera.qcom.so`（`240610b0…`） | Xiaomi 官方 vendor HAL（`26adcce…`）经 **GSQ2004 / thor-miuicamera v0.1.7** 打补丁（含 ISPv3 电源命令修正） | 本机底层 vendor HAL 实测即 `26adcce…` |
| `libmicampostproc_client.so`、`vendor.xiaomi.hardware.campostproc@1.0.so` | Xiaomi 官方 ROM；**GSQ2004** 做过适配修改 | 原厂输入件 `7a69c561…` / `924566bd…` |
| `libgui_shim_miuicamera.so` | **GSQ2004 / thor-miuicamera v0.1.7**（2.3KB 符号桩，补 A16 缺失的 `BnProducerListener::onBufferDetached`） | |
| `libhidltransport.so` / `libhwbinder.so` | Xiaomi 官方 ROM（system/lib64，空壳桩） | 仅满足 dynstr 依赖 |
| `libmis_plugin_vidhance.so` | Xiaomi 官方 vendor；随 **GSQ2004** 模块分发 | |
| `miui-cameraopt.jar` | Xiaomi 官方 ROM（system_ext/framework，225KB 原件） | |
| `thor.xml`（device_features）、`MiuiCameraOverlayLeicaed.apk` | Xiaomi 官方 ROM / **GSQ2004** 适配 | |
| `libmialgoengine.so` 等 vendor 算法库 | Xiaomi 官方 vendor（由 ROM 自身提供） | |
| `meta-overlayfs`（运行依赖，非本模块内容） | KernelSU-Modules-Repo | MIT/GPL 见其仓库 |

## 备注
- 本模块为**非官方移植**，与 Xiaomi / Leica / 上游作者均无隶属关系；所有小米版权文件版权归 Xiaomi 所有。
- 上游项目及其产物的许可与归属见其仓库 `NOTICE.md`；若上游作者（GSQ2004 / thor-miuicamera）有异议，可联系移除对应文件。