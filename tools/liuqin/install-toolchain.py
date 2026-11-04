#!/usr/bin/env python3
"""Install the pinned Android Clang archive on a Linux filesystem."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tarfile
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--archive", type=Path, required=True)
    parser.add_argument(
        "--destination", type=Path,
        default=Path("/var/tmp/liuqin-android12-5.10/prebuilts-master/clang/host/"
                     "linux-x86/clang-r416183b"),
    )
    args = parser.parse_args()
    if sys.platform != "linux":
        parser.error("Run this installer in WSL/Linux to preserve ELF executables and symlinks.")
    if not hasattr(tarfile, "data_filter"):
        parser.error("Python with tarfile.data_filter is required (Python 3.12+ recommended).")
    archive = args.archive.resolve(strict=True)
    destination = args.destination.resolve()
    if destination.exists():
        parser.error(f"Destination exists; verify it instead of overwriting: {destination}")

    manifest_path = Path(__file__).with_name("dependencies.json")
    manifest = json.loads(manifest_path.read_text(encoding="utf-8-sig"))
    with archive.open("rb") as stream:
        digest = hashlib.file_digest(stream, "sha256").hexdigest()
    expected = manifest["toolchain"].get("archiveSha256")
    if expected and digest != expected:
        raise SystemExit("Archive SHA-256 does not match dependencies.json")
    print(f"Archive SHA-256: {digest}", flush=True)
    destination.parent.mkdir(parents=True, exist_ok=True)
    staging = Path(tempfile.mkdtemp(prefix=".clang-r416183b-", dir=destination.parent))
    try:
        with tarfile.open(archive, "r:gz") as package:
            package.extractall(staging, filter="data")
        result = subprocess.run(
            ["bash", str(Path(__file__).with_name("verify-toolchain.sh")), str(staging)],
            text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        )
        print(result.stdout, end="")
        result.check_returncode()
        os.rename(staging, destination)
    finally:
        if staging.exists():
            shutil.rmtree(staging)
    receipt = {
        "archiveSha256": digest,
        "repositoryRevision": manifest["toolchain"]["repositoryRevision"],
        "installedPath": str(destination),
        "validation": "AArch64 object compilation and ThinLTO/CFI link passed",
        "fullKernelValidated": False,
    }
    (destination / "liuqin-install-receipt.json").write_text(
        json.dumps(receipt, indent=2) + "\n", encoding="utf-8"
    )
    print(f"Installed: {destination}")


if __name__ == "__main__":
    main()
