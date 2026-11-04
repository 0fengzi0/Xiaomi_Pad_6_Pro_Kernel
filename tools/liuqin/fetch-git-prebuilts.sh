#!/usr/bin/env bash
# Fallback fetcher: git fetch pinned SHAs directly from googlesource for the
# repositories whose +archive downloads were truncated. Idempotent, marker-based.
# Pins: kernel/superproject common-android12-5.10 @ 557096a98eee (coherent with
# build@dbfab7e0de2e and clang@6e3223f76384).
set -euo pipefail

ROOT=/var/tmp/liuqin-android12-5.10
DL="$ROOT/downloads"
LOG="$DL/fetch-git.log"
mkdir -p "$DL"
log() { echo "[$(date '+%F %T')] $*" | tee -a "$LOG"; }

fetch_git() {
    local url="$1" sha="$2" dest="$3" name="$4"
    local marker="$dest/.pinned-sha"
    mkdir -p "$dest"
    if [[ -f "$marker" ]] && [[ "$(cat "$marker")" == "$sha" ]]; then
        log "SKIP $name (already at $sha)"
        return 0
    fi
    rm -rf "$dest.tmp"
    mkdir -p "$dest.tmp"
    git -C "$dest.tmp" init -q
    git -C "$dest.tmp" remote add origin "$url"
    local attempt
    for attempt in 1 2 3; do
        log "FETCH(git, attempt $attempt) $name @ $sha"
        if git -C "$dest.tmp" -c gc.auto=0 fetch --depth 1 --quiet origin "$sha"; then
            break
        fi
        if [[ "$attempt" == 3 ]]; then
            log "FAIL git fetch $name"
            return 1
        fi
        sleep 10
    done
    git -C "$dest.tmp" -c advice.detachedHead=false checkout -q FETCH_HEAD
    rm -rf "$dest.old"
    mv "$dest" "$dest.old" 2>/dev/null || true
    mv "$dest.tmp" "$dest"
    rm -rf "$dest.old"
    printf '%s\n' "$sha" > "$marker"
    log "OK $name"
}

log "=== fetch-git start ==="
fails=0
fetch_git "https://android.googlesource.com/platform/prebuilts/build-tools" \
    cfedc16ec3deb680fca6fe2aff44a1837a97b50d "$ROOT/prebuilts/build-tools" prebuilts-build-tools || fails=$((fails+1))
fetch_git "https://android.googlesource.com/platform/prebuilts/gcc/linux-x86/host/x86_64-linux-glibc2.17-4.8" \
    4e6f66acf138d40d9a80be24b275abb9c6eed729 \
    "$ROOT/prebuilts/gcc/linux-x86/host/x86_64-linux-glibc2.17-4.8" prebuilts-gcc-sysroot || fails=$((fails+1))
fetch_git "https://android.googlesource.com/kernel/common" \
    c55664ffabc21968048951a4f3dbfe860173548c "$ROOT/common" common || fails=$((fails+1))
# Device-build additions referenced by msm-kernel build.configs but not tracked
# by the ACK superproject; pinned at branch heads resolved 2026-11-04.
fetch_git "https://android.googlesource.com/platform/prebuilts/gas/linux-x86" \
    b2a189331333e014bfef4c0425b3ef4b74accdd0 "$ROOT/prebuilts/gas/linux-x86" prebuilts-gas || fails=$((fails+1))
fetch_git "https://android.googlesource.com/platform/system/libufdt" \
    9b70f594cf149c7c73989c78f03d210f8aa1c1f6 "$ROOT/tools/libufdt" tools-libufdt || fails=$((fails+1))

# Remove truncated archive leftovers from the failed +archive attempts.
rm -f "$DL"/prebuilts-build-tools-*.tar.gz "$DL"/prebuilts-gcc-sysroot-*.tar.gz "$DL"/common-*.tar.gz.part

if [[ $fails -gt 0 ]]; then
    log "=== done with $fails failure(s) ==="
    exit 1
fi
log "=== all git fetches complete ==="
