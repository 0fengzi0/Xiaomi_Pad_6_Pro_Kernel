#!/usr/bin/env python3
"""Extract named files from an Android boot ramdisk (LZ4-legacy compressed
newc cpio), using only the Python standard library.

The Android GKI generic ramdisk uses the legacy LZ4 stream format
(magic 0x184C2102: u32 compressed size per 8 MiB block) followed by a newc
cpio archive. Both formats are decoded here directly so no external lz4
binary is needed on Windows.

Usage:
  python extract-ramdisk-file.py RAMDISK --list
  python extract-ramdisk-file.py RAMDISK --name kernelsu.ko --out PATH [--name2 X --out2 Y ...]
"""

import argparse
import hashlib
import struct
import sys
from pathlib import Path

LZ4_LEGACY_MAGIC = 0x184C2102
LZ4_BLOCK_MAX = 8 * 1024 * 1024
NEWC_MAGIC = b"070701"


def fail(msg):
    print(f"ERROR: {msg}", file=sys.stderr)
    sys.exit(1)


def lz4_block_decompress(src):
    """Decode one LZ4 block (raw format)."""
    dst = bytearray()
    i, n = 0, len(src)
    while i < n:
        token = src[i]
        i += 1
        length = token >> 4
        if length == 15:
            while True:
                if i >= n:
                    fail("truncated literal length in LZ4 block")
                b = src[i]
                i += 1
                length += b
                if b != 255:
                    break
        if i + length > n:
            fail("truncated literals in LZ4 block")
        dst += src[i:i + length]
        i += length
        if i >= n:
            break  # last sequence has no match
        if i + 2 > n:
            fail("truncated match offset in LZ4 block")
        offset = src[i] | (src[i + 1] << 8)
        i += 2
        if offset == 0 or offset > len(dst):
            fail("invalid LZ4 match offset")
        match_len = (token & 0xF) + 4
        if match_len == 19:
            while True:
                if i >= n:
                    fail("truncated match length in LZ4 block")
                b = src[i]
                i += 1
                match_len += b
                if b != 255:
                    break
        start = len(dst) - offset
        if offset >= match_len:
            dst += dst[start:start + match_len]
        else:
            for j in range(match_len):
                dst.append(dst[start + j])
    return bytes(dst)


def lz4_legacy_decompress(data):
    if struct.unpack_from("<I", data, 0)[0] != LZ4_LEGACY_MAGIC:
        fail("not an LZ4-legacy stream (magic mismatch)")
    out = bytearray()
    pos = 4
    blocks = 0
    while pos + 4 <= len(data):
        comp_size, = struct.unpack_from("<I", data, pos)
        pos += 4
        if comp_size == 0 or pos + comp_size > len(data):
            break  # end of blocks (optional checksum may follow)
        out += lz4_block_decompress(data[pos:pos + comp_size])
        pos += comp_size
        blocks += 1
    print(f"lz4: {blocks} blocks -> {len(out)} bytes", file=sys.stderr)
    return bytes(out)


def parse_newc(data):
    entries = []
    pos = 0
    while pos + 6 <= len(data):
        if data[pos:pos + 6] != NEWC_MAGIC:
            break
        hdr = data[pos:pos + 110]
        (ino, mode, uid, gid, nlink, mtime, filesize, dev_maj, dev_min,
         rdev_maj, rdev_min, namesize, check) = (
            int(hdr[6 + i * 8:14 + i * 8], 16) for i in range(13))
        name = data[pos + 110:pos + 110 + namesize - 1].decode("utf-8", "replace")
        hdr_end = pos + 110 + namesize
        hdr_end += (4 - hdr_end % 4) % 4
        file_start = hdr_end
        file_end = file_start + filesize
        entries.append((name, mode, filesize,
                        data[file_start:file_end] if filesize else b""))
        pos = file_end + (4 - file_end % 4) % 4
        if name == "TRAILER!!!":
            break
    return entries


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("ramdisk", help="ramdisk file (LZ4-legacy newc cpio)")
    ap.add_argument("--list", action="store_true", help="list entries and exit")
    ap.add_argument("--name", action="append", default=[],
                    help="entry name (or path suffix) to extract; repeatable")
    ap.add_argument("--out", action="append", default=[],
                    help="output path for each --name, same order")
    ap.add_argument("--all-kos", metavar="OUTDIR",
                    help="extract every .ko entry into OUTDIR (flattened)")
    args = ap.parse_args()
    data = Path(args.ramdisk).read_bytes()
    if data[:4] == NEWC_MAGIC[:4] or data[:6] == NEWC_MAGIC:
        entries = parse_newc(data)
    else:
        entries = parse_newc(lz4_legacy_decompress(data))
    print(f"cpio: {len(entries)} entries")
    if args.list:
        for name, mode, size, _ in entries:
            print(f"{mode:07o} {size:10d} {name}")
        return
    if args.all_kos:
        outdir = Path(args.all_kos)
        outdir.mkdir(parents=True, exist_ok=True)
        count = 0
        for name, mode, size, blob in entries:
            if name.endswith(".ko"):
                (outdir / Path(name).name).write_bytes(blob)
                count += 1
        print(f"extracted {count} .ko entries -> {outdir}")
        return
    if len(args.out) != len(args.name):
        fail("--name and --out counts differ")
    wanted = {n: Path(o) for n, o in zip(args.name, args.out)}
    found = {}
    for name, mode, size, blob in entries:
        for target, out in wanted.items():
            if name == target or name.endswith("/" + target) or \
                    Path(name).name == Path(target).name:
                out.parent.mkdir(parents=True, exist_ok=True)
                out.write_bytes(blob)
                print(f"extracted {name} ({size} bytes) -> {out} "
                      f"sha256={hashlib.sha256(blob).hexdigest()}")
                found[target] = size
    missing = set(wanted) - set(found)
    if missing:
        fail(f"entries not found: {', '.join(sorted(missing))}")


if __name__ == "__main__":
    main()
