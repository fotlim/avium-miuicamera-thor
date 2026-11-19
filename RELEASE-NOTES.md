# AviumUI 小米相机模块（thor）1.7.7

**适用于 Xiaomi 12S Ultra（`thor`）× AviumUI-16.2.2 / Android 16**

本项目是把**小米官方 MiuiCamera 6.x** 移植到 A16 自定义 ROM 的 KernelSU 模块。
相机 APK 与 native 库来自上游 [GSQ2004/thor-miuicamera](https://github.com/GSQ2004/thor-miuicamera) v0.1.7（已完成 A16 patch + 重签名），
模块脚本、overlay 骨架、自检与打包流程为本项目自写。**payload 的全部功劳归上游与小米官方。**

---

## 一、下载与校验

| 文件 | 说明 | 大小 | SHA-256 |
|---|---|---|---|
| `avium_miuicamera_thor-1.7.7-avium.zip` | 相机模块本体 | 121,498,558 B（115.9 MB） | `bcdd8d3ac05196f1d87a37b4db5967ae9fef564bbedd909559449d710324bd32` |
| `meta-overlayfs.zip` | **前置必装** metamodule v1.3.1 | 451,415 B | `279d85a6a35724dfcf8aa1137a9630c7e989e154b94543517c539ee70f9b8811` |

Windows 校验：

```powershell
Get-FileHash .\avium_miuicamera_thor-1.7.7-avium.zip -Algorithm SHA256
```

---

## 二、前置条件（不满足会装了个寂寞）

1. **KernelSU**（或支持 metamodule 的 KSU 分支），已获得 root。
2. **meta-overlayfs 1.3.1+** 必须先装好并生效 —— 相机内容靠它把镜像挂到 `/system`、`/system_ext`。
   没装的话模块**会直接 abort 并提示**（1.7.4 起有守卫，不会再假成功）。
3. ROM 侧需允许 overlayfs 挂载（本模块已在 AviumUI-16.2.2 上验证）。

---

## 三、刷入

1. **先装 `meta-overlayfs.zip`**，重启，确认 `/data/adb/metamodule` 存在。
2. 装 `avium_miuicamera_thor-1.7.7-avium.zip`（KernelSU 管理器「模块 → 从本地安装」，或命令行）：
   ```bash
   adb push avium_miuicamera_thor-1.7.7-avium.zip /data/local/tmp/avium_cam.zip
   adb shell "/data/adb/ksud module install /data/local/tmp/avium_cam.zip"
   ```
3. **重启**。首次启动会等系统起来后自动补授 10 项权限。
4. 打开「相机」图标即可用。

完整刷入/排障说明见包内 `INSTALL-CN.md`。

---

## 四、本版（1.7.2 → 1.7.7）更新内容

**均为模块脚本层优化，payload 未改动**（APK/HAL 与上游 v0.1.7 字节一致）。

- **`customize.sh`**：新增 metamodule 守卫（未装 meta-overlayfs 直接 abort 并给指引）；
  新增镜像残留目录提示（防止旧模块目录与新 payload 混挂）。
- **`action.sh`**：设备端自检升级 ——
  `hashes.txt` 把生效的 APK/HAL 哈希与期望值比对（`match=YES/NO`）；
  `overlay.txt` 检查 metamodule 链接、`KSU on /system` 是否含本模块、provider/cameraserver 进程；
  `integrity.txt` 先 `tr -d '\r'` 归一化再校验（修掉 CRLF 导致全 FAIL）；
  `fps.txt` 改取最大 `Frames produced` 求差，区分 `none`/`reset`（原来会抓错流给出假数据）；
  修掉 `pidof` 匹配不到 provider 进程名的误报（改用 `init.svc_debug_pid`）。
- **`build.ps1`**：`SHA256SUMS` 用 **LF** 写出并排除 `customize.sh`/`README.md`（装后不落地，纳入即误报）；
  顶层文档走白名单；测试报告归档 `reports\`；7-Zip 加 `-mcu=on`；说明文档改名 `INSTALL-CN.md`（ASCII），
  避免中文名被按 GBK 存进 zip 后解出来乱码、导致校验失败。
- **`service.sh`**：等 `sys.boot_completed` 后再等 `pm path com.android.camera`（≤120s）才授权，写 `startup.log`。
- **包内附带** `INSTALL-CN.md` 刷入说明。

---

## 五、实测验证（thor / AviumUI-16.2.2 / A16）

| 项目 | 结果 |
|---|---|
| `sha256sum -c SHA256SUMS` | 25 OK / 0 失败 |
| APK 哈希 | `5e1816cf…`（match=YES） |
| HAL 哈希 | `240610b0…`（match=YES） |
| 冷启动 | 461 ms |
| 预览帧率 | 约 17 fps（帧计数持续增长） |
| 拍照 | 3.1 MB 级（3072×4096，约 3,154,162 B） |
| CHI 报错 / crash | 0 / 0 |

已验证可用：主界面 5 个模式、前置相机、照片、4K30、8K、超级防抖、专业模式、辅助窗口预览，另有 11/12 个「更多」模式。

---

## 六、已知问题（未修，需改 APK / 二进制）

1. **慢动作**（模式 id `0xac`）：进入录制会让 `camera-provider` 在 `libSNPE.so` 内 SIGSEGV，导致 cameraserver 重启。
   - 已确认：换回本机官方 stock HAL（`26adcce`）同样崩溃 → **不是本模块 payload 引入的**；
   - 已尝试无效：`vsquality` 120 项调参、关 AI/美颜/HDR、`resetprop` 注入各算法开关；
   - 纯 prefs 隐藏入口不可行（App 启动会重算模式列表）；
   - 结论：只能改 APK 或 provider/`libSNPE` 二进制，本版不改。**请不要在正式使用中进入慢动作。**
2. **官方签名 APK 在 A16 无法预览**：缺 `ZoomMapBridge`（A/B 实验已证实）。所以本模块只能用上游重签名 + patch 过的 APK，这也意味着它**不能覆盖安装在其它 ROM 的官方相机上**。

---

## 七、致谢 / Credits

- **相机 APK / native 库 / HAL patch**：Xiaomi 官方 + [GSQ2004/thor-miuicamera](https://github.com/GSQ2004/thor-miuicamera) v0.1.7 —— 本项目 payload 与其 `mod017.zip` 字节一致（仅去掉 2 个没用的 stub HIDL 库、替换 `miui-cameraopt.jar`）。
- **meta-overlayfs**：其作者。
- **模块脚本 / overlay 骨架 / 自检 / 打包流程**：本项目自写。

**本项目为非官方移植，与小米、GSQ2004 均无隶属关系。刷机有风险，自行承担。**