#!/usr/bin/env bash
# Read-only collection of vendor kernel modules from a connected liuqin device.
#
# Pulls every .ko under the standard Android module directories plus the module
# metadata lists, via a tar staged in /data/local/tmp. Nothing on the device is
# modified except creating and removing that one staging file. Run the CRC
# extractor over the result afterwards to refresh the KMI baseline.
#
# Usage: tools/liuqin/collect-vendor-modules.sh [OUT_DIR]
set -euo pipefail

OUT="${1:-work/dependencies/device-modules-$(date +%Y%m%d-%H%M%S)}"
STAGING=/data/local/tmp/liuqin-vendor-modules.tar
export MSYS_NO_PATHCONV=1  # stop Git Bash from rewriting /data/... adb args

command -v adb >/dev/null || { echo "adb not on PATH" >&2; exit 1; }
adb get-state >/dev/null 2>&1 || adb wait-for-device

uid="$(adb shell id -u 2>/dev/null | tr -d '\r')"
if [ "$uid" != "0" ]; then
    echo "requesting adb root ..."
    adb root >/dev/null 2>&1 || true
    sleep 2
    adb wait-for-device
    uid="$(adb shell id -u 2>/dev/null | tr -d '\r')"
fi
[ "$uid" = "0" ] || { echo "ERROR: adb shell is not root (uid=$uid); enable ADB Root in KernelSU" >&2; exit 1; }
echo "device root confirmed: uid=0"

mkdir -p "$OUT"

echo "probing module directories ..."
DIRS="$(adb shell 'for d in /vendor_dlkm/lib/modules /vendor/lib/modules /odm/lib/modules /system/lib/modules /system_dlkm/lib/modules; do
    if [ -d "$d" ]; then echo "$d"; fi; done' | tr -d '\r')" || true
[ -n "$DIRS" ] || { echo "ERROR: no module directories found" >&2; exit 1; }
echo "$DIRS" | tee "$OUT/module-dirs.txt"

REL="$(echo "$DIRS" | sed 's|^/||' | tr '\n' ' ')"
echo "packaging on device ..."
adb shell "cd / && tar -cf $STAGING $REL" >/dev/null
adb pull "$STAGING" "$OUT/vendor-modules.tar" >/dev/null
adb shell rm -f "$STAGING"
echo "staging file removed on device"

mkdir -p "$OUT/root"
# /vendor/lib/modules is a symlink to /vendor_dlkm/lib/modules on-device;
# Windows hosts cannot create that symlink, so extract the real tree only.
tar -xf "$OUT/vendor-modules.tar" -C "$OUT/root" vendor_dlkm
find "$OUT/root" -name '*.ko' -type f | wc -l | xargs echo "extracted .ko count:"

echo "collecting module metadata lists ..."
adb shell 'ls /vendor_dlkm/lib/modules/ 2>/dev/null; echo ---; ls /vendor/lib/modules/ 2>/dev/null' \
    | tr -d '\r' > "$OUT/module-listings.txt" || true
adb shell cat /proc/modules | tr -d '\r' > "$OUT/loaded-modules-now.txt"
adb shell uname -a | tr -d '\r' > "$OUT/uname.txt"
cat "$OUT/uname.txt"

echo "done. artifacts in $OUT"
echo "next: python -I tools/liuqin/extract-module-crcs.py <ramdisk-modules-dir> \"$OUT/root\" --out tools/liuqin/baseline/symbol-crcs.json"
