#!/bin/sh
# Build tfmtp for the console and run the protocol self-test on the host.
# Needs Zig (https://ziglang.org); tested with Zig 0.17.0.
#
#   ./build.sh          -> sdcard/cubegm/tfmtp (static MIPS32 LE) + self-test
#   ZIG=/path/zig ./build.sh
set -eu
cd "$(dirname "$0")"
ZIG=${ZIG:-zig}

echo "== tfmtp for the console (mipsel-linux-musleabi, static)"
"$ZIG" cc -target mipsel-linux-musleabi -mcpu=mips32 -static -Os -s \
    -Wall -Wno-unused-function -o sdcard/cubegm/tfmtp src/tfmtp.c
ls -l sdcard/cubegm/tfmtp

echo "== host self-test"
tmp=$(mktemp -d)
case "$(uname -s 2>/dev/null)" in
    MINGW*|MSYS*|CYGWIN*) EXTRA="-Dstrcasecmp=_stricmp"; EXE=tfmtp_test.exe ;;
    *) EXTRA=""; EXE=tfmtp_test ;;
esac
"$ZIG" cc -DTFMTP_TEST $EXTRA -Wall -Wno-unused-function -o "$tmp/$EXE" src/tfmtp.c
(cd "$tmp" && "./$EXE" 2>/dev/null)
rm -rf "$tmp"
