#!/usr/bin/env python3
"""Report concrete liuqin source gaps; this is not a full compatibility check."""

import json
from pathlib import Path
import re
import subprocess


ROOT = Path(__file__).resolve().parents[2]


def main():
    missing = []
    misc = ROOT / "drivers/misc/Kconfig"
    for line_number, line in enumerate(misc.read_text().splitlines(), 1):
        match = re.match(r'\s*source\s+"([^"]+)"', line)
        if match and not (ROOT / match[1]).is_file():
            missing.append({"source": match[1], "referencedAt": f"drivers/misc/Kconfig:{line_number}"})

    consumers = [
        "drivers/net/wireless/cnss2/qmi.c",
        "drivers/soc/qcom/icnss2/qmi.c",
        "drivers/misc/gpio-testing-mode.c",
    ]
    required = set()
    for consumer in consumers:
        required.update(re.findall(r"\bHARDWARE_PROJECT_[A-Z0-9_]+\b", (ROOT / consumer).read_text()))
    references = []
    for name in ("hwid-reference", "hwid-legacy-reference"):
        header = ROOT / "work/dependencies" / name / "hwid.h"
        defined = set()
        if header.is_file():
            defined.update(re.findall(r"^#define\s+(HARDWARE_PROJECT_[A-Z0-9_]+)\b", header.read_text(), re.M))
        references.append({
            "path": header.relative_to(ROOT).as_posix(),
            "missingProjectDefinitions": sorted(required - defined),
            "integrated": False,
        })
    gitlink = subprocess.check_output(
        ["git", "ls-files", "--stage", "drivers/misc/plaid"], cwd=ROOT, text=True
    ).strip()
    report = {
        "missingLiteralMiscKconfigSources": missing,
        "plaidIndexEntry": gitlink,
        "gitmodulesPresent": (ROOT / ".gitmodules").is_file(),
        "hwidConsumersChecked": consumers,
        "hwidReferences": references,
        "scope": "Direct misc Kconfig includes and HWID project constants only; not a complete build/KMI audit",
    }
    print(json.dumps(report, indent=2))
    return 1 if missing else 0


if __name__ == "__main__":
    raise SystemExit(main())
