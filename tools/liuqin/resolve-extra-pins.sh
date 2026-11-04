#!/bin/bash
set -euo pipefail
for repo in platform/prebuilts/gas/linux-x86 platform/system/libufdt; do
    echo "=== $repo ==="
    git ls-remote "https://android.googlesource.com/$repo" refs/heads/master refs/heads/master-kernel-build-2021 2>/dev/null || \
        echo "ls-remote failed"
done
