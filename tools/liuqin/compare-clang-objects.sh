#!/bin/bash
# Diagnostic Clang object compilation of the five patched files, mirroring
# work/dependencies/maintenance/compare-objects.sh (which used Debian GCC).
#
# Scope and limits (same as the GCC diagnostic):
#   - Runs in the isolated validation tree recorded in linux-validation-path.txt,
#     where the missing drivers/misc/{hwid,plaid}/Kconfig references are excluded.
#   - Config seeded from diagnostic.config, compiler capability symbols recomputed
#     under Clang; LTO/CFI/GCC_PLUGINS/KASAN/DEBUG_INFO stay off; ZRAM_WRITEBACK,
#     ZRAM_MEMORY_TRACKING forced on so the modified zram branches compile.
#   - Object compile only: no full link, no KMI check, no vendor modules, no device.
#
# Usage:
#   wsl -d Debian -- bash /mnt/e/project/Xiaomi_Kernel_OpenSource/tools/liuqin/compare-clang-objects.sh
set -euo pipefail
project_dir=/mnt/e/project/Xiaomi_Kernel_OpenSource
log_dir="$project_dir/work/dependencies/maintenance"
validation_dir=$(cat "$log_dir/linux-validation-path.txt")
case "$validation_dir" in
    /var/tmp/liuqin-maintenance-20261103-*) ;;
    *) echo 'Unexpected validation directory'; exit 1 ;;
esac
clang_dir=/var/tmp/liuqin-android12-5.10/prebuilts-master/clang/host/linux-x86/clang-r416183b
test -x "$clang_dir/bin/clang"
"$clang_dir/bin/clang" --version | head -n 1
grep -E 'clang version 12.0.5|r416183b' < <("$clang_dir/bin/clang" --version)

# The isolated tree must still have the missing-Kconfig references excluded.
if grep -q 'source "drivers/misc/hwid/Kconfig"' "$validation_dir/drivers/misc/Kconfig"; then
    echo 'Isolated snapshot still references missing hwid Kconfig; refusing to run.'
    exit 1
fi

cd "$validation_dir"
out_dir="$validation_dir/out-smoke-clang"
sources=(mm/memory.c drivers/android/binder.c drivers/block/zram/zram_drv.c
         drivers/usb/dwc3/gadget.c drivers/scsi/ufs/ufs-qcom.c)
objects=("${sources[@]/%.c/.o}")

mkdir -p "$out_dir"
# Seed from the GCC diagnostic config, then force the same diagnostic scope.
cp "$log_dir/diagnostic.config" "$out_dir/.config"
scripts/config --file "$out_dir/.config" \
    -d LTO_CLANG -d LTO_CLANG_FULL -d LTO_CLANG_THIN -e LTO_NONE \
    -d CFI_CLANG -d GCC_PLUGINS -d KASAN -d DEBUG_INFO \
    -e ZRAM_WRITEBACK -e ZRAM_MEMORY_TRACKING
export PATH="$clang_dir/bin:$PATH"
echo "Clang olddefconfig (recomputes compiler capability symbols)"
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- LLVM=1 O="$out_dir" \
    olddefconfig > "$log_dir/clang-olddefconfig.log" 2>&1
grep -E '^CONFIG_(CC_IS_CLANG|CLANG_VERSION|LTO_NONE|ZRAM_WRITEBACK|ZRAM_MEMORY_TRACKING|SCSI_UFS_QCOM|USB_DWC3|ANDROID_BINDER_IPC|ANDROID_VENDOR_HOOKS)=' "$out_dir/.config" | tee -a "$log_dir/clang-olddefconfig.log"
cp "$out_dir/.config" "$log_dir/diagnostic-clang.config"

for phase in baseline patched; do
    source_dir="$project_dir"
    if [ "$phase" = baseline ]; then
        source_dir="$log_dir/baseline-tree"
    fi
    for source_file in "${sources[@]}"; do
        cp "$source_dir/$source_file" "$validation_dir/$source_file"
    done
    echo "Diagnostic Clang compilation: $phase"
    if ! make -j8 ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- LLVM=1 \
        O="$out_dir" "${objects[@]}" > "$log_dir/$phase-clang-objects.log" 2>&1; then
        tail -n 65 "$log_dir/$phase-clang-objects.log"
        exit 1
    fi
    for object_file in "${objects[@]}"; do
        test -s "$out_dir/$object_file"
        # Capture fully before grepping: grep -q exits early and SIGPIPEs
        # llvm-readelf, which intermittently exits 74 (EX_IOERR).
        header=$("$clang_dir/bin/llvm-readelf" -h "$out_dir/$object_file")
        grep -q 'Machine:.*AArch64' <<<"$header"
        echo "AARCH64_OBJECT_OK $phase $object_file"
    done
done

python3 - "$log_dir" <<'PY'
import re
import sys
from pathlib import Path
root = Path(sys.argv[1])
def warnings(name):
    text = (root / name).read_text()
    return sorted(re.sub(r':\d+:\d+:', ':LINE:COL:', line)
                  for line in text.splitlines() if 'warning:' in line)
baseline = warnings('baseline-clang-objects.log')
patched = warnings('patched-clang-objects.log')
print('Baseline Clang warnings:', len(baseline))
print('Patched Clang warnings:', len(patched))
if baseline != patched:
    raise SystemExit('Warning sets differ; inspect logs before accepting diagnostic build.')
print('WARNING_SETS_IDENTICAL: Clang diagnostic objects pass; production warning gate is still unresolved.')
PY
