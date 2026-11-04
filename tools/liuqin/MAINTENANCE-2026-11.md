# Pad 6 Pro：Linux 5.10 首批维护补丁

日期：2026-11-03（首批）、2026-11-04（第二批与构建环境）。目标设备 `liuqin`，
用户报告系统为 HyperOS 3.0.7.0。

## 本次结果和范围

在小米原始提交 `eb49e10028e27fa98856cb5e458c0f0ec5b4554e` 上合入 12 个
Linux 5.10 稳定分支修复，涉及 5 个 C 文件。11 个补丁按稳定分支原文应用；
UFS 时钟门控补丁只调整了上下文以保留厂商后续 Qunipro 设置。

版本继续保持 **5.10.81**。核对时上游为 5.10.273
（`f23b568f7597f98a241454018a34361ce2523c05`），本次没有合入中间全部补丁，
也不代表达到其安全补丁水平。未迁移调度器、GPU 驱动体系、固件或设备树。
WLAN 保留已同步的官方 `liuqin-t-oss` 资源，未更换不匹配的平台分支。

这些修复针对正确性、稳定性和边界保护；没有实机证据表明它们一定提高帧率或续航。

## 补丁清单

完整上游提交、稳定分支提交、补丁文件 SHA-256、顺序和适配说明均保存在
[manifest.json](patches/2026-11-maintenance/manifest.json)。原作者和签署信息保留在补丁中。

| 顺序 | 稳定分支提交 | 改动 |
| --- | --- | --- |
| 1 | `73704c6b35c7` | 修正取消映射时大偏移量的有符号右移 |
| 2 | `15b8095bac72` | 修正页表遍历遇到空项后漏处理后续映射 |
| 3 | `388ee7a4d330` | 修复未注册 Binder 读取线程可能一直等待的问题 |
| 4 | `1677f31bfe15` | 去除错误拒绝合法 Binder 弱引用增加的检查 |
| 5 | `1f96f8c0a6ed` | 在事务锁下读取 Binder 目标进程，配合线程退出同步 |
| 6 | `5602a43f251c` | 固定目标线程临时引用，避免 Binder 事务释放期间目标进程失效 |
| 7 | `98f31cf96f47` | 拒绝大小为零的 zRAM 后备块设备，防止相应自引用配置 |
| 8 | `8823fa063f59` | zRAM 状态遍历的配套整理，保留本分支原有时间单位 |
| 9 | `fee53224c826` | 在初始化读锁内读取 zRAM 大小，避免重设大小后越界 |
| 10 | `b43225948b23` | 拒绝超出 DWC3 事件缓冲区长度的事件计数 |
| 11 | `d113c66bb4ae` | UFS 时钟计时寄存器写入后读回，确认写入到达设备 |
| 12 | `dca975427630` | UFS 硬件时钟门控设置后读回，保留小米其余时钟处理 |

其中补丁 5、6 配套保留，补丁 8、9 配套保留。zRAM 的 2021 年边界修复
`7091fcc75ff6` 已在基线中，未重复应用。
Binder 的 `3a8154bb4ab4` 修复依赖本基线没有的新事务复制流程，未强行套用；
这并不意味着旧复制流程已经完成安全审计。
UFS 的 `c8f2eefc496e` 屏障删除暂未选择，避免在缺少运行时验证时扩大移植范围。

## 已执行验证

1. **补丁重放通过**：从原始提交提取五个文件，在隔离临时仓库按顺序应用全部补丁，
   验证补丁 SHA-256，并与工作目录逐字节比较，五个文件全部一致。
2. **代码检查通过**：`git diff --check`；内核自带 `checkpatch.pl`
   检查合并后的 C 代码差异，结果为 0 errors、0 warnings。
3. **页表控制流程回归测试通过**：直接提取 `mm/memory.c` 的
   `apply_to_pte_range()` 编译测试。基线在“开头空项”和“中间空项”场景失败；
   更新后这两项以及“创建时访问所有项”“回调报错时停止”四项均通过。
   页表基础操作及锁为模拟实现，不验证真实 MMU 或并发行为。
4. **AArch64 诊断对象编译通过**：原始和更新后源码的 `memory.o`、`binder.o`、
   `zram_drv.o`、`gadget.o`、`ufs-qcom.o` 均生成有效 AArch64 ELF 对象。
   工具为 Debian GCC 14.2.0；基线和更新后各有 32 条编译告警，去掉行列号后集合一致，
   没有新增告警。

### 编译验证的限制

生产构建尚未通过，`buildValidated` 继续为 `false`。

- 原始 Kconfig 在缺失 `drivers/misc/hwid/Kconfig` 处失败。
  `plaid` 是未检出的 Git 子模块引用，提交为
  `80a977e60598fe47f66fac17a514a5daa4923df2`，没有 `.gitmodules` 地址。
- 诊断使用独立 Linux 源码副本；仅在该副本移除上述两个缺失 Kconfig 的引用。
  主工作目录没有删除对应引用，也没有放置空实现。
- 测试配置由 `gki_defconfig` 和 `liuqin_GKI.config` 合并，采用 GCC，
  未启用生产 Clang 的 LTO/CFI；未启用 KASAN 和调试信息。
  明确启用 `ZRAM_WRITEBACK`、`ZRAM_MEMORY_TRACKING`，保证修改分支进入编译；
  Binder、厂商 hooks、UFS QCOM 和 USB DWC3 保持启用。
- 原有厂商 `cc-wrapper` 会将 GCC 告警判为失败。严格尝试确实失败，日志保留；
  后续仅在诊断命令使用 `CC=aarch64-linux-gnu-gcc`，保留所有告警以对比修改前后。
  没有修改项目的告警策略。这不算通过生产告警门槛。
- 未链接完整内核、未执行 KMI/ABI 对比、未启动内核、未测试厂商模块或刷写设备。
  对象编译不能证明 HyperOS 3.0.7.0 兼容性。

日志、诊断配置、隔离构建脚本保存在本地忽略目录 `work/dependencies/maintenance/`：
`compile.log` 是严格编译尝试，`baseline-objects.log` / `patched-objects.log`
是对象诊断对照，`diagnostic.config` 是实际配置。
`linux-validation-path.txt` 记录 WSL 中的隔离源码副本位置。

## 复核命令

从项目根目录运行：

```powershell
python tools/liuqin/verify-backports.py
git diff --check

# Windows Git 自带的 Perl 可运行本项目 checkpatch；仅省略提交签署检查。
& 'C:\Program Files\Git\usr\bin\perl.exe' scripts/checkpatch.pl --no-tree --no-signoff work/dependencies/maintenance/combined.patch

# Linux 主机回归测试；--baseline 可额外传入原始提交的 memory.c。
wsl -d Debian -- python3 /mnt/e/project/Xiaomi_Kernel_OpenSource/tools/liuqin/test-pte-walk.py
```

`verify-backports.py` 自 2026-11-04 起按顺序重放两个批次目录
（`2026-11-maintenance` → `2026-11-batch2`），共 19 个补丁。
Clang 对象验证脚本保存在 `tools/liuqin/batch2-clang-verify.sh`
（在 WSL ext4 内运行；直接从 `/mnt/e` 执行脚本在本机不可靠）。

`combined.patch` 是本次本地差异快照，后续源码改动后需重新生成再检查。
回放脚本核对当前文件内容，后续继续修改这五个文件时应同步维护补丁序列和清单。

## 第二批维护补丁（2026-11-04）

在第一批之上再合入 7 个 linux-5.10.y 修复，扫描范围为 v5.10.82..v5.10.90，
重点覆盖 ext4/f2fs 文件系统完整性、dwc3 gadget 与 writeback。补丁清单、上游
提交、SHA-256 与适配说明见 [batch2 manifest](patches/2026-11-batch2/manifest.json)：

| 顺序 | 稳定分支提交 | 改动 |
| --- | --- | --- |
| 1 | `3abf746e800b` | dwc3：END_TRANSFER 后忽略下一个 NoStream 事件（移动标志设置时机） |
| 2 | `140e2df472ba` | dwc3：Start Transfer 仅在 SuperSpeed U3、低速链路 U2 时触发远程唤醒 |
| 3 | `c581090228e3` | bdi 注销时归还 min_ratio，避免全局 bdi_min_ratio 只增不减 |
| 4 | `1d4b1c4e8bbd` | ext4：extent 块更新失败时不写回部分修改的 extent 块 |
| 5 | `76366c024f56` | ext4：校验索引 extent 无乱序 |
| 6 | `0875873b2a97` | ext4：校验索引块与叶块 extent 一致（应用时用 `--fuzz=3` 调整上下文，语义未变） |
| 7 | `fffb6581a23a` | f2fs：对最后一个 xattr 项做越界检查，防止畸形 xattr 触发越界读取 |

版本仍保持 5.10.81；累计 19 个补丁，涉及 8 个 C 文件。

**同批确认已存在而未重复合入的候选**（详见 manifest `notApplied`）：
UFS 任务管理完成及其超时竞态修复（厂商 ufshcd.c 已用等价的 `tmf_rqs`
实现）、dwc3 空指针保护、Binder `wake_up_pollfree()`、Binder 空事务
`async_free_space` 记账——这五项反向补丁检查或代码比对均确认基线已含等价实现。
mm/mempolicy THP 与 hugetlbfs TLB 修复因诊断配置无法编译对应文件（未启用
`CONFIG_NUMA`/`CONFIG_HUGETLBFS`）暂不合入；binder sender_euid 修复带行为变化，
不与前置补丁一起引入。

### 第二批验证

1. **补丁重放通过**：`verify-backports.py` 已扩展为按批次目录顺序重放，
   19 个补丁从原始提交重放后与工作目录逐字节一致（8 个文件）。
2. **checkpatch 通过**：重新生成的 `combined.patch`（520 行）0 errors、0 warnings。
3. **Clang 对象编译通过**：8 个文件全部用生产 Clang r416183b (12.0.5) 做了
   基线/补丁后 AArch64 对象编译。方法是先跑一次 kbuild 生成 `.cmd`，再剥掉
   厂商 `cc-wrapper` 前缀直接执行相同命令行，逐文件捕获全部告警：
   基线与补丁后均为 0 告警，集合一致。另一次保留 `cc-wrapper` 的 kbuild
   对象编译也通过（该包装器会把未豁免的告警判为失败），与直接编译互为印证。
   说明：5.10 内核对单目标 make 天然静默（`single-build=1` 会命中
   `findstring s` 的静默判定），告警只走 stderr，因此不能以"日志没有
   CC 行"判断编译未发生。
4. **排查记录**：诊断中发现 `llvm-readelf | grep -q` 会因 SIGPIPE 间歇性
   返回 74 导致脚本中断，已改为先完整捕获输出再 grep；WSL 对 `/mnt/e`
   的读写在本次环境不稳定，验证脚本与日志一律放在 WSL ext4，最后才拷回。

## 构建环境补齐（2026-11-04）

按 ACK `common-android12-5.10` manifest 与 superproject 快照
（`557096a98eee`，其中 build 固定于 `dbfab7e0de2e`、clang 固定于 `6e3223f76384`，
与我们已有资源完全一致）在 WSL Debian 组装了完整构建工作区
`/var/tmp/liuqin-android12-5.10/`：

| 路径 | 资源 | 固定提交 |
| --- | --- | --- |
| `build/` | kernel/build（含 106 个 hermetic 工具符号链接） | `dbfab7e0de2e` |
| `common/` | kernel/common android12-5.10（84954 个文件，SUBLEVEL 270） | `c55664ffabc2` |
| `prebuilts/build-tools` | platform/prebuilts/build-tools | `cfedc16ec3de` |
| `prebuilts/kernel-build-tools` | kernel/prebuilts/build-tools（hermetic dtc、depmod、avbtool、mkdtboimg.py 等） | `ca5b087f88c0` |
| `prebuilts/gcc/.../x86_64-linux-glibc2.17-4.8` | hermetic host sysroot | `4e6f66acf138` |
| `prebuilts/gas/linux-x86` | GNU as（msm 构建脚本引用，superproject 未跟踪，按分支头固定） | `b2a189331333` |
| `tools/mkbootimg` | mkbootimg.py / unpack_bootimg.py（boot 头 v3/v4） | `34bc8bfb4934` |
| `tools/libufdt` | ufdt overlay 工具（superproject 未跟踪，按 master 头固定） | `9b70f594cf14` |
| `kernel/configs` | kernel/configs | `c10b7ea022ed` |
| `msm-kernel/` | 本仓库 @ `eb49e10028e` + 19 补丁 + 设备树（4433 文件） | — |
| `prebuilts-master/clang/.../clang-r416183b` | 生产 Clang（已装） | `6e3223f76384` |

符号链接审计：msm-kernel 43 个、build 106 个 git 符号链接全部恢复为真实链接
且目标存在（broken=0）；common 内 `find -type l` 审计同样 0 断链。
工具烟雾测试：hermetic dtc 1.6.0-Android-build、python 3.9.1、make 4.3、
mkdtboimg.py、mkbootimg.py、unpack_bootimg.py、clang/LLD 12.0.5 全部可执行。

`build/build.sh BUILD_CONFIG=msm-kernel/build.config.msm.liuqin` 自检：
环境解析全部成功（PATH 指向 hermetic 工具、clang、gas），`consolidate` 变体
会因当前 ACK common 已移除 `build.config.gki_consolidate.aarch64` 而中断
（时代偏差，见下），`VARIANT=gki` 变体配置链完整通过并进入实际内核编译。
gki 变体先编译 ACK common 的 GKI 内核：`gki_defconfig` 配置生成、2663 个
编译单元（对象/内置库成员）在生产 Clang 下全部通过；最终在 `LTO vmlinux.o`
链接处被系统终止
（`Killed`）——本机 `.wslconfig` 限制 WSL 仅 2 GB 内存/1 CPU，而 ThinLTO
vmlinux 链接需要数十 GB 内存。这是宿主机资源限制而非环境缺口；日志在
WSL `/var/tmp/build-selfcheck2.log`。设备内核（msm-kernel 阶段）尚未开始，
仍会先被 hwid/plaid 缺失阻断。若日后要尝试完整链接，需要提高 `.wslconfig`
的 memory 限制（并预期单核下耗时以小时计）。

仍存在的阻塞（未变）：

1. `drivers/misc/hwid/Kconfig` 与 `plaid` 缺失——设备内核配置生成
   （msm-kernel 阶段）仍会在此失败；工作区构建已在等待验证这一步。
2. `consolidate` 变体依赖的 ACK common 文件已不存在：我们固定的 common 是
   当前分支头（5.10.270 时代），而小米 5.10.81 时代的 msm-kernel 构建脚本
   引用当时还存在的 consolidate 配置。`gki` 变体不受影响；若必须复现
   consolidate，需要把 common 固定到 2022 年初的 android12-5.10 提交。

## 下一阶段门槛

需获得设备实际 `uname -r`、`/proc/version`、完整系统版本和匹配的厂商模块信息，
补齐 `hwid`、`plaid` 及外部驱动资源，使用匹配的 Android Clang 建立生产构建。
通过编译、KMI 检查和可恢复的启动测试后，才能扩大稳定补丁合并范围。
实机验收至少覆盖应用启动/切换、USB/ADB、存储读写与休眠唤醒、zRAM 压力、
Wi-Fi、音频、充电、触控笔和待机功耗。
