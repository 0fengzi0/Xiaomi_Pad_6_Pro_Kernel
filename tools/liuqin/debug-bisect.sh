#!/bin/bash
set -u
cd /var/tmp/liuqin-maintenance-20261103-sv7lnn
export PATH=/var/tmp/liuqin-android12-5.10/prebuilts-master/clang/host/linux-x86/clang-r416183b/bin:$PATH
V=/var/tmp/liuqin-maintenance-20261103-sv7lnn
outdir=$V/out-smoke-clang
rm -f "$outdir/mm/memory.o"

try() {
    local name="$1"; shift
    local log="/var/tmp/bisect-$name.log"
    rm -f "$outdir/mm/memory.o"
    make "$@" mm/memory.o > "$log" 2>&1
    echo "$name: exit=$? lines=$(wc -l < "$log")"
}

try A -j8 ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- LLVM=1 O="$outdir"
try B -j8 ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- LLVM=1 O=out-smoke-clang
try C ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- LLVM=1 O="$outdir"
try D ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- LLVM=1 O=out-smoke-clang
try E -j8 ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- LLVM=1 O="$outdir" V=1
