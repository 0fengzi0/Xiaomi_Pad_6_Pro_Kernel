#!/bin/bash
# Resolve full SHAs and containing stable releases for the batch-2 candidate
# commits from linux-5.10.y (v5.10.82..v5.10.90).
set -euo pipefail
META=/var/tmp/stable-meta
rm -rf "$META"
mkdir -p "$META"
cd "$META"
git init -q
git remote add origin https://github.com/gregkh/linux
refs=()
for n in 82 83 84 85 86 87 88 89 90; do
    refs+=("refs/tags/v5.10.$n:refs/tags/v5.10.$n")
done
git fetch --quiet --filter=tree:0 --no-tags origin "${refs[@]}"
git fetch --quiet --filter=tree:0 origin refs/heads/linux-5.10.y:refs/heads/linux-5.10.y

shorts=(9f3acee7eac8 1cb8444f3114 ddd4e46cff40 86ab0f8ff008 0755f3f3 140e2df4 3abf746e \
        1d4b1c4e8bbd 76366c024f56 0875873b2a97 fffb658 c581090228e3)
for s in "${shorts[@]}"; do
    full=$(git rev-parse "${s}^{commit}")
    subject=$(git log -1 --format=%s "$full")
    release=$(git tag --contains "$full" | sort -V | head -n 1)
    date=$(git log -1 --format=%cI "$full")
    printf '%s %s %s %s\n' "$full" "${release:-BEYOND-v5.10.90}" "$date" "$subject"
done
