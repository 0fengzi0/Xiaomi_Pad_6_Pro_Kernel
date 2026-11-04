# Pad 6 Pro 实机基线核对

采集日期：2026-11-04。通过已授权的 USB ADB 读取设备信息；用户确认安装的是
KernelSU，未报告另外更换内核。后续启用的 ADB Root 返回 `uid=0`、
`u:r:ksu:s0`，SELinux 为 `Enforcing`，`ksud --version` 为 `3.2.4`。
本次只读采集系统信息、配置、模块及当前槽位的 vendor_boot，未刷写、重启、
加载模块、修改调度/功耗参数或关闭安全保护。

## 已确认的信息

| 项目 | 设备读数 |
| --- | --- |
| 型号 / 代号 | `23046RP50C` / `liuqin` |
| 系统 | Android 15，SDK 35，`OS3.0.7.0.VMYCNXM` |
| 系统安全补丁属性 | `2026-05-01` |
| vendor 安全补丁属性 | `2026-02-01` |
| 当前运行内核 | `5.10.236-android12-9-00003-gfb24cf99ad97-ab14313284` |
| 内核编译工具 | Android Clang `r416183b` / 12.0.5，LLD 12.0.5 |
| KernelSU 报告的 KMI 系列 | `android12-5.10` |
| 设备树 model | `Liuqin based on Qualcomm Technologies, Inc SM8475` |
| 设备树 compatible | `qcom,cape-mtp`、`qcom,cape`、`qcom,mtp` |
| 当前槽位 | `_a` |
| Bootloader 属性 | `unlocked`，`flash.locked=0`，Verified Boot `orange` |
| 已加载模块 | 416 个（采集时快照） |

安全补丁日期是设备属性，不能据此证明源码包含某个安全补丁。
用户后续确认 KernelSU 为 LKM 模式。已在 KernelSU 保存的原始 boot 备份中
核对出相同的 5.10.236 内核，且与当前槽位内核逐字节一致、与运行配置一致；
当前 ramdisk 另含 `kernelsu.ko`，与 LKM 安装方式相符。具体证据见后文。

## 原始 boot 与当前槽位核对

用户提供的项目根目录 `boot.img` 是以前保留的原始备份，其内核为
`5.10.226-android12-9-00064-gea4a6f067d3f-ab12969919`。该文件保持原样，
其内核和配置均与当前设备不同，不能当作当前系统的原始镜像。

在设备 `/data/adb/ksu/` 的七份 boot 备份中，找到三份内核字节与当前槽位
一致的备份。已复制其中保存时间较新的
`ksu_backup_bde9e48aa1b3e328d66552b972f91f02b816fd29` 到电脑，核对
整镜像 SHA-256 与设备端一致，镜像 SHA-1 同时与备份文件名一致。

本次 boot 产物目录为 `work/dependencies/stock-boot-20261104/`：

| 文件 | 来源 / SHA-256 |
| --- | --- |
| 项目根目录 `boot.img` | 用户旧备份；`1655c74684b3984f6c6c246b9a826e99ee3b70cf3704f8f909ac4674a9ab716c` |
| `ksu-saved-original-boot-5.10.236.img` | KernelSU 保存的匹配原始备份；`9dd14961ae15aa10d162711d57972c5c62e7af23f2dabc22bac57b24bc185e4b` |
| `current-boot-a.img` | 当前槽位完整只读备份；`16e9977e648f1519547412a8a9e4191d876f36862edaf7357590526a81181919` |

三个 boot 文件大小均为 201326592 字节（192 MiB），镜像头均为 v4。
用户旧备份头中的 OS patch level 为 `2025-02`，匹配备份和当前槽位均为
`2025-09`；镜像头 OS version 均为 `12.0.0`，不能把这个头字段当作设备当前
Android 系统版本（设备系统属性为 Android 15）。

匹配备份与当前槽位的内核均为 46854828 字节，SHA-256 相同：

```text
42c827b562da776539da12ef90e7755495b1ebd33fe16d6257e299a0530fb801
```

从匹配备份内核导出的配置与 `/proc/config.gz` 解压结果逐字节一致，SHA-256
均为 `aa19d5a2ad009afb5a8968e8a880790a4657c659041ac15c89e4b7ce6c0a04b6`。
匹配备份 ramdisk 为 1380093 字节，当前 ramdisk 为 1743468 字节；两者均完成
LZ4 解压与 cpio 条目解析，当前镜像额外含 `kernelsu.ko`（327576 字节），
匹配备份的条目中无该文件。以上证据支持当前 LKM 安装保留了备份中的内核。

匹配备份来自设备本地 KernelSU，尚未与小米官方当前 ROM 包进行独立摘要比对，
也未执行任何恢复或启动测试。本次没有调用 `boot-restore`，只读取了其帮助。
`comparison.json`、`ramdisk-comparison.json` 与各 unpack 日志保存详细证据。

### 同源 ACK 源码

已从 Google 官方 Gitiles 获取当前内核 release 对应的完整提交：

[`fb24cf99ad973cd4c7c7fa375c6053f939ef3a89`](https://android.googlesource.com/kernel/common/+/fb24cf99ad973cd4c7c7fa375c6053f939ef3a89)。

该提交的 `Makefile` 为 5.10.236，`build.config.common` 指定
`BRANCH=android12-5.10`、`KMI_GENERATION=9` 和 Clang `r416183b`，
与设备 release 及编译工具读数一致。官方提交 JSON 和四份构建元数据已保存于
boot 产物目录的 `ack-source-commit.json`、`ack-source-metadata/`。
这些核对确认了可追溯的候选源码提交；尚未在该提交完成源码检出、全量构建、
可重复二进制比较或新内核 ABI 验收。

## hwid 和厂商模块

Root 下读取的硬件标识参数：

| 参数 | 值 |
| --- | --- |
| `project` | `16` |
| `hwid_value` | `589824`（`0x90000`） |
| `project_adc` | `34270` |
| `build_adc` | `65002` |

`/proc/cmdline` 同时含四个对应的 `hwid.*` 参数，值与 sysfs 一致；
`/proc/bootconfig` 的 `androidboot.hwversion` 为 `16.9.0`。
因此已确认当前设备通过内核启动参数传递这些数值，而非只能猜测默认值。

从当前 `vendor_boot_a` 的 vendor ramdisk 提取到 `lib/modules/hwid.ko`，大小
23040 字节。它不在运行后的 `/vendor/lib/modules` 下，先前普通 ADB 在该位置
找不到文件不能证明模块缺失。设备 `/proc/modules` 同时确认 hwid 已加载，
其消费者包括 `qca6490`、`machine_dlkm`、`camera`、`cnss2`、`icnss2`。

已提取 hwid，以及 vendor_dlkm 内的 `cnss2.ko`、`camera.ko`、`msm_drm.ko`、
`machine_dlkm.ko`、`cs35l41_dlkm.ko`、`qca_cld3_qca6490.ko`。
七个文件的 vermagic 均为：

```text
5.10.160-gki-gd28eeb36ae86 SMP preempt mod_unload modversions aarch64
```

| 模块 | 文件中的 scmversion，与运行时 sysfs 读数一致 |
| --- | --- |
| hwid、cnss2 | `gd28eeb36ae86` |
| WLAN qca6490 | `g90b312bec263` |
| camera | `g1da65533971b` |
| msm_drm | `ge5cf5b30a363` |
| machine_dlkm、cs35l41_dlkm | `g6963eef22682` |

hwid 导出 9 个接口，包括 `get_hw_version_platform`、`get_hw_id_value`、
`get_hw_country_version`、`product_name_get`、版本拆分接口和两个 ADC getter。
对所抽取六个消费者模块与 hwid 的符号交集做 CRC 核对：camera 2 处、cnss2
2 处、machine_dlkm 2 处、qca6490 1 处，共 7 处全部一致。其余两个被抽取模块
在本次核对中没有直接导入这些 hwid 接口。

这是当前模块集合内部的静态接口证据，不能代替新编译内核的全量 KMI/ABI 检查。
当前运行内核版本与模块 vermagic 不同，二者已在该设备中共同加载；不能用
版本字符串相等与否代替符号版本、CFI 和运行时兼容性验证。

取得 `project=16` 和实际模块后，已具备核对 M81 映射的实机依据；尚未恢复
hwid 源码，也未把该值写入社区参考实现。plaid 未出现在所读模块清单及 ramdisk
条目中，相关 sysfs 节点也未发现；该有限检查不能证明其可安全从源码构建中删除。

## 配置与运行状态

已成功导出 `/proc/config.gz`（39530 字节）并解压。解压配置 SHA-256：

```text
aa19d5a2ad009afb5a8968e8a880790a4657c659041ac15c89e4b7ce6c0a04b6
```

配置显示启用 `CONFIG_MODVERSIONS`、Clang Full LTO、CFI、vendor hooks 和
`CONFIG_KASAN_HW_TAGS`。这些是配置证据，不代表已测得运行期开销或续航影响，
也不能仅凭缺少某个 vendor 配置项判断外部模块未启用。

CPU 三个 policy 的 governor 均为 `walt`，GPU 读数为 `Adreno730v3`。
zRAM 当前选择 `lzo-rle`，逻辑 disksize 为 12884901888 字节（12 GiB）。
这些都是采集时状态；本次未进行应用流畅度、待机功耗或压力测试。

## 产物与验证边界

原始产物位于本地忽略目录：

```text
work/dependencies/device-baseline-20261104-222958/
```

- `summary.json`：系统、Root、hwid、镜像和核对结果。
- `running.config`、`config.gz`：设备导出的运行内核配置。
- `loaded-modules.txt`、`vendor.modules.*`：已加载模块和 vendor 加载/依赖清单。
- `vendor_boot_a.img`：当前槽位镜像，只读导出，100663296 字节。
- `vendor-boot-unpacked/vendor_ramdisk00`、`ramdisk-inventory.json`：ramdisk 和条目清单。
- `ramdisk-selected/hwid.ko`、`modules/*.ko`、`module-abi.json`：七个模块和 ELF 元数据。
- `root-probe.txt`、`root-confirmed.txt`：hwid、驱动 scmversion、设备树及权限读数。
- `hardware-access.stderr.txt`：启用 ADB Root 前的权限失败，属于早期采集记录。

vendor_boot 镜像 SHA-256 经设备端与电脑端比对一致：

```text
752b75972f50a71b58ea0da2f227525f4eb16982fba1ea60449c5f63a8bc1b40
```

六个 vendor_dlkm 模块同样逐个核对了设备端与本地 SHA-256。hwid 来自已核对
镜像的 ramdisk，模块 scmversion 与运行时读数相同。

原始 unpack_bootimg 脚本在 Windows 创建 ramdisk 名称符号链接时失败，已写出的
ramdisk 使用现有 Android prebuilt lz4 解压，再按 newc cpio 头和范围检查提取选定
文件；未把该次 unpack 命令记为完整成功。REA 已识别 ARM64 ELF，深度分析因
Windows 后端未配置/不支持该 ELF 目标而不可用；符号证据来自普通 readelf 和
本地 ELF64 节表、符号表、`.modinfo`、`__versions` 解析，没有反编译成功的声明。

## 槽位 B 取证（同日稍后补充）

刷入测试需要非当前槽位作为落点。Root 只读导出 `_b` 槽与 dtbo 后核对：

| 分区 | 大小 | 与 `_a` 对比 |
| --- | --- | --- |
| `boot_b` | 201326592 字节 | **全零，从未写入**（SHA-256 `46b23b74…`） |
| `vendor_boot_b` | 100663296 字节 | 与 `vendor_boot_a` 不同（`425382d5…` vs `752b7597…`） |
| `dtbo_b` | 25165824 字节 | 与 `dtbo_a` 不同（`95aeaae0…` vs `21376daf…`） |

四个镜像已导出到 `work/dependencies/device-baseline-20261104-222958/`，
设备端暂存文件已删除。结论：**不能直接切到 b 槽**——它缺少可引导的
boot/vendor_boot。刷入测试必须先把 `vendor_boot_a`、`dtbo_a` 复制到
`_b` 槽，再写入新内核 `boot_b`，最后 `set_active b`；回退只需
`set_active a`，A 槽全程不写。

同时完成设备端全量模块采集（用于 KMI 基线）：
`/vendor_dlkm/lib/modules` 310 个 `.ko`（`/vendor/lib/modules` 为其符号链接，
`/odm`、`/system_dlkm` 不存在），加上前述 vendor ramdisk 内 352 个 `.ko`，
按内容去重后共 353 个唯一模块、3624 个导入符号，**模块间 CRC 零冲突**；
416 个已加载模块按名称核对 415 个有对应文件（kernelsu 从 boot ramdisk 加载，
已单独提取，SHA-256 `e3087aab…` 与镜像清单一致）。基线数据与提取脚本见
主仓库 `tools/liuqin/baseline/symbol-crcs.json`、`extract-module-crcs.py`、
`collect-vendor-modules.sh`，细节记录于 `dependencies.json` 的
`kmiBaseline`。值得注意：kernelsu.ko 的 vermagic 为 `5.10.252-dirty`，
且 `__versions` 为空（无版本化导入），与 vermagic 宽容机制
（`CONFIG_MODVERSIONS` 下 `same_magic()` 忽略版本前缀）一致。

## 对后续工作的影响

当前至少有三个不同版本层次：本项目 5.10.81 源码、抽取模块的 5.10.160
构建标记、设备当前 5.10.236 内核。原有 19 个维护补丁的重放和对象编译结果
仅证明旧源码上的验证，不能直接作为给这台设备升级内核的依据。

下一阶段优先验证以同源 5.10.236 ACK、KMI generation 9 重建 GKI 核心，
保留现有 vendor_boot、vendor_dlkm 厂商模块和 KernelSU LKM 的路线。
[GKI 架构说明](https://source.android.com/docs/core/architecture/kernel/generic-kernel-image)
将 SoC/板级支持放在厂商模块，提供稳定 KMI；这支持该路线的架构可行性，
不能代替本设备新内核的完整 ABI、模块装载和运行验收。

hwid/plaid 源码仍是重编译旧厂商内核路线的缺口；保留已安装的厂商模块时，
应先验证 GKI 能否满足它们的符号和 CFI 要求，再决定是否需要恢复这些源码。
完整链接资源限制、新内核 KMI/ABI 检查、镜像打包和可恢复启动验收仍未完成。
本次没有生成或试启动新的内核镜像。
