#!/bin/sh
# Build the console binaries and run the tfmtp protocol self-test on the host.
# Needs Zig (https://ziglang.org); tested with Zig 0.17.0.
#
#   ./build.sh          -> sdcard/cubegm/{tfmtp,tfusbd,tfkey} (static MIPS32 LE) + self-test
#   ZIG=/path/zig ./build.sh
set -eu
cd "$(dirname "$0")"
ZIG=${ZIG:-zig}
MIPS="-target mipsel-linux-musleabi -mcpu=mips32 -static -Os -s -Wall -Wno-unused-function"

for b in tfmtp tfusbd tfkey; do
    echo "== $b for the console (mipsel-linux-musleabi, static)"
    "$ZIG" cc $MIPS -o "sdcard/cubegm/$b" "src/$b.c"
    ls -l "sdcard/cubegm/$b"
done

echo "== host self-test (tfmtp protocol)"
tmp=$(mktemp -d)
case "$(uname -s 2>/dev/null)" in
    MINGW*|MSYS*|CYGWIN*) EXTRA="-Dstrcasecmp=_stricmp"; EXE=tfmtp_test.exe ;;
    *) EXTRA=""; EXE=tfmtp_test ;;
esac
"$ZIG" cc -DTFMTP_TEST $EXTRA -Wall -Wno-unused-function -o "$tmp/$EXE" src/tfmtp.c
(cd "$tmp" && "./$EXE" 2>/dev/null)
rm -rf "$tmp"
