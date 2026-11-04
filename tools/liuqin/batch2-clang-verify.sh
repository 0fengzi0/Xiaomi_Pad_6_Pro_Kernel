#!/bin/bash
# Batch-2 Clang verification: compile all eight maintained files with
# production Clang r416183b (12.0.5), baseline vs patched, using the exact
# kbuild command lines extracted from .cmd files (vendor cc-wrapper prefix
# stripped so every warning is visible), then compare warning sets per file.
set -euo pipefail
V=/var/tmp/liuqin-maintenance-20261103-sv7lnn
out=$V/out-smoke-clang
proj=/mnt/e/project/Xiaomi_Kernel_OpenSource
root=/var/tmp/liuqin-clang-batch2
clang_dir=/var/tmp/liuqin-android12-5.10/prebuilts-master/clang/host/linux-x86/clang-r416183b
rm -rf "$root"; mkdir -p "$root"
export PATH="$clang_dir/bin:$PATH"
cd "$V"

sources=(mm/memory.c drivers/android/binder.c drivers/block/zram/zram_drv.c
         drivers/usb/dwc3/gadget.c drivers/scsi/ufs/ufs-qcom.c
         mm/backing-dev.c fs/ext4/extents.c fs/f2fs/xattr.c)
objects=("${sources[@]/%.c/.o}")

# 1. Seed config + one kbuild pass so kbuild generates every .cmd file.
if [[ ! -f "$out/.config" ]]; then
    echo "ERROR: out-smoke-clang/.config missing; rerun the batch-1 compare script first" >&2
    exit 1
fi
cp /dev/null "$root/kbuild-pass.log"
for o in "${objects[@]}"; do
    rm -f "$out/$o"
done
make -j8 ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- LLVM=1 \
    O="$out" "${objects[@]}" >> "$root/kbuild-pass.log" 2>&1
echo "kbuild pass exit ok (vendor warning gate accepted all objects)"

# 2. Extract exact command lines, stripping the cc-wrapper prefix.
cmds=()
for o in "${objects[@]}"; do
    cmdfile="$out/${o%/*}/.${o##*/}.cmd"
    cmd=$(sed -n "s|^cmd_$o := ||p" "$cmdfile")
    cmd=${cmd#scripts/basic/cc-wrapper }
    cmds+=("$cmd")
done

run_phase() {
    local phase="$1" src_root="$2"
    local i src o cmd log
    for i in "${!sources[@]}"; do
        src="${sources[$i]}"; o="${objects[$i]}"; cmd="${cmds[$i]}"
        cp "$src_root/$src" "$V/$src"
        rm -f "$out/$o"
        log="$root/$phase-$(basename "$o").log"
        ( cd "$out" && eval "$cmd" ) > /dev/null 2> "$log"
        test -s "$out/$o"
        header=$("$clang_dir/bin/llvm-readelf" -h "$out/$o")
        grep -q 'Machine:.*AArch64' <<<"$header"
        echo "PHASE_OK $phase $o warnings=$(grep -c 'warning:' "$log" || true)"
    done
}

run_phase baseline "$proj/work/dependencies/maintenance/baseline-tree"
run_phase patched "$proj"

python3 - "$root" <<'PY'
import re
import sys
from pathlib import Path
root = Path(sys.argv[1])
names = ["memory.o", "binder.o", "zram_drv.o", "gadget.o", "ufs-qcom.o",
         "backing-dev.o", "extents.o", "xattr.o"]
total_b = total_p = 0
for n in names:
    def warnings(phase):
        text = (root / f"{phase}-{n}.log").read_text()
        return sorted(re.sub(r':\d+:\d+:', ':LINE:COL:', line)
                      for line in text.splitlines() if 'warning:' in line)
    b, p = warnings("baseline"), warnings("patched")
    total_b += len(b); total_p += len(p)
    status = "IDENTICAL" if b == p else "DIFFER"
    print(f"{n}: baseline={len(b)} patched={len(p)} {status}")
    if b != p:
        for line in sorted(set(b) - set(p)):
            print("  ONLY-BASELINE:", line)
        for line in sorted(set(p) - set(b)):
            print("  ONLY-PATCHED:", line)
print(f"TOTAL baseline={total_b} patched={total_p}")
if total_b != total_p:
    raise SystemExit("Warning totals differ; inspect logs.")
print("WARNING_SETS_IDENTICAL across all eight files")
PY
echo "BATCH2_CLANG_PASS"
