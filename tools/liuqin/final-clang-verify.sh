#!/bin/bash
# Final Clang diagnostic: real recompiles with logs on ext4, object checks,
# warning-set comparison, then publish artifacts to the Windows-side log dir.
set -euo pipefail
project_dir=/mnt/e/project/Xiaomi_Kernel_OpenSource
out_root=/var/tmp/liuqin-clang-final
validation_dir=/var/tmp/liuqin-maintenance-20261103-sv7lnn
clang_dir=/var/tmp/liuqin-android12-5.10/prebuilts-master/clang/host/linux-x86/clang-r416183b
rm -rf "$out_root"
mkdir -p "$out_root"
export PATH="$clang_dir/bin:$PATH"
cd "$validation_dir"

sources=(mm/memory.c drivers/android/binder.c drivers/block/zram/zram_drv.c
         drivers/usb/dwc3/gadget.c drivers/scsi/ufs/ufs-qcom.c)
objects=("${sources[@]/%.c/.o}")

run_phase() {
    local phase="$1" src_root="$2" log="$out_root/$1-clang-objects.log"
    local source_file
    for source_file in "${sources[@]}"; do
        cp "$src_root/$source_file" "$validation_dir/$source_file"
    done
    # Touch to force real recompiles regardless of drvfs mtime quirks.
    for source_file in "${sources[@]}"; do
        touch "$validation_dir/$source_file"
    done
    make -j8 ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- LLVM=1 \
        O="$validation_dir/out-smoke-clang" "${objects[@]}" > "$log" 2>&1
    local cc_lines
    cc_lines=$(grep -cE '^(  (CC|GEN)|CC|SYNC|HOSTCC)' "$log" || true)
    echo "PHASE $phase: make exit ok, command-echo lines=$cc_lines"
    if [ "$cc_lines" -lt 5 ]; then
        echo "ERROR: fewer than 5 compile commands recorded; logs unreliable" >&2
        tail -20 "$log" >&2
        exit 1
    fi
    local object_file header
    for object_file in "${objects[@]}"; do
        test -s "$validation_dir/out-smoke-clang/$object_file"
        header=$("$clang_dir/bin/llvm-readelf" -h "$validation_dir/out-smoke-clang/$object_file")
        grep -q 'Machine:.*AArch64' <<<"$header"
        echo "AARCH64_OBJECT_OK $phase $object_file"
    done
}

echo "Clang: $("$clang_dir/bin/clang" --version | head -n 1)"
run_phase baseline "$project_dir/work/dependencies/maintenance/baseline-tree"
run_phase patched "$project_dir"

python3 - "$out_root" <<'PY'
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
print('WARNING_SETS_IDENTICAL: Clang diagnostic objects pass.')
PY

# Publish artifacts to the Windows-side log directory (copied from ext4).
log_dir="$project_dir/work/dependencies/maintenance"
cp "$out_root/baseline-clang-objects.log" "$out_root/patched-clang-objects.log" "$log_dir/"
cp "$validation_dir/out-smoke-clang/.config" "$log_dir/diagnostic-clang.config"
sha256sum "$out_root/baseline-clang-objects.log" "$out_root/patched-clang-objects.log" \
          "$log_dir/diagnostic-clang.config" > "$out_root/artifacts.sha256"
echo "PUBLISHED artifacts; hashes in $out_root/artifacts.sha256"
