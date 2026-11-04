#!/bin/bash
set -x
V=/var/tmp/liuqin-maintenance-20261103-sv7lnn
cd "$V"
export PATH=/var/tmp/liuqin-android12-5.10/prebuilts-master/clang/host/linux-x86/clang-r416183b/bin:$PATH
rm -f "$V/out-smoke-clang/mm/memory.o"
ls -la "$V/out-smoke-clang/mm/memory.o" 2>&1
stat -c '%Y' "$V/mm/memory.c"
make V=1 ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- LLVM=1 O="$V/out-smoke-clang" mm/memory.o > /var/tmp/def.log 2>&1
echo "exit=$?"
tail -4 /var/tmp/def.log
stat -c '%Y %n' "$V/out-smoke-clang/mm/memory.o"
