#!/bin/bash
set -euo pipefail
cd /var/tmp/stable-meta
git rev-parse c581090228e3^{commit}
echo "=== per-release order ==="
prev=v5.10.81
# fetch the v5.10.81 tag too for range boundaries
git fetch --quiet --filter=tree:0 --no-tags origin refs/tags/v5.10.81:refs/tags/v5.10.81 || true
for n in 82 83 84 85 86 87 88 89 90; do
    cur=v5.10.$n
    echo "--- $cur ---"
    git rev-list --reverse "$cur" ^"$prev" 2>/dev/null | while read -r c; do
        s=$(git log -1 --format=%s "$c")
        case "$s" in
            *"binder"*|*"dwc3"*|*"ufs"*|*"ext4"*|*"f2fs"*|*"bdi"*|*"memblock"*) echo "$c $s" ;;
        esac
    done
    prev=$cur
done
