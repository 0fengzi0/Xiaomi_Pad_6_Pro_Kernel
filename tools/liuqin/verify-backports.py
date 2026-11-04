#!/usr/bin/env python3
"""Replay the maintenance series and compare it with the working tree.

This verifies patch provenance/reproducibility, not runtime correctness or KMI.
The isolated replay directory is retained under work/dependencies/maintenance.
"""

import hashlib
import json
from pathlib import Path
import subprocess
import tempfile


def run_git(directory, *arguments):
    return subprocess.check_output(
        ["git", "-C", str(directory), *arguments], stderr=subprocess.STDOUT
    )


def main():
    project = Path(__file__).resolve().parents[2]
    # Series replay order: 2026-11-maintenance first, then later batches.
    batch_dirs = [
        project / "tools/liuqin/patches/2026-11-maintenance",
        project / "tools/liuqin/patches/2026-11-batch2",
    ]
    base_revision = None
    changed_files = []
    all_patches = []

    for patch_root in batch_dirs:
        manifest = json.loads((patch_root / "manifest.json").read_text(encoding="utf-8"))
        series = (patch_root / "series").read_text(encoding="utf-8").splitlines()
        if series != [patch["file"] for patch in manifest["patches"]]:
            raise RuntimeError("Patch order differs from manifest: " + str(patch_root))
        if base_revision is None:
            base_revision = manifest["baseRevision"]
        elif manifest.get("baseRevision") != base_revision:
            raise RuntimeError("Batches disagree on baseRevision")
        for filename in manifest["changedFiles"]:
            if filename not in changed_files:
                changed_files.append(filename)
        all_patches.append((patch_root, manifest["patches"]))

    cache = project / "work/dependencies/maintenance"
    cache.mkdir(parents=True, exist_ok=True)
    replay = Path(tempfile.mkdtemp(prefix="replay-", dir=cache))
    run_git(replay, "init", "--quiet")
    run_git(replay, "config", "core.autocrlf", "false")

    for filename in changed_files:
        destination = replay / filename
        destination.parent.mkdir(parents=True, exist_ok=True)
        content = run_git(project, "show", base_revision + ":" + filename)
        destination.write_bytes(content)

    for patch_root, patches in all_patches:
        for patch in patches:
            filename = patch_root / patch["file"]
            digest = hashlib.sha256(filename.read_bytes()).hexdigest()
            if digest != patch["sha256"]:
                raise RuntimeError("Patch checksum mismatch: " + patch["file"])
            run_git(replay, "apply", "--check", str(filename))
            run_git(replay, "apply", str(filename))
            print("REPLAY_OK " + patch["file"], flush=True)

    for filename in changed_files:
        actual = (project / filename).read_bytes()
        expected = (replay / filename).read_bytes()
        if actual != expected:
            raise RuntimeError("Working tree differs from replay: " + filename)
        print("CONTENT_MATCH " + filename, flush=True)

    print("PASS: all patches replay and match; no build/runtime/KMI claim.")
    print("Replay directory: " + str(replay))


if __name__ == "__main__":
    main()
