# 小米 Pad 6 Pro 依赖资源核对

核对日期：2026-11-04（首次 2026-11-03）。目标是日常流畅与续航平衡，
用户当前系统为 HyperOS 3.0.7.0。Android 版本、完整系统版本后缀、
设备实际内核版本尚未核实。

已在原始 5.10.81 基线上分两批合入 19 个稳定维护补丁（首批 12 个，
第二批 7 个），更新了 Binder、zRAM、UFS、USB、ext4、f2fs、bdi 和内存管理
代码。补丁来源、验证结果及仍未通过的设备构建条件见
[维护记录](MAINTENANCE-2026-11.md)。这不是完整升级至最新 5.10.y。

## 已同步的资源

`dependencies.json` 记录来源、分支、完整提交号及本地位置。

| 资源 | 本地状态 | 上游提交 |
| --- | --- | --- |
| 小米内核 `liuqin-t-oss` | 原有源码已经与该官方分支一致；版本为 5.10.81 | `eb49e10028e` |
| 小米设备树 `liuqin-t-oss` | 已补齐到 `arch/arm64/boot/dts/vendor` | `1c507816ba8a` |
| 小米 WLAN `liuqin-t-oss` | 已下载到 `work/dependencies/wlan`，尚未接入构建 | `50782ba78f15` |
| Android 构建脚本 `master-kernel-build-2021` | 已下载并在 WSL 构建工作区装配为 `build/` | `dbfab7e0de2e` |
| ACK 内核 `android12-5.10` | 已装配到 WSL 工作区 `common/`（当前分支头） | `c55664ffabc2` |
| platform/prebuilts/build-tools | 已装配到 WSL 工作区 | `cfedc16ec3de` |
| kernel/prebuilts/build-tools | 已装配（hermetic dtc/depmod/avbtool/mkdtboimg.py 等） | `ca5b087f88c0` |
| platform/prebuilts/gcc（host sysroot） | 已装配 | `4e6f66acf138` |
| platform/prebuilts/gas/linux-x86 | 已装配（msm 构建脚本引用，分支头固定） | `b2a189331333` |
| platform/system/tools/mkbootimg | 已装配（mkbootimg.py/unpack_bootimg.py） | `34bc8bfb4934` |
| platform/system/libufdt | 已装配（overlay 工具，master 头固定） | `9b70f594cf14` |
| kernel/configs | 已装配 | `c10b7ea022ed` |
| 社区厂商模块 `evox-a16` | 已下载到 `work/dependencies/sm8450-modules-reference`，仅作移植参考 | `0df8f5c6d8e8` |

另已保存两套社区 `hwid` 实现，固定来源和文件 SHA-256 见 `referenceSources`。
它们缺少本设备所需的标识定义，未接入内核。`plaid` 仍缺少可下载来源。
厂商模块与 hwid 的核对结果见 [源码恢复记录](SOURCE-RECOVERY-2026-11.md)。

设备树包含 `liuqin-sm8475-pm8008-overlay.dtbo` 的构建入口。WLAN 包含
`fw-api`、`qca-wifi-host-cmn`、`qcacld-3.0` 和 `utils`，应作为配套资源核对。
下载的仓库各自保留 Git 历史和远端信息；大体积资源被主仓库忽略，不会随主仓库提交。
新机器需要按清单重新克隆，并检出记录的完整提交号。

## 检查资源是否有更新

在项目根目录运行：

```powershell
# 核对清单内五个本地仓库的 HEAD，以及八个 hwid 参考文件摘要。
powershell -NoProfile -File tools/liuqin/check-dependencies.ps1

# 同时查询清单中的分支（包括社区参考仓库），发现变更时返回非零退出码。
powershell -NoProfile -File tools/liuqin/check-dependencies.ps1 -Online
```

`PIN_MATCH` 仅表示提交号一致，不代表工作目录没有改动、编译通过或可刷机。
`UPSTREAM_CHANGED` 表示远端分支偏离记录的提交，应检查差异和兼容性后再更新清单。
脚本不会自动合并、重置文件或更新设备。工具链及源码完整性不属于该检查的范围。
`HASH_MATCH` 只表示参考文件与记录的摘要一致，不表示已适配设备。

## 工具链核对

本地 `build.config.common` 与核对时 Google 的 `android12-5.10/build.config.common`
均指定 `clang-r416183b`；其 `AndroidVersion.txt` 标注 Clang 12.0.5。
已从 Google 固定提交下载并安装 Linux x86_64 二进制，实际输出为
`Android (7284624, based on r416183b) clang version 12.0.5`，LLD 为 12.0.5。
ARM64 对象编译和 ThinLTO/CFI 链接检查通过；这不等于完整内核通过构建。

安装在 WSL Debian 的 Linux 文件系统中，保留真实符号链接与执行权限：

```text
/var/tmp/liuqin-android12-5.10/prebuilts-master/clang/host/linux-x86/clang-r416183b
```

压缩包保留在 `work/dependencies/toolchains/clang-r416183b.tar.gz`，
SHA-256 为 `d84acd1183f49d25d7d54b4f8b01675a677aa531b53a87cce2c4919ac5ea56a8`。
安装路径在 `/var/tmp` 磁盘上，不使用容量较小的 `/tmp`；系统清理仍可能删除 `/var/tmp`，
保留的压缩包可用于恢复。此路径尚未组装成完整 Android kernel build 工作区。

从本项目目录验证现有安装：

```powershell
wsl -d Debian -- bash /mnt/e/project/Xiaomi_Kernel_OpenSource/tools/liuqin/verify-toolchain.sh
```

若安装目录已不存在，可用已保存的包重装；脚本校验清单中的 SHA-256、
使用安全解包过滤器并执行编译测试，不覆盖已有安装目录：

```powershell
wsl -d Debian -- python3 /mnt/e/project/Xiaomi_Kernel_OpenSource/tools/liuqin/install-toolchain.py --archive /mnt/e/project/Xiaomi_Kernel_OpenSource/work/dependencies/toolchains/clang-r416183b.tar.gz
```

新机器可从 `dependencies.json` 的 `toolchain.archiveUrl` 下载固定提交的压缩包。
安装脚本需要带 `tarfile.data_filter` 的 Python（建议 3.12+）。
Google 配套 manifest 使用 `master-kernel-build-2021` 获取构建工具。
升级到其他 Clang 版本需要单独验证旧版 CFI、LTO、厂商驱动及 KMI，不能仅修改目录名。

## 当前构建缺口

1. `drivers/misc/Kconfig` 无条件引用了缺失的 `drivers/misc/hwid/Kconfig`
   和 `drivers/misc/plaid/Kconfig`。必须寻找匹配实现，不能用空文件假装补齐。
   这仍会阻断 msm-kernel（设备内核）阶段的配置生成。
2. `techpack` 当前只有 `stub`；已下载社区厂商模块作为参考，音频、相机、显示的
   原厂配套源码和 BSP 版本仍需核对。
3. ~~external/dtc、启动镜像工具及 host prebuilts 未补齐~~ 已于 2026-11-04 补齐：
   hermetic dtc 实际来自 `kernel/prebuilts/build-tools`（本树 manifest 无
   external/dtc 项目），mkbootimg/unpack_bootimg、build-tools、host sysroot、
   gas、libufdt 均已按固定提交装配进 WSL 构建工作区
   `/var/tmp/liuqin-android12-5.10/`，`build/build.sh` 环境解析全部通过，
   `VARIANT=gki` 下 ACK common 内核可以实际编译。
4. Windows 检出的符号链接问题已通过 WSL 中的真实 git 克隆解决：
   msm-kernel 43 个、build 106 个 git 符号链接全部恢复且目标存在（broken=0）。
   注意 WSL 对 `/mnt/e` 的文件读写在当前环境不可靠（出现过脚本读到半截、
   写入日志丢失），验证一律在 WSL ext4 内进行，产物最后才拷回。
5. 小米公开分支表将 `liuqin-t-oss` 标注为 Android T，BSP 为
   `LA.VENDOR.1.0.r1-13100-WAIPIO.0-1`。它对 HyperOS 3.0.7.0 的兼容性尚未验证。
6. `consolidate` 变体引用的 `common/build.config.gki_consolidate.aarch64`
   在当前 ACK common（5.10.270 时代分支头）已不存在；`gki` 变体不受影响。
   如需复现 consolidate，需将 common 固定到 2022 年初的 android12-5.10 提交。

## 后续更新顺序

先采集目标设备的 `uname -r`、`/proc/version`、完整系统版本及厂商模块信息，
定位缺失驱动和匹配工具，再建立能重复编译、可回退的基线。
随后分批评估 Android Common Kernel / Linux 5.10 维护补丁，进行构建与 KMI 检查。
内核主版本迁移、驱动跨版本替换和工具链大版本升级应分别验证。

面向续航的配置优化放在基线建立后：当前 `build.config.msm.liuqin` 默认
`consolidate` 变体，包含较多调试配置，可评估 `gki` 变体。
这不说明设备现用内核也采用该配置，更不能在缺少厂商功能验证时直接切换。

先前维护已完成修改前后五个文件的 GCC 诊断对象编译；2026-11-04 又用生产
Clang r416183b 完成了 8 个受影响文件（含第二批 ext4/f2fs/bdi）的基线与
补丁后对象编译，全部通过且零告警，条件与局限详见维护记录。构建工作区已
组装完成：自检中 ACK common 的 GKI 内核完成配置生成并用生产 Clang 编译了
2663 个编译单元，最终 ThinLTO vmlinux 链接因本机 WSL 内存限制（2 GB）被
系统终止——属宿主机资源限制而非环境缺口。设备内核配置生成仍因缺少 hwid
而失败，详见源码恢复记录。尚未完成完整内核链接、模块装载、镜像打包或
设备刷写。

## 官方来源

- [小米内核分支表](https://github.com/MiCode/Xiaomi_Kernel_OpenSource/tree/README)
- [小米配套设备树](https://github.com/MiCode/kernel_devicetree/tree/liuqin-t-oss)
- [小米配套 WLAN](https://github.com/MiCode/vendor_qcom_opensource_wlan/tree/liuqin-t-oss)
- [Google Android 12 / 5.10 资源 manifest](https://android.googlesource.com/kernel/manifest/+/refs/heads/common-android12-5.10/default.xml)
- [Google 工具链配置](https://android.googlesource.com/kernel/common/+/refs/heads/android12-5.10/build.config.common)
- [已核实的 Clang 版本](https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+/6e3223f76384455acde43affde3df0ea9df66c0d/clang-r416183b/AndroidVersion.txt)
