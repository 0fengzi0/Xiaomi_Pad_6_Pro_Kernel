#!/usr/bin/env python3
"""Extract per-module symbol CRC evidence from ARM64 Linux kernel .ko files.

Pure standard-library ELF64 parser (no third-party deps). Reproduces the
manual evidence format recorded in work/dependencies/device-baseline-*/module-abi.json
(see tools/liuqin/DEVICE-BASELINE-2026-11-04.md):

- ``.modinfo``      -> module name, vermagic, scmversion, ...
- ``__versions``    -> imported symbol CRCs (struct modversion_info entries)
- ``.symtab``       -> undefined symbols; SHN_ABS entries carry the CRC of
                       symbols this module exports (referenced from
                       ``.rela___kcrctab+<sym>``), names cross-checked
                       against ``__ksymtab_strings``

Usage:
  python extract-module-crcs.py FILE.ko [DIR ...] --out abi.json --abi
  python extract-module-crcs.py FILE.ko [DIR ...] --out baseline.json
  python extract-module-crcs.py FILE.ko ... --validate module-abi.json

``--abi`` writes {"modules": [...]} matching the manual baseline layout so the
two can be diffed. Without it, writes an aggregated symbol baseline for the
GitHub Actions KMI check (check-kmi.py).
"""

import argparse
import hashlib
import json
import struct
import sys
from datetime import datetime, timezone
from pathlib import Path

SHT_SYMTAB = 2
SHN_UNDEF = 0
SHN_ABS = 0xFFF1
SYMTAB_ENTRY = 24


def fail(msg):
    print(f"ERROR: {msg}", file=sys.stderr)
    sys.exit(1)


def parse_sections(data):
    e_shoff, = struct.unpack_from("<Q", data, 0x28)
    e_shentsize, e_shnum, e_shstrndx = struct.unpack_from("<HHH", data, 0x3A)
    if e_shentsize != 64:
        fail(f"unexpected section header entry size {e_shentsize}")
    raw = [struct.unpack_from("<IIQQQQIIQQ", data, e_shoff + i * e_shentsize)
           for i in range(e_shnum)]
    names = data[raw[e_shstrndx][4]:raw[e_shstrndx][4] + raw[e_shstrndx][5]]
    secs = []
    for r in raw:
        end = names.index(b"\x00", r[0])
        secs.append({"name": names[r[0]:end].decode("ascii", "replace"),
                     "type": r[1], "offset": r[4], "size": r[5],
                     "link": r[6], "entsize": r[9]})
    return secs


def parse_modinfo(data, sec):
    blob = data[sec["offset"]:sec["offset"] + sec["size"]]
    mod = {}
    for item in blob.split(b"\x00"):
        if not item:
            continue
        key, _, val = item.partition(b"=")
        mod.setdefault(key.decode("ascii", "replace"), []).append(
            val.decode("ascii", "replace"))
    return mod


def parse_imports(data, sec):
    """__versions: fixed-size entries of (u32 crc @0, char name[] @8); the
    device modules use a 64-byte stride with a 56-byte name field. Detect the
    stride by divisibility plus printable, null-terminated names."""
    blob = data[sec["offset"]:sec["offset"] + sec["size"]]
    if not blob:
        return {}  # module built without MODVERSIONS imports
    for esz in (64, 60):
        if len(blob) % esz:
            continue
        entries, ok = [], True
        for off in range(0, len(blob), esz):
            crc, = struct.unpack_from("<I", blob, off)
            raw = blob[off + 8:off + esz].split(b"\x00")[0]
            if not raw or any(not (32 <= b < 127) for b in raw):
                ok = False
                break
            entries.append((crc, raw.decode("ascii")))
        if ok and entries:
            return {n: format(crc, "08x") for crc, n in entries if crc and n}
    fail(f"cannot parse __versions ({sec['size']} bytes) in module")


def parse_symtab(data, secs, ksym_names):
    """Return (undefined symbols, exported {name: crc}) from .symtab."""
    undefined, exports = [], {}
    st = next((s for s in secs if s["type"] == SHT_SYMTAB), None)
    if st is None:
        return undefined, exports
    strsec = secs[st["link"]]
    strdata = data[strsec["offset"]:strsec["offset"] + strsec["size"]]
    blob = data[st["offset"]:st["offset"] + st["size"]]
    for off in range(0, len(blob), SYMTAB_ENTRY):
        st_name, st_info, _other, st_shndx, st_value, _size = struct.unpack_from(
            "<IBBHQQ", blob, off)
        if not st_name:
            continue
        end = strdata.index(b"\x00", st_name)
        name = strdata[st_name:end].decode("ascii", "replace")
        if st_shndx == SHN_UNDEF:
            undefined.append(name)
        elif st_shndx == SHN_ABS and name.startswith("__crc_"):
            # MODVERSIONS export: __crc_<symbol> SHN_ABS entry whose value
            # is the CRC (referenced from .rela___kcrctab+<symbol>)
            sym = name[len("__crc_"):]
            if not ksym_names or sym in ksym_names:
                exports[sym] = format(st_value & 0xFFFFFFFF, "08x")
    return undefined, exports


def extract_module(path):
    data = Path(path).read_bytes()
    if data[:4] != b"\x7fELF" or data[4] != 2 or data[5] != 1:
        fail(f"{path}: not a little-endian ELF64 object")
    secs = parse_sections(data)
    by_name = {s["name"]: s for s in secs}
    for required in (".modinfo", "__versions"):
        if required not in by_name:
            fail(f"{path}: missing section {required}")
    ksym_names = set()
    if "__ksymtab_strings" in by_name:
        s = by_name["__ksymtab_strings"]
        kb = data[s["offset"]:s["offset"] + s["size"]]
        ksym_names = {x.decode("ascii", "replace") for x in kb.split(b"\x00") if x}
    undefined, exports = parse_symtab(data, secs, ksym_names)
    return {
        "file": Path(path).as_posix(),
        "bytes": len(data),
        "sha256": hashlib.sha256(data).hexdigest(),
        "architecture": "AArch64 ELF64 little-endian",
        "modinfo": parse_modinfo(data, by_name[".modinfo"]),
        "exportedSymbolCRCs": exports,
        "importedSymbolCRCs": parse_imports(data, by_name["__versions"]),
        "undefinedSymbols": undefined,
    }


def collect(inputs):
    modules, seen = [], set()
    for item in inputs:
        p = Path(item)
        files = sorted(p.glob("*.ko")) if p.is_dir() else [p]
        for f in files:
            m = extract_module(f)
            if m["sha256"] in seen:
                continue  # same module shipped in several locations
            seen.add(m["sha256"])
            modules.append(m)
    if not modules:
        fail("no .ko inputs found")
    return modules


def write_abi(modules, out):
    doc = {"modules": modules,
           "scope": "Static ELF metadata and imported/exported symbol CRCs "
                    "extracted by tools/liuqin/extract-module-crcs.py. Static "
                    "evidence only, not a runtime compatibility statement."}
    Path(out).write_text(json.dumps(doc, indent=2) + "\n", encoding="utf-8")


def write_baseline(modules, out):
    symbols, conflicts, providers = {}, {}, {}
    for m in modules:
        mod = m["modinfo"].get("name", ["?"])[0]
        for sym, crc in m["importedSymbolCRCs"].items():
            if sym in symbols and symbols[sym] != crc:
                conflicts.setdefault(sym, {}).setdefault(symbols[sym], []).append(mod)
                conflicts[sym].setdefault(crc, []).append(mod)
            symbols.setdefault(sym, crc)
        for sym, crc in m["exportedSymbolCRCs"].items():
            providers.setdefault(sym, {}).setdefault(crc, []).append(mod)
    doc = {
        "schema": 1,
        "generatedOn": datetime.now(timezone.utc).strftime("%Y-%m-%d"),
        "generator": "tools/liuqin/extract-module-crcs.py",
        "moduleCount": len(modules),
        "sourceModules": [
            {"name": m["modinfo"].get("name", ["?"])[0], "file": m["file"],
             "bytes": m["bytes"], "sha256": m["sha256"],
             "vermagic": m["modinfo"].get("vermagic", ["?"])[0]}
            for m in modules],
        "symbols": dict(sorted(symbols.items())),
        "symbolConflicts": {k: v for k, v in sorted(conflicts.items())},
        "providers": {k: v for k, v in sorted(providers.items())},
    }
    Path(out).write_text(json.dumps(doc, indent=2) + "\n", encoding="utf-8")
    print(f"baseline: {len(symbols)} imported symbols, "
          f"{len(conflicts)} CRC conflicts, {len(providers)} vendor-provided "
          f"symbols, {len(modules)} modules -> {out}")
    for sym, by in conflicts.items():
        print(f"  CONFLICT {sym}: " +
              ", ".join(f"{crc}<-{','.join(mods)}" for crc, mods in by.items()),
              file=sys.stderr)


def validate(modules, abi_path):
    ref = json.loads(Path(abi_path).read_text(encoding="utf-8"))
    ref_by_sha = {m["sha256"]: m for m in ref["modules"]}
    mismatches = 0
    for m in modules:
        r = ref_by_sha.get(m["sha256"])
        if r is None:
            print(f"  SKIP {m['file']}: not in reference (sha256 unknown)")
            continue
        for key in ("exportedSymbolCRCs", "importedSymbolCRCs", "undefinedSymbols",
                    "bytes", "architecture"):
            if m[key] != r.get(key):
                mismatches += 1
                print(f"  MISMATCH {m['file']} {key}:")
                print(f"    extractor: {json.dumps(m[key])[:300]}")
                print(f"    reference: {json.dumps(r.get(key))[:300]}")
        rmod = r.get("modinfo", {})
        for k, v in m["modinfo"].items():
            if k in rmod and rmod[k] != v:
                mismatches += 1
                print(f"  MISMATCH {m['file']} modinfo.{k}: extractor={v} ref={rmod[k]}")
    if mismatches:
        print(f"VALIDATION FAILED: {mismatches} field mismatches")
        sys.exit(1)
    matched = sum(1 for m in modules if m["sha256"] in ref_by_sha)
    print(f"VALIDATION OK: {matched}/{len(modules)} modules match reference "
          f"on exported/imported CRCs, undefined symbols, modinfo")
    # cross-check hwid consumer comparisons if present
    for cmp_ in ref.get("hwidSymbolComparisons", []):
        if cmp_.get("hwidExportCRC") != cmp_.get("consumerImportCRC"):
            print(f"  note: reference comparison already inconsistent: {cmp_}")


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("inputs", nargs="+", help=".ko files or directories")
    ap.add_argument("--out", help="output JSON path")
    ap.add_argument("--abi", action="store_true",
                    help="write per-module list instead of aggregated baseline")
    ap.add_argument("--validate", metavar="MODULE_ABI_JSON",
                    help="cross-check extractor output against the manual "
                         "baseline and exit nonzero on any difference")
    args = ap.parse_args()
    modules = collect(args.inputs)
    if args.validate:
        validate(modules, args.validate)
        return
    if not args.out:
        fail("--out is required without --validate")
    if args.abi:
        write_abi(modules, args.out)
    else:
        write_baseline(modules, args.out)
    print(f"wrote {args.out} ({len(modules)} modules)")


if __name__ == "__main__":
    main()
