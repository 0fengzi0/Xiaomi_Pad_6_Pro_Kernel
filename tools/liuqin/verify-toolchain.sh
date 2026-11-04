#!/bin/bash
set -euo pipefail

toolchain=${1:-/var/tmp/liuqin-android12-5.10/prebuilts-master/clang/host/linux-x86/clang-r416183b}
test -x "$toolchain/bin/clang"
version=$("$toolchain/bin/clang" --version)
printf '%s\n' "$version"
grep -q 'clang version 12.0.5' <<< "$version"
grep -q 'r416183b' <<< "$version"
"$toolchain/bin/ld.lld" --version

scratch=$(mktemp -d /var/tmp/liuqin-clang-check.XXXXXX)
trap 'rm -rf -- "$scratch"' EXIT
cat > "$scratch/target.c" <<'EOF'
int transform(int value) { return value + 1; }
EOF
cat > "$scratch/caller.c" <<'EOF'
extern int transform(int value);
int (*volatile operation)(int) = transform;
int entry(int value) { return operation(value); }
EOF

"$toolchain/bin/clang" --target=aarch64-linux-gnu -ffreestanding \
    -O2 -Wall -Werror -c "$scratch/target.c" -o "$scratch/target.o"
"$toolchain/bin/llvm-readelf" -h "$scratch/target.o" | grep 'AArch64'

for source in target caller; do
    "$toolchain/bin/clang" --target=aarch64-linux-gnu -ffreestanding \
        -O2 -Wall -Werror -flto=thin -fsanitize=cfi \
        -fvisibility=hidden -c "$scratch/$source.c" -o "$scratch/$source.bc"
done
"$toolchain/bin/ld.lld" -m aarch64elf -e entry \
    "$scratch/target.bc" "$scratch/caller.bc" -o "$scratch/cfi.elf"
"$toolchain/bin/llvm-readelf" -h "$scratch/cfi.elf" | grep 'AArch64'
printf '%s\n' 'PASS: AArch64 object compilation and ThinLTO/CFI link.' \
    'This does not validate a complete kernel, vendor modules or device boot.'
