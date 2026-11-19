# AviumUI 小米相机模块 — 当前状态（2026-11-17 夜，定稿）

## 一句话
模块 **`avium_miuicamera_thor20` / `1.5.0-avium`** 已定稿并装机可用；
「官方原签名 APK 原样可用」经实机 A/B 与上游仓库证据判定**不可行**（详见
`rom\devtree\final\MiuiCamera_CTA与黑屏_根因调查_2026-11-17.md`）。

## 实机结论（本轮）
| 项 | 结果 |
|---|---|
| 预览 | 正常（`dumpsys media.camera` 见到 229~282 帧持续增长） |
| 拍照 | 正常，`IMG_20261117_225556.jpg` = 2,689,638 B |
| 录像/8K | 本轮未重测（沿用交接文档 1.2.5 的验证结论） |
| crash | buffer 为空 |
| CTA | 不弹（上游重签 APK 已修；本轮额外做的 `cta-seed.sh` 已按用户要求移除） |

## payload（= 上游 GSQ2004/thor-miuicamera v0.1.7 的 Android 16 适配产物）
- `MiuiCamera.apk` = `5e1816cf…`（官方原签名 `dfb0c5fe…` 是上游**输入材料**，A16 上无法出预览）
- `camera.qcom.so` = `240610b0…`（由本机原厂 vendor `26adcce…` 打补丁；本机底层 HAL 实测即 `26adcce…`）
- `libcamera_algoup_jni` / `mianode` = 上游 ABI 补丁版；`libgui_shim_miuicamera.so` 补 A16 缺符号
- `libmicampostproc_client` / `campostproc@1.0` / `miui-cameraopt.jar` / `thor.xml` / Leica overlay

## 我们自写的部分
`module.prop`、`customize.sh`、`prepare.sh`、`post-fs-data.sh`、`service.sh`、`action.sh`、
`sepolicy.rule`、`system.prop`、privapp/hiddenapi/default-permissions 配置、`build.ps1`。

## 部署
```powershell
& F:\thor\rom\avium-miuicamera\build.ps1
adb push <zip> /data/local/tmp/avium_cam.zip
adb shell "/data/adb/ksud module install /data/local/tmp/avium_cam.zip"
adb reboot
```
> 换 payload 内容必须换新模块 id；改脚本不用换，但镜像小（2GB）时记得清
> `/data/adb/modules/meta-overlayfs/mnt/<旧id>`。本轮已把 16/17/18/19 清掉，镜像占用 99% → 60%。

## 遗留 TODO
1. `service.sh` 开机 `pm grant` 可能因 PMS 未就绪失败 → 加「等 `pm path com.android.camera` 成功」重试。
2. 取景右下角蓝色残影（交接文档 §13-3）未复查。
3. 上游已核对组合为 crDroid A16 / LOS 24；本机 `libgui.so` 哈希不同（未核对组合），实测可用但非官方验证范围。
---

## 更新（2026-11-18 上午）
- 模块升级到 **1.5.1-avium**：`service.sh` 增加「等 PMS 就绪再 `pm grant`」重试；
  实测 `startup.log` → `pms_ready=1 grants_ok=10 grants_failed=0`。
- 取景**蓝条残影不复现**（像素分析：取景区最大偏蓝度 1.3、底部 0.8）→ 该项关闭。
- 复测：预览 133 帧、拍照 `IMG_20261118_094904.jpg` = 2,295,285 B，正常。
- 剩余 TODO：仅第 3 项（本机 libgui 属上游未核对组合，实测可用）。
## 与开发者（上游 v0.1.7）对比（2026-11-18）
- **payload 与上游 zip 逐字节同源**（APK / 两 JNI / gui_shim / campostproc 客户端与服务 / HAL 240610b0 /
  Vidhance / thor.xml / Leica overlay 全部哈希一致）；我们仅额外补 `libhidltransport.so`、`libhwbinder.so`
  两个空壳（满足依赖）和 `system_ext/framework/miui-cameraopt.jar`（修 CameraOptManager ClassNotFound）。
- 本机实测：冷启动 425–436ms；HAL 自报预览 **24.95 fps**；拍照 **3072×4096 / 2.3–3.0 MB**；crash buffer 空。
- 待复测：录像 / 8K / 超级防抖 / 高倍率取景小窗（payload 与上游相同，但本机尚未逐一验证）。
- 排查提醒：USB 选项弹窗、权限弹窗、其它应用通知弹窗抢焦点时，相机会 `onPause` → 停帧 →
  最终走错误页退出（日志 `CameraExitHintDialogFragment` / `wm_finish_activity app-request`）。测相机前先清场。
## 四项补测进度（2026-11-18 上午，thor20 / 1.5.1）
| 项目 | 结果 |
|---|---|
| 预览 | ✅ HAL 自报 `preview fps is 24.950100`；24 秒前台探针全程稳定 |
| 拍照 | ✅ 3072×4096 / 2,295,285 B |
| **普通录像（4K30）** | ✅ `VID_20261118_104016.mp4` = 47,548,781 B（约 6 秒，4K·30 档） |
| 8K 录像 | ⬜ 未测（需进分辨率菜单，UI 自动化易触发 pause） |
| 超级防抖 / PRO | ⬜ 未测（需模式内二级菜单） |
| 高倍率辅助取景小窗 | ⬜ 未测（需多点手势放大到 ~96×，`adb input` 无法 pinch；建议人工验证） |

### 重要行为特征（排查必读）
MiuiCamera **一旦 Activity 进入 pause 就会自行退出**（日志见
`CameraExitHintDialogFragment.showErrorScreen` → `Camera.finish()`，events 里是
`wm_finish_activity ... app-request`）。所以任何抢焦点的东西——USB 选项弹窗、权限弹窗、
其它应用通知弹窗、甚至一次误触打开别的 App——都会让相机"几秒后自己退出"。
测试时：先 `svc power stayon true`、点掉弹窗、只在相机 UI 内做单次点按，每次交互后重新核对前台。
## 补测更新（2026-11-18 10:47）
| 项目 | 结果 |
|---|---|
| **8K 录像** | ✅ `VID_20261118_104700_8K.mp4` = **81,684,742 B**（约 5 秒，界面显示 `8K · 24`） |
| 普通录像 4K30 | ✅ `VID_20261118_104016.mp4` = 47,548,781 B（约 6 秒，`4K · 30`） |
| 拍照 | ✅ 3072×4096 / 2,295,285 B |
| 预览 | ✅ HAL 自报 24.95 fps；24 秒前台探针稳定 |
| 超级防抖 / PRO | ⬜ 未测（需模式内二级菜单，下一步试） |
| 高倍率辅助取景小窗 | ⬜ 未验证：本轮借变焦条上推到 5× 时 `dumpsys` 里仍无 408×306 级辅助流；上游记录是 ~96× 才出现，需**人工双指放大**后再查流表 |

### 录像分辨率菜单坐标（复用）
录像模式下点右上角分辨率标签（≈ x=1200, y=260）展开四档：
`720`→x≈179、`1080`→x≈540、`4K`→x≈897、`8K`→x≈1255（均为 y≈260）。
## 补测更新（2026-11-18 10:52）
| 项目 | 结果 |
|---|---|
| **高倍率/辅助取景小窗** | ✅ 已见辅助流：**超级月亮模式 + 5×** 时存在 `ImageReader-408x306f22m4`，与主预览同步出帧（6 秒 103 帧 ≈17 fps），截图右上角可见带白框小窗 —— 即上游 `PRIVATE ImageReader/ImageWriter` 桥接产物 |
| 8K 录像 | ✅ 81,684,742 B（≈5s，`8K·24`） |
| 4K30 录像 | ✅ 47,548,781 B（≈6s，`4K·30`） |
| 拍照 / 预览 | ✅ 3072×4096 / 2.29MB；HAL 24.95fps |
| 超级防抖 / 防抖 PRO | ⬜ 未找到自动入口：`更多模式`面板只有一页 12 项（超清/夜景/慢动作/延时/长曝光/全景/超级月亮/微电影/电影镜头/魔法分身/AI水印/编辑）；8K 与 1080 录像下均未见明显防抖开关 → **需人工在录像模式顶部/设置里点** |

### 自动化操作坑（记录）
- 上滑开"更多模式"面板后，点顶部 chevron (720,140) 关面板**不总生效**；后续点击会落到网格项上
  （本轮两次误入「超级月亮」）。关面板建议：点面板外空白，或再上/下滑一次并截图确认。
- 录像分辨率菜单：右上标签 (x≈1200,y≈260) → `720/1080/4K/8K`（x≈179/540/897/1255, y≈260）。
- 超级月亮模式退出：白胶囊右端 × ≈ (870, 2500)。
## 补测更新（2026-11-18 11:00）
### 视频防抖（EIS）链路已确认在工作
- 录像模式切到 **1080 · 60** 后，HAL 出现 EIS 节点：
  `MultiCameraVideoSATNoGPU0_com.qti.node.eisv314_cam2` / `eisv212_cam2`，
  且 `EISV2 ProcessRequest()` 在最近一次采样中有 **84 条** 日志 → 防抖管线确实在跑。
- 但**应用层「超级防抖 / 防抖 PRO」档位开关未定位**：
  - 顶栏中心 chevron 点开无面板；
  - 顶栏左上是「闪光/EV」而不是防抖；
  - 「更多模式」面板仅一页 12 项，无防抖档。
- 应用字符串池里确实有：`超级防抖`、`超级防抖PRO`、`超级防抖PRO已关闭`、`超级防抖已开启/关闭状态`、
  `视频防抖` → 入口存在，属二级设置。
- 下一步思路：①在**专业(Pro)模式的录像子模式**里找；②用 `aapt dump --values resources` 反查
  `超级防抖` 的 resource id，再在 smali 里定位引用它的 UI 类，从代码侧确定入口控件。
## 1.5.2（2026-11-18 11:06）：修复 SHA256SUMS 误报
- **问题**：装机后 `sha256sum -c SHA256SUMS` 报 `customize.sh`、`README.md` FAILED。
  原因是这两个文件不随安装落地：`customize.sh` 是安装期脚本（KernelSU 装完即删），
  `README.md` 装后亦不保留（实测`/data/adb` 下已无该文件），但被写进了校验清单。
- **修法**：`build.ps1` 生成清单时排除 `SHA256SUMS` / `customize.sh` / `README.md`。
- **验证**：装 1.5.2 后 `SHA256SUMS` 25 条、`sha256sum -c` **0 失败**；
  冷启动 194ms、预览帧持续增长（627 帧在涨）、拍照 `IMG_20261118_110601.jpg` = **2,854,584 B**、
  `Invalid logical camera id` **0 条**、crash buffer 空。
- 端点：`avium_miuicamera_thor-1.5.2-avium.zip`（121,482,847 B）。
## 上游四大卖点全量验证完成（2026-11-18 11:10，thor20 / 1.5.2）
| 项目 | 证据 |
|---|---|
| 预览 | HAL 自报 24.95 fps；1080P60 下帧 772→930（5s，≈31.6 fps） |
| 拍照 | `IMG_20261118_110601.jpg` = 2,854,584 B，3072×4096 |
| 4K30 录像 | `VID_20261118_104016.mp4` = 47,548,781 B（≈6s） |
| 8K 录像 | `VID_20261118_104700_8K.mp4` = 81,684,742 B（≈5s，`8K·24`） |
| 辅助取景小窗 | `ImageReader-408x306f22m4` 与主预览同步出帧（6s 103 帧 ≈17 fps） |
| **超级防抖** | UI 状态 `超级防抖，关闭状态` → **`超级防抖，开启状态`**；预览 ≈31.6 fps |
| **超级防抖 PRO** | UI 状态 → **`超级防抖PRO，开启状态`**；预览 ≈31.8 fps；录制 `VID_20261118_111044.mp4` = 12,498,604 B（≈4s） |

### 防抖入口（自动化坐标，已实测可用）
1. 进 **录像** 模式：模式行 y≈2503，录像 x≈432
2. 点顶部"功能菜单"chevron：**(720, 286)**（无障碍名 `功能菜单：展开/收起`）
3. 面板里点 **超级防抖** 按钮：**(1237, 2052)**（bounds `[1097,1985][1378,2119]`）
4. 出现两档选择：**超级防抖 (720, 2087)** / **超级防抖 PRO (1180, 2087)**
5. 用 `uiautomator dump` 读 `content-desc` 即可判定当前状态（`超级防抖，开启状态` / `…PRO，开启状态`）

> 提示：`uiautomator dump` 是本机型最可靠的 UI 定位手段（比截图猜坐标稳），后续自动化优先用它拿 bounds。
## 1.6.x（2026-11-18 12:23）：A+B 优化 + 与开发者包画质对比

### A. 去掉死重空壳（模块换新 id：thor21）
- 核实：payload 的 `libmicampostproc_client.so` 与 `campostproc@1.0.so` 的 DT_NEEDED **已不含** `libhidltransport/libhwbinder`；
  唯一还依赖 `libhidltransport` 的是 vendor 侧 `camera.qcom.so`，由 **ROM 自带 `/vendor/lib64/libhidltransport.so`（10,752B）** 满足。
- 动作：从 payload 删除 `system/lib64/libhidltransport.so`、`libhwbinder.so`；模块 id 换 **`thor21`**，版本 **1.6.2-avium**。
- 验证：装机后 `/system/lib64` 里已无这两个文件；`verify.ps1` 全绿、CHI 0、crash 0、拍照正常。

### B. `action.sh` 强化（设备端一键自检）
管理器里点「操作」即产出 `$MODDIR/diagnostics/`：
`integrity.txt`（sha256sum -c）、`fps.txt`（3 秒预览帧率）、`hashes.txt`（生效 APK/HAL/JNI）、
`status.txt`（设备/模块/权限/进程）、`camera-log.txt`、`crash.txt`。
实测输出：`integrity: 23 OK / 0 异常`、`fps: frames 168 -> 229 in 3s (delta 61, ~20 fps)`。

### 过程中修掉的两个真问题
1. **`SHA256SUMS` 是 CRLF** → 设备端某些 `sha256sum` 实现把 `\r` 当文件名一部分，`-c` 全 FAIL。
   修：`build.ps1` 改写为 **LF**；`action.sh` 里再做一次 `tr -d '\r'` 归一化兜底。（zip 内实测 CRLF=0）
2. **action 的 fps 取样抓错流**（曾出现 `791 -> 1` / `113 -> 113`）→ 改为取 dump 中所有 `Frames produced` 的**最大值**再求差，
   并对"相机未运行 / 采样期间被重开"分别给出 none / reset 提示。

### 与开发者包（GSQ2004 v0.1.7）画质对比（同 APK、同 JNI，仅 HAL 补丁不同）
同一机位、拍照 1×、每组 3 张（3072×4096）：

| 组 | HAL | 字节均值 | 清晰度(Laplacian方差) | 亮度 | 对比度 | 色彩 | 归一化清晰度 |
|---|---|---|---|---|---|---|---|
| **本机配置** | `240610b0`（由其 android17 档、针对本机 vendor `26adcce` 打补丁） | 3,151,845 | **114.8** | **109.9** | **47.7** | **16.5** | **0.0503** |
| 开发者包 A16 档 | `900dfb00`（针对 crDroid 的 vendor 补丁） | 3,078,139 | 95.9 | 98.5 | 45.2 | 14.2 | 0.0469 |
| 差异 | | +2.4% | **+19.7%** | +11.5% | +5.5% | +16.2% | **+7.4%** |

结论：**本机应继续用 `240610b0`**（它是用本机原厂 vendor HAL 打的补丁）。即使消除亮度/对比度影响后，归一化清晰度仍高 7.4%。
注意：亮度差 11.5% 说明两组 AE 曲线不同，清晰度优势里有一部分来自亮度；但结论与交接文档的 8 组 A/B 一致。

原始样张与计算脚本：`F:\thor\rom\tests\quality\`（`hal240610b0/`、`hal900dfb00/`、`qcmp.py`、`qcmp2.py`）。
## 自动化工具集（2026-11-18 12:30）
| 脚本 | 作用 | 实跑结果 |
|---|---|---|
| `verify.ps1` | 11 项基础验证：完整性 / 生效哈希 / 冷启动 / 前台 / 预览 fps / 拍照 / CHI / crash | 全绿（1.6.2） |
| **`verify-features.ps1`** | 四项功能矩阵：拍照 / 4K30 / 8K / 超级防抖 + PRO，全部用 `uiautomator` 的 `content-desc` 定位并断言 | 全绿（见下） |

**verify-features.ps1 实跑（12:30）**
```
相机启动        461 ms
拍照出片        IMG_20261118_123019.jpg = 3,025,537 B
切到 4K         分辨率,4K
4K30 录像       VID_20261118_123055.mp4 = 46,733,204 B
切到 8K         分辨率,8K
8K 录像         VID_20261118_123124_8K.mp4 = 78,244,111 B
超级防抖        已开启
超级防抖 PRO    已开启
复位拍照模式     com.android.camera/.Camera
```
报告：`features_report_20261118_123001.md`

> 工具要点：所有点击坐标都从 UI dump 的 `content-desc`/`text` **实时解析**，不硬编码；
> 分辨率菜单项自带 `分辨率,720P/1080P/4K/8K` 描述，防抖按钮是 `超级防抖，开启/关闭状态`，断言很稳。
> 发布前建议顺序执行：`verify.ps1` → `verify-features.ps1`。
## 「更多模式」12 项巡检 + 慢动作缺陷（2026-11-18 13:03）
新增脚本 **`verify-moremodes.ps1`**（每个模式强制重启相机 → 上滑开面板 → 按 3×4 网格坐标点入 → 判前台/出帧）。

| 模式 | 结果 | 模式 | 结果 |
|---|---|---|---|
| 超清 | OK 22.5 fps | 微电影 | OK 36 fps |
| 夜景 | OK 21.5 fps | 电影镜头 | OK 17 fps |
| **慢动作** | **EXIT（见下）** | 魔法分身 | OK 18.5 fps |
| 延时摄影 | OK 40 fps | AI水印 | OK 19.5 fps |
| 长曝光 | OK 18.5 fps | 编辑 | OK 17 fps |
| 全景 | OK 18.5 fps | | |
| 超级月亮 | OK 20 fps | | |

**结论：11/12 正常。**

### ❗ 慢动作（720·120）不可用 —— 已定位
现象：进入后屏幕提示 **「无法连接到相机，应用将在 2s 后退出，请稍后重试。」**，随后走错误页（`CameraExitHintDialogFragment`）→ `Camera.finish()`。
日志链：
```
E CamX              : configure_streams() FPS: 120 ~ 120
E Camera3-Device    : Camera 8: configureStreamsLocked: Unable to configure streams with HAL: Broken pipe (-32)
E CameraDeviceClient: endConfigure: Camera 8: Error configuring streams: Broken pipe (-32)
E MCAM_MiuiCamera2  : onHighSpeedConfigureFailed: id=1 sessionId=1
E MCAM_CameraDeviceCallbackImpl: onCameraError: camera disabled（error=4）
```
**对照实验**：把 HAL 换回原厂 `26adcce`（`F:\thor\rom\official\stock_camera_qcom_26adcce.so`）后，慢动作**同样失败** →
说明**不是上游 HAL 补丁的问题**，而是高帧率（120fps）会话在这个移植里根本建不起来。
上游 `VALIDATION.md` 也从未验证过慢动作 → 属移植本身的已知缺口。
## 慢动作「最小改动修复」尝试结论（2026-11-18 14:10）
模块回到干净状态：**thor22 / 1.7.1-avium**，验证全绿（照片 3,004,116 B、CHI 0、crash 0）。

### 已试且失败的配置级方案（都无效）
| 尝试 | 做法 | 结果 |
|---|---|---|
| A1 | 给 `/vendor/etc/camera/camxoverridesettings.txt` 的 `vsquality` 追加 `5@120\|5@240\|5@480`（720p 高帧率稳像质量） | ❌ 进慢动作仍 provider SIGSEGV |
| A2 | 关掉视频 AI/增强链路：`isVideoBeautifierSupported=FALSE`、`AIEnhancementVersion=0`、`enableVSR=0`、`iseispreviewSupported=FALSE`、`enableSALINet=0`、`isPreviewZoomEISSupported=0`、`enableNCSService=0`、`enableICAInGrid=0` | ❌ 仍 SIGSEGV |
| A3（更早） | resetprop 关 `aiscene.disable.function` / `aio_seg.isbypass` / `miaideblur.disable_deblur` / `arcsoft.bokeh_video.bypass` / `ellv.bypass.enable` | ❌ 仍 SIGSEGV |

→ **配置层（prop / .txt / device_features）救不了**：进慢动作时 camera provider 在 libSNPE 的线程里踩坏函数指针（`trying to execute non-executable memory`），与 HAL 补丁无关（原厂 `26adcce` 同样崩）。
尝试用的配置文件留档：`F:\thor\rom\devtree\camxcfg\`（stock / ai-off 两份）。

### 剩下可行方向（改动从大到小）
1. **改 APK（我们自己的重签版）**：`SlowMotionModule` / `SlowMotionVideoConfiguration` 把慢动作从「constrained high-speed 会话」改成普通录像 + 后期慢放，或换到不触发 SNPE 的组合 → 中等工作量、需换新 payload id。
2. **修 provider/libSNPE**：给崩溃路径打二进制补丁 → 风险高、收益不确定。
3. **隐藏「慢动作」入口**（最小改动）：从模式列表移除（编辑模式或预置 pref），避免用户误进导致**相机服务重启**（provider 崩溃会重拉 cameraserver，影响其它相机使用）。
## 最终决定：慢动作保持现状（2026-11-18 14:25）
用户决定**不改 APK**，模块维持 **thor22 / 1.7.1-avium**（干净状态：无 camx 配置覆盖、prefs 已还原）。

### 「隐藏慢动作入口」尝试结论（不可行，纯 pref 做不到）
- `pref_camera_sort_modes_key`：删掉 `172`（慢动作）后，网格只是把它**挪到最后一格**，没消失；
- `all_support_mode_list`：一起删掉也没用 —— **app 启动时会自己把 172 重算回完整支持列表**；
- 原因：MIUI 相机的「编辑模式」只支持拖动**排序**，不支持删除；支持集合由代码（模块管理器）决定。
- → 真要隐藏必须改 APK（从模块注册表摘掉 `SlowMotionModule`），用户选择不做。
- 已把 pref 恢复原样（`camera_settings_global.xml` 回滚，列表顺序正常），实测网格 12 项与之前一致。

### 慢动作当前状态（保留为已知缺陷）
进「慢动作（720·120）」→ provider 进程 SIGSEGV（崩在 `libSNPE.so`）→ `Broken pipe (-32)` → 应用错误页
「无法连接到相机，应用将在 2s 后退出」→ 相机退出；**provider 崩溃会让 cameraserver 重拉**，期间其它相机应用也会受影响。
配置层修复已排除（见上文三组尝试），HAL 换原厂同样崩。其余 11 个更多模式 + 5 主模式 + 前置 + 4K30/8K/超级防抖/PRO/辅助小窗 均正常。
## 模块本体优化（1.7.2 → 1.7.7，2026-11-18 15:18）
这一轮改的都是**模块自身**（payload 未变，沿用 thor22 id），不涉及相机功能取舍。

### 1) 装错环境不再"假成功" —— `customize.sh`
- 新增 **metamodule 守卫**：没有 `/data/adb/metamodule`（即没装 meta-overlayfs）直接 `abort`，
  并打印三行指引；装成功时打印实际 metamodule 路径。
- 新增**镜像残留提示**：发现 `meta-overlayfs/mnt/` 里还有别的相机模块目录（会与本模块抢同一路径）时列出目录名并建议卸载。
- 实测：安装日志出现 `- metamodule: /data/adb/modules/meta-overlayfs`，
  且成功拦截并提示了残留的 `mnt/avium_miuicamera_thor21`。

### 2) 设备端自检升级 —— `action.sh`
新增/修正项（点「操作」即产出 `diagnostics/`）：
| 文件 | 内容 |
|---|---|
| `hashes.txt` | 生效 APK / HAL 哈希 **与 payload 期望值比对**（`match=YES/NO`），并列 algoup/mianode/gui_shim |
| `overlay.txt` | metamodule 链接、`KSU on /system` 挂载是否含本模块目录、**provider/cameraserver 进程**（用 `init.svc_debug_pid` 判断，修掉了 `pidof` 匹配不到进程名的误报） |
| `integrity.txt` | 清单先做 `tr -d '\r'` 归一化再校验（修 CRLF 全 FAIL 的坑） |
| `fps.txt` | 取所有 `Frames produced` 的**最大值**求差；相机未运行/被重开分别给 `none` / `reset` |
实测输出：`integrity 25 OK / 0 异常`、`apk=YES hal=YES`、`overlay=YES`、`fps ≈15–17`。

### 3) 打包流程硬化 —— `build.ps1`
- `SHA256SUMS` 改 **LF** 写出，并排除 `SHA256SUMS` / `customize.sh` / `README.md`（装后不落地，纳入会误报）；
- 顶层文档按**白名单**（`CREDITS.md`/`README.md`/`STATUS.md`/`INSTALL-CN.md`）打包，测试报告归档到 `reports\`；
- 7-Zip 加 **`-mcu=on`**（UTF-8 文件名）；说明文档改名 **`INSTALL-CN.md`**（ASCII），
  避免中文名被按 GBK 存进 zip 后解出来变乱码、导致完整性校验失败。

### 4) 包内附带刷入说明
`INSTALL-CN.md` 随包分发（含 metamodule 前置、装机顺序、验证命令、已知问题、排障表）。

### 验证（1.7.7）
`verify.ps1` 全绿：完整性 OK、APK `5e1816cf`、HAL `240610b0`、冷启 461ms、预览 17.6fps、
照片 3,162,417 B、CHI 0、crash 0；`action.sh` 自检 25 OK / 0 + apk/hal/overlay 全 YES。
包：`avium_miuicamera_thor-1.7.7-avium.zip`。

> 发布包的大小与 SHA-256 **不在本文件里写死**：`STATUS.md` / `INSTALL-CN.md` 都随包分发，
> 一旦写进自身哈希，改一次文档哈希就变，永远对不上。校验值统一记在发布目录的 `RELEASE.txt`
> （不打包进 zip），包内 `SHA256SUMS` 只用于校验模块文件本身。

### 收尾状态（2026-11-19）
- 模块本体优化 1.7.2→1.7.7 已完成，真机验证全绿，装机自检通过。
- `INSTALL-CN.md` 内版本号已对齐 1.7.7，且改为不写自身校验值/精确字节数。
- 遗留（非模块缺陷，用户已接受）：慢动作模式（id `0xac`）触发 provider 在 `libSNPE.so` 内崩溃；
  官方签名 APK 在 A16 上无法预览（缺 `ZoomMapBridge`）。两者都只能改 APK / 二进制，不改。