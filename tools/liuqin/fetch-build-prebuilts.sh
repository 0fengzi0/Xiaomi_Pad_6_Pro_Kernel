#!/usr/bin/env bash
# Fetch the pinned ACK android12-5.10 build prebuilts into the WSL build workspace.
# Pins come from the kernel/superproject branch common-android12-5.10 @ 557096a98eee
# (coherent snapshot that also pins build@dbfab7e0de2e and clang@6e3223f76384).
#
# Usage (from Windows or inside WSL):
#   wsl -d Debian -- bash /mnt/e/project/Xiaomi_Kernel_OpenSource/tools/liuqin/fetch-build-prebuilts.sh
#
# Layout produced under /var/tmp/liuqin-android12-5.10:
#   common/                                       kernel/common           @ c55664ffabc2
#   build/                                        kernel/build            @ dbfab7e0de2e (assembled separately from local clone)
#   prebuilts/build-tools                         platform/prebuilts/build-tools @ cfedc16ec3de
#   prebuilts/kernel-build-tools                  kernel/prebuilts/build-tools   @ ca5b087f88c0
#   prebuilts/gcc/linux-x86/host/x86_64-linux-glibc2.17-4.8 @ 4e6f66acf138
#   tools/mkbootimg                               platform/system/tools/mkbootimg @ 34bc8bfb4934
#   kernel/configs                                kernel/configs          @ c10b7ea022ed
# Archives are cached under downloads/ with sha256 sums; extraction uses the
# Python tarfile 'data' filter (no absolute paths, no .., no special bits).
set -euo pipefail

ROOT=/var/tmp/liuqin-android12-5.10
DL="$ROOT/downloads"
LOG="$DL/fetch.log"
mkdir -p "$DL"

log() { echo "[$(date '+%F %T')] $*" | tee -a "$LOG"; }

fetch_one() {
    local project="$1" sha="$2" dest="$3" name="$4"
    local archive="$DL/${name}-${sha}.tar.gz"
    local marker="$dest/.pinned-sha"
    mkdir -p "$dest"
    if [[ -f "$marker" ]] && [[ "$(cat "$marker")" == "$sha" ]]; then
        log "SKIP $name (already extracted at $sha)"
        return 0
    fi
    if [[ ! -s "$archive" ]]; then
        log "FETCH $name ($project @ $sha)"
        # WSL Debian may lack curl/wget; python3 urllib is the portable path.
        if ! python3 - "$project" "$sha" "$archive.part" <<'PYEOF'
import sys, urllib.request
project, sha, out = sys.argv[1], sys.argv[2], sys.argv[3]
url = f"https://android.googlesource.com/{project}/+archive/{sha}.tar.gz"
req = urllib.request.Request(url, headers={"User-Agent": "liuqin-fetch/1.0"})
with urllib.request.urlopen(req, timeout=600) as resp, open(out, "wb") as fh:
    while True:
        chunk = resp.read(1 << 20)
        if not chunk:
            break
        fh.write(chunk)
PYEOF
        then
            log "FAIL download $name"
            rm -f "$archive.part"
            return 1
        fi
        mv "$archive.part" "$archive"
    fi
    sha256sum "$archive" | tee -a "$LOG"
    log "EXTRACT $name -> $dest"
    rm -rf "$dest.tmp"
    mkdir -p "$dest.tmp"
    if ! python3 - "$archive" "$dest.tmp" <<'PYEOF'
import sys, tarfile
archive, dest = sys.argv[1], sys.argv[2]
with tarfile.open(archive, "r:gz") as tf:
    tf.extractall(dest, filter="data")
PYEOF
    then
        log "FAIL extract $name (archive unusable)"
        rm -rf "$dest.tmp"
        return 1
    fi
    # Atomically swap in the extracted tree
    rm -rf "$dest.old"
    mv "$dest" "$dest.old" 2>/dev/null || true
    mv "$dest.tmp" "$dest"
    rm -rf "$dest.old"
    printf '%s\n' "$sha" > "$marker"
    log "OK $name"
}

log "=== fetch-build-prebuilts start ==="

fails=0
# Small, order-insensitive resources first
fetch_one "platform/system/tools/mkbootimg" 34bc8bfb493401f7aadbd3b434f9fbfa521e9301 "$ROOT/tools/mkbootimg" mkbootimg || fails=$((fails+1))
fetch_one "kernel/configs"                  c10b7ea022edc356d37c092d7ca46bcb860f8a90 "$ROOT/kernel/configs" kernel-configs || fails=$((fails+1))
fetch_one "platform/prebuilts/build-tools"  cfedc16ec3deb680fca6fe2aff44a1837a97b50d "$ROOT/prebuilts/build-tools" prebuilts-build-tools || fails=$((fails+1))
fetch_one "kernel/prebuilts/build-tools"    ca5b087f88c0302ff66f59a6f26be663e92baf15 "$ROOT/prebuilts/kernel-build-tools" prebuilts-kernel-build-tools || fails=$((fails+1))
fetch_one "platform/prebuilts/gcc/linux-x86/host/x86_64-linux-glibc2.17-4.8" \
    4e6f66acf138d40d9a80be24b275abb9c6eed729 \
    "$ROOT/prebuilts/gcc/linux-x86/host/x86_64-linux-glibc2.17-4.8" prebuilts-gcc-sysroot || fails=$((fails+1))
# Large: ACK kernel source tree (needed for build.config inheritance)
fetch_one "kernel/common" c55664ffabc21968048951a4f3dbfe860173548c "$ROOT/common" common || fails=$((fails+1))

if [[ $fails -gt 0 ]]; then
    log "=== done with $fails failure(s) ==="
    exit 1
fi
log "=== all prebuilts fetched and extracted ==="
