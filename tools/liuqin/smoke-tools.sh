#!/bin/bash
B=/var/tmp/liuqin-android12-5.10/build/build-tools/path/linux-x86
C=/var/tmp/liuqin-android12-5.10/prebuilts-master/clang/host/linux-x86/clang-r416183b/bin
T=/var/tmp/liuqin-android12-5.10/tools/mkbootimg
python3 "$B/mkdtboimg.py" version 2>&1 | head -1
python3 "$T/mkbootimg.py" --help >/dev/null && echo mkbootimg.py_OK
python3 "$T/unpack_bootimg.py" --help >/dev/null && echo unpack_bootimg.py_OK
"$C/clang" --version | head -1
"$C/ld.lld" --version | head -1
