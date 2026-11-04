#!/bin/bash
# Verify the two phase logs contain real compiler invocations and the objects
# are fresh relative to the copied sources.
cd /var/tmp/liuqin-maintenance-20261103-sv7lnn
for log in /mnt/e/project/Xiaomi_Kernel_OpenSource/work/dependencies/maintenance/baseline-clang-objects.log \
           /mnt/e/project/Xiaomi_Kernel_OpenSource/work/dependencies/maintenance/patched-clang-objects.log; do
    echo "=== $(basename "$log") ($(wc -l < "$log") lines) ==="
    grep -cE '^(CC|LD|HOSTCC)' "$log" 2>/dev/null || true
    grep -E '^\s*(CC|clang).*(memory|binder|zram_drv|gadget|ufs-qcom)\.c' "$log" | head -6
done
echo "=== object vs source mtimes ==="
for pair in "mm/memory.c out-smoke-clang/mm/memory.o" \
            "drivers/android/binder.c out-smoke-clang/drivers/android/binder.o" \
            "drivers/block/zram/zram_drv.c out-smoke-clang/drivers/block/zram/zram_drv.o" \
            "drivers/usb/dwc3/gadget.c out-smoke-clang/drivers/usb/dwc3/gadget.o" \
            "drivers/scsi/ufs/ufs-qcom.c out-smoke-clang/drivers/scsi/ufs/ufs-qcom.o"; do
    set -- $pair
    echo "$(stat -c '%Y' "$1") $1   $(stat -c '%Y' "$2") $2"
done
