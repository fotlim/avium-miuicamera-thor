# AviumUI 小米相机模块 —— 刷入说明

> 模块：`avium_miuicamera_thor22` / **1.7.7-avium**
> 包名：`avium_miuicamera_thor-1.7.7-avium.zip`
> 大小：约 **115.9 MB**（以发布目录中的实际文件为准）
> SHA-256：以发布目录 / 发布页提供的校验值为准（包内 `SHA256SUMS` 用于校验模块文件本身）
>
> 说明：本文件随包分发，因此不写死自身校验值和精确字节数 —— 否则一改本文件，包的大小与哈希就跟着变。

---

## 零、前置必装：metamodule（meta-overlayfs）

**相机模块的内容是靠 meta-overlayfs 挂载上去的；没有它，装了也不会生效。**

| 项 | 值 |
|---|---|
| 包名 | `meta-overlayfs.zip` |
| 大小 | **451,415 B（约 0.43 MB）** |
| SHA-256 | `279d85a6a35724dfcf8aa1137a9630c7e989e154b94543517c539ee70f9b8811` |
| 模块 id / 版本 | `meta-overlayfs` / **1.3.1**（versionCode 13100） |
| 作者 | KernelSU Developers |
| 关键标记 | `module.prop` 里有 `metamodule=1` |

### 安装顺序（务必先它、后相机）

```powershell
adb root
adb push meta-overlayfs.zip /data/local/tmp/meta-overlayfs.zip
adb shell "/data/adb/ksud module install /data/local/tmp/meta-overlayfs.zip"
adb reboot
# 重启后确认它是"生效的 metamodule"，再装相机模块
```

KernelSU 管理器 GUI 同理：**先装 meta-overlayfs → 重启 → 再装相机模块 → 再重启**。

### 怎么确认 metamodule 真的生效

```powershell
# 1) metamodule 链接是否指向它（这是 KSU 认它的唯一凭据）
adb shell "ls -l /data/adb/metamodule"
#    期望：/data/adb/metamodule -> /data/adb/modules/meta-overlayfs

# 2) 模块 id / 版本
adb shell "grep -E '^(id|version|metamodule)=' /data/adb/modules/meta-overlayfs/module.prop"

# 3) 装完相机模块并重启后，overlay 是否真的挂上（应能看到本模块目录）
adb shell "mount | grep 'KSU on /system'"
#    期望：... lowerdir=/data/adb/modules/meta-overlayfs/mnt/avium_miuicamera_thor22/system:/system
```

> ⚠️ 卸载时顺序相反：**先卸相机模块 → 再卸 meta-overlayfs**。
> 另外 meta-overlayfs 会占一个 **2 GB 的 ext4 镜像**（`/data/adb/modules/meta-overlayfs/modules.img`），
> 相机模块约 200 MB，装旧版本多了会满，见下一节清理办法。

---

## 一、适用条件（不满足就别装）

| 项 | 要求 |
|---|---|
| 机型 | Xiaomi 12S Ultra（`thor` / 2203121C） |
| 系统 | Android 16（API 36），实测 AviumUI-16.2.2 |
| Root | KernelSU（内核集成）**+ 能挂载 overlay 的 metamodule** |
| **必需 metamodule** | **meta-overlayfs v1.3.1**（没有它，KSU 3.x 不会把模块里的 `/system`、`/vendor` 内容挂上去） |
| SELinux | Enforcing（模块自带规则，不要关 SELinux） |

> `customize.sh` 会校验机型与 API，不符会直接中止安装。

---

## 二、装包前先看清楚

1. **模块 id 是 `avium_miuicamera_thor22`**。如果你之前装过别的 id（`thor18`、`thor19`、`thor20`、`thor21`…），
   请先**卸载旧模块并重启**，否则两个模块会同时往 `/system/priv-app/MiuiCamera` 挂载，行为不可预期。
2. meta-overlayfs 的镜像是 **2 GB**，每份模块约 200 MB。**装过 3–4 个旧版本后镜像会满**，
   新模块会静默拷贝失败（表现为"模块目录缺 system"）。满了就先清：

```
adb shell su -c "rm -rf /data/adb/modules/meta-overlayfs/mnt/<旧模块id>"
adb shell su -c "df -h /data/adb/modules/meta-overlayfs/mnt"
```

---

## 三、刷入（二选一）

### 方式 A：KernelSU 管理器 GUI（推荐给普通用户）

1. 把 zip 传到手机任意目录（例如 `/sdcard/Download/`）。
2. 打开 **KernelSU 管理器 → 模块 → 从本地安装**，选这个 zip。
3. 安装完成后**重启手机**。
4. 重启后打开「相机」App，首次可能弹权限框，全部允许。

### 方式 B：命令行（adb）

```powershell
# 0) 设备连上、拿到 root
adb devices
adb root

# 1) 把包推到手机
adb push avium_miuicamera_thor-1.7.7-avium.zip /data/local/tmp/avium_cam.zip

# 2) 安装（KernelSU 的 ksud）
adb shell "/data/adb/ksud module install /data/local/tmp/avium_cam.zip"

# 3) 安装完确认模块目录
adb shell "ls /data/adb/modules/"

# 4) 重启
adb reboot
```

> ⚠️ 如果你是从**旧 id** 升级：安装新版之后还要把旧模块标记卸载，再重启：
> ```
> adb shell "/data/adb/ksud module uninstall <旧模块id>"
> ```

---

## 四、装完怎么确认成功

```powershell
# 1) 模块在不在、版本对不对
adb shell "grep -E '^(id|version)=' /data/adb/modules/avium_miuicamera_thor22/module.prop"

# 2) 文件完整性（应为全部 OK，0 失败；1.7.2+ 清单已排除安装期文件）
adb shell "cd /data/adb/modules/avium_miuicamera_thor22 && sha256sum -c SHA256SUMS | grep -v ': OK'"

# 3) 生效的 APK / HAL 哈希（应分别是 5e1816cf… / 240610b0…）
adb shell "sha256sum /system/priv-app/MiuiCamera/MiuiCamera.apk"
adb shell "sha256sum /vendor/lib64/hw/camera.qcom.so"

# 4) 打开相机并看预览是否真的在出帧
adb shell "am start -n com.android.camera/.Camera"
adb shell "dumpsys media.camera | grep -m1 'Frames produced'"      # 数字应在涨

# 5) 拍一张
adb shell "input tap 720 2870"
adb shell "ls -l -t /sdcard/DCIM/Camera/*.jpg | head -1"           # 正常约 2.3–3.2 MB、3072×4096
```

模块应用里点「操作」按钮会做一次设备端自检，结果写到：
`/data/adb/modules/avium_miuicamera_thor22/diagnostics/`
（`integrity.txt` / `fps.txt` / `hashes.txt` / `status.txt` / `camera-log.txt`）。

---

## 五、卸载 / 回滚

```powershell
adb shell "/data/adb/ksud module uninstall avium_miuicamera_thor22"
adb shell "rm -rf /data/adb/modules/meta-overlayfs/mnt/avium_miuicamera_thor22"
adb reboot
```
重启后 `/system/priv-app/MiuiCamera` 恢复成 ROM 自带（若 ROM 本身没有相机，就用系统默认相机）。

---

## 六、已知问题（装完先知道，免得以为坏了）

1. **「慢动作」模式不能用**：进去会提示「无法连接到相机，应用将在 2s 后退出」，并且**会让相机服务重启一下**
   （期间其它用相机的 App 也会短暂受影响）。原因：该模式要建 120fps 高帧率会话，provider 在 `libSNPE` 里崩溃；
   换原厂 HAL、关 AI 配置都试过均无效。**其余模式都正常**。
2. **USB 选项弹窗 / 权限弹窗会打断相机**：MiuiCamera 一旦被切到后台就会自己退出（正常行为，不是崩溃）。
   装完第一次打开时若弹权限框，先点允许；桌面连接 USB 时先点掉「将 USB 用于」弹窗。
3. **首次启动会稍慢**（要加载 26 个 AI 模型/配置），等几秒再按快门。
4. **别用 `input keyevent 27` 去按快门**（本机该键会触发退出提示），用点击快门位置 `input tap 720 2870`。

---

## 七、出问题怎么排查

| 现象 | 先查 |
|---|---|
| 模块装了但相机还是 ROM 原来的 | meta-overlayfs 没装/没生效；`mount | grep 'KSU on /system'` 里应能看到本模块目录 |
| 相机图标有、点开闪退 | 权限白名单/API 不符；看 `diagnostics/crash.txt`、`camera-log.txt` |
| 取景全黑、`dumpsys media.camera` 里 `Frames produced: 0` | payload 被换成了官方原签名 APK（缺预览桥，必然黑屏）—— 必须用本包内的 APK |
| 开机卡第一屏 | 模块 id 未更换却换了 payload（镜像里残留旧文件）；卸载旧模块 + 清 `mnt/` 旧目录 |
| 装机后 `sha256sum -c` 报 FAIL | 若报的是 `customize.sh` / `README.md`，那是老版本包的 bug（已修）；1.7.1 起清单不再包含这两个文件 |

---

## 八、第三方署名

相机 APK 与相机相关库来自 **Xiaomi 官方**，经 **GSQ2004 / thor-miuicamera v0.1.7** 为 Android 16 适配并重签；
模块脚本、SELinux 规则、权限配置、打包流程由 **AviumUI** 编写。完整出处见包内 `CREDITS.md`。
本模块为非官方移植，与 Xiaomi / Leica 无隶属关系。