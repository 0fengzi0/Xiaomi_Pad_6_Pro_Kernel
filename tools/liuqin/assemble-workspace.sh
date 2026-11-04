#!/usr/bin/env bash
# Assemble the Linux build workspace under /var/tmp/liuqin-android12-5.10:
#   build/       kernel/build @ dbfab7e0de2e (cloned from the local Windows checkout)
#   msm-kernel/  this repo @ eb49e10028e + fresh 5-file maintenance diff + vendor devicetree
# Then audit every git symlink in msm-kernel/, build/ and common/ for missing targets,
# and smoke-test the hermetic host tools.
set -euo pipefail
ROOT=/var/tmp/liuqin-android12-5.10
LOG="$ROOT/downloads/assemble.log"
PROJ=/mnt/e/project/Xiaomi_Kernel_OpenSource
log() { echo "[$(date '+%F %T')] $*" | tee -a "$LOG"; }

log "=== assemble-workspace start ==="

# --- build/ from the pinned local clone -------------------------------------
if [[ ! -d "$ROOT/build/.git" ]]; then
    log "CLONE build from local android-build checkout"
    git clone --quiet --no-local "$PROJ/work/dependencies/android-build" "$ROOT/build"
fi
git -C "$ROOT/build" checkout --quiet dbfab7e0de2e04316b526ef938b1140d7a5fd40d
log "build HEAD: $(git -C "$ROOT/build" rev-parse HEAD)"

# --- msm-kernel/ from the pinned local kernel repo ---------------------------
if [[ ! -d "$ROOT/msm-kernel/.git" ]]; then
    log "CLONE msm-kernel from local kernel checkout"
    git clone --quiet --no-local "$PROJ" "$ROOT/msm-kernel"
fi
git -C "$ROOT/msm-kernel" checkout --quiet liuqin-t-oss
log "msm-kernel HEAD: $(git -C "$ROOT/msm-kernel" rev-parse HEAD)"
# Reapply the maintenance diff idempotently; verify it matches the E: tree.
git -C "$ROOT/msm-kernel" apply --whitespace=nowarn /var/tmp/liuqin-5files.patch 2>>"$LOG" || true
for f in mm/memory.c drivers/android/binder.c drivers/block/zram/zram_drv.c \
         drivers/usb/dwc3/gadget.c drivers/scsi/ufs/ufs-qcom.c; do
    cmp "$PROJ/$f" "$ROOT/msm-kernel/$f"
done
log "msm-kernel five files byte-identical to the Windows working tree"

# --- vendor devicetree into the Kbuild-consumed path -------------------------
DT_SRC="$PROJ/arch/arm64/boot/dts/vendor"
DT_DST="$ROOT/msm-kernel/arch/arm64/boot/dts/vendor"
rm -rf "$DT_DST"
mkdir -p "$DT_DST"
(cd "$DT_SRC" && tar cf - --exclude=.git .) | (cd "$DT_DST" && tar xf -)
src_n=$(find "$DT_SRC" -type f -not -path "*/.git/*" | wc -l)
dst_n=$(find "$DT_DST" -type f | wc -l)
if [[ "$src_n" != "$dst_n" ]]; then
    log "FAIL devicetree copy: $src_n source files vs $dst_n copied"
    exit 1
fi
log "devicetree copied: $dst_n files (matches source count)"

# --- symlink audit ------------------------------------------------------------
audit_symlinks() {
    local dir="$1" name="$2" broken=0
    while IFS=$'\t' read -r mode sha stage path; do
        [[ "$mode" == 120000 ]] || continue
        local target full
        target=$(git -C "$dir" cat-file blob "$sha")
        full="$dir/$(dirname "$path")/$target"
        if [[ ! -e "$full" ]]; then
            echo "MISSING_LINK $name: $path -> $target"
            broken=$((broken+1))
        fi
    done < <(git -C "$dir" ls-files -s)
    echo "SYMLINK_AUDIT $name: broken=$broken"
    [[ $broken -eq 0 ]]
}

audit_symlinks "$ROOT/msm-kernel" msm-kernel || true
audit_symlinks "$ROOT/build" build || true
audit_symlinks "$ROOT/common" common || true

# --- hermetic tool smoke tests -------------------------------------------------
BT="$ROOT/build/build-tools/path/linux-x86"
CLANG="$ROOT/prebuilts-master/clang/host/linux-x86/clang-r416183b/bin"
"$BT/dtc" --version | head -n 1
"$BT/python3" --version
"$BT/make" --version | head -n 1
"$BT/depmod" --version 2>/dev/null || echo "depmod: (kmod without --version output)"
python3 "$BT/mkdtboimg.py" version 2>&1 | head -n 1 || true
python3 "$ROOT/tools/mkbootimg/mkbootimg.py" --help >/dev/null && echo "mkbootimg.py OK"
python3 "$ROOT/tools/mkbootimg/unpack_bootimg.py" --help >/dev/null && echo "unpack_bootimg.py OK"
"$CLANG/clang" --version | head -n 1
log "=== assemble-workspace done ==="
