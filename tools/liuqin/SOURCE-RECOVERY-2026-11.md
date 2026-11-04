# liuqin 缺失源码核对

本次目标：补齐 `hwid`、`plaid`、厂商模块，安装配置指定的 Android Clang。
源码基线仍为 `liuqin-t-oss` / Linux 5.10.81。2026-11-04 设备接入后，已通过
KernelSU ADB Root 取得 `project=16`、`hwid_value=589824`，并从当前 vendor_boot
提取真实 `hwid.ko`，但对应源码仍缺失。当前内核为 5.10.236，抽取模块的构建
标记为 5.10.160；详见 [实机基线核对](DEVICE-BASELINE-2026-11-04.md)。
下文社区参考和缺失源码的结论继续保留，早期权限失败不能代替此次 Root 采集结果。

## 源码状态

| 资源 | 本地位置 | 结论 |
| --- | --- | --- |
| 较新的社区 hwid | `work/dependencies/hwid-reference` | 已保存四个真实源码文件，仅供对照；缺少 `HARDWARE_PROJECT_M81` |
| 较早的社区 hwid | `work/dependencies/hwid-legacy-reference` | 已保存四个真实源码文件，仅覆盖 L2/L3；包含额外 sysfs 接口 |
| 厂商模块集合 | `work/dependencies/sm8450-modules-reference` | 已下载，仅供对照；尚未证明与本内核及 HyperOS 3.0.7.0 配套 |
| 官方 WLAN | `work/dependencies/wlan` | 已有 `liuqin-t-oss` 配套源码，尚未接入完整构建 |
| plaid | `drivers/misc/plaid` | 仍为空目录；上游仅提供 gitlink，缺少来源 URL |

两个 hwid 实现均通过模块参数接收 `project` 和 `hwid_value`，默认值为零。
较早实现的头文件有 SMEM 数据结构定义，但这份实现没有通过 SMEM 自动读取设备标识。
不能仅添加一个猜测的 `M81` 数值，就认为能够正确识别平板。
本树 `cnss2/qmi.c` 使用该常量选择 `bd_m81.elf` 或 `bd_m81gf.elf`，
错误标识会改变 Wi-Fi 校准文件的选择。

社区较新实现也移除了较早实现的部分导出符号与 `/sys/hwid` 接口；
需结合原厂模块的符号需求和初始化脚本核对，不能只判断它自身能否编译。

`plaid` gitlink 固定为 `80a977e60598fe47f66fac17a514a5daa4923df2`。
主仓库没有 `.gitmodules`。已检查 MiCode 及相关 SM8475/SM8450 社区仓库和公开提交搜索，
尚未定位到该提交的可下载实现；搜索无结果不等于证明源码不存在。
保留原有 Kconfig 引用，未创建空桩，也未通过删除引用掩盖缺口。

## 厂商模块参考的边界

下载的模块集合包括 audio、camera、display、video、mmrm、cvp、eva、dataipa、
datarmnet、datarmnet-ext 和 WLAN。它是社区 `evox-a16` 分支，不是小米发布的
`LA.VENDOR.1.0.r1-13100-WAIPIO.0-1` 配套清单。

已查阅的历史表明：

- CS35L43 由 `46e0c6c5205cc576f8ce2c07d484729ce0f78529` 从 `garnet-t-oss` 引入。
- 当前提交 `0df8f5c6d8e85458f9f6cf49dff9aa60d0474989` 注释掉了
  `MMHARDWARE_DETECTION` 相关代码；这不是原厂 liuqin 功能等价的证据。
- 当前分支包含更晚的 Qualcomm 更新，如 WLAN 的
  `LA.VENDOR.1.0.r1-28900-WAIPIO.QSSI16.0`，需要逐模块审查接口与固件匹配。
- camera 的 Makefile 引用了 `sm8450-modules/.../mmrm-driver/Module.symvers`；
  源码目录存在本身并不能使当前内核的构建脚本自动接入它。

因此源码保留在被忽略的参考目录，尚未复制进 `techpack`、覆盖官方 WLAN 或改写设备配置。

## 可重复检查

```powershell
python tools/liuqin/audit-driver-sources.py
powershell -NoProfile -File tools/liuqin/check-dependencies.ps1
```

前一条命令在当前缺失 hwid/plaid 的状态下应返回 1，并列出具体引用和缺失常量。
后一条检查清单中仓库提交及参考文件摘要；通过不代表源码已补齐或可启动。

安装和验证 Clang 的步骤见 [README](README.md)。完整内核构建仍受上述缺失源码阻塞。

已使用安装后的 Clang 在原始工作树上执行 `gki_defconfig`（独立 Linux 输出目录），
实际在 `drivers/misc/Kconfig:552` 报错：

```text
can't open file "drivers/misc/hwid/Kconfig"
```

命令返回 2，日志为 `work/dependencies/toolchains/kconfig-check.log`。
没有修改 Kconfig 来跳过该错误。静态引用检查同时确认下一项 `plaid/Kconfig` 也缺失。
工具链 ARM64/ThinLTO/CFI 测试通过，但配置生成尚未通过，不能进入完整内核构建验收。

## 下一步需要的证据

1. 原厂 `hwid.ko` 对应源码、设备项目编号、模块参数传递方式、导出符号和 sysfs 使用情况。
2. `plaid` 指定提交的仓库 URL 或厂商源码包。
3. 与当前系统对应的厂商模块/BSP 清单、实际内核版本、模块符号版本和配套固件。

设备到手后可先采集 `uname -r`、`/proc/version`、`/sys/module/hwid/parameters/`、
完整系统构建号和模块列表，再核对原厂初始化配置。以上都不需要先刷入新内核。

## 来源

- [较新的 hwid 固定版本](https://github.com/cupid-development/android_kernel_xiaomi_sm8450/tree/060fed194023de6ed41cb25e9a15cfa307b05469/drivers/misc/hwid)
- [较早 hwid 的引入提交](https://github.com/xiaomi-sm8450-kernel/android_kernel_platform_msm-kernel/commit/17deedc1d673d707672cb426036623f8f2216262)
- [厂商模块参考固定版本](https://github.com/Sickyman678/android_kernel_xiaomi_sm8450-modules/tree/0df8f5c6d8e85458f9f6cf49dff9aa60d0474989)
- [CS35L43 的引入提交](https://github.com/Sickyman678/android_kernel_xiaomi_sm8450-modules/commit/46e0c6c5205cc576f8ce2c07d484729ce0f78529)
- [官方内核固定版本](https://github.com/MiCode/Xiaomi_Kernel_OpenSource/tree/eb49e10028e27fa98856cb5e458c0f0ec5b4554e)
