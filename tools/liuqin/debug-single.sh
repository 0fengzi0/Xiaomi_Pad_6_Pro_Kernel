#!/bin/bash
set -x
cd /var/tmp/liuqin-maintenance-20261103-sv7lnn
export PATH=/var/tmp/liuqin-android12-5.10/prebuilts-master/clang/host/linux-x86/clang-r416183b/bin:$PATH
touch mm/memory.c
stat -c '%Y %n' mm/memory.c out-smoke-clang/mm/memory.o
make V=1 ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- LLVM=1 O=out-smoke-clang mm/memory.o > /var/tmp/single.log 2>&1
echo "make_exit=$?"
wc -l /var/tmp/single.log
head -10 /var/tmp/single.log
stat -c '%Y %n' out-smoke-clang/mm/memory.o
