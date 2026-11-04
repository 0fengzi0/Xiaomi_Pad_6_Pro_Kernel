#!/bin/bash
set -euxo pipefail
RD=/var/tmp/liuqin-android12-5.10/prebuilts-master/clang/host/linux-x86/clang-r416183b/bin/llvm-readelf
obj=/var/tmp/liuqin-maintenance-20261103-sv7lnn/out-smoke-clang/drivers/scsi/ufs/ufs-qcom.o
set +e
"$RD" -h "$obj" | grep -q 'Machine:.*AArch64'
echo "pipeline_status=$?"
echo AFTER_GREP_1
"$RD" -h "$obj" | grep -q 'Machine:.*AArch64'
rc=$?
echo "pipeline_status2=$rc"
echo AFTER_GREP_2
set -e
"$RD" -h "$obj" | grep -q 'Machine:.*AArch64'
echo AFTER_GREP_3_SET_E
echo DONE
