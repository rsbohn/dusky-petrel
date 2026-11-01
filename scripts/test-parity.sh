#!/bin/bash
# Parity test: Dusky batch mode vs expected output
set -e
REPO="$(cd "$(dirname "$0")/.." && pwd)"
export PATH="$HOME/.local/bin:$HOME/.dotnet:$PATH"
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT
echo "Building..."
dotnet "$REPO/dusky/bin/Release/net9.0/Snova.dll" abs "$REPO/simh/cvit-kernel-simh.asm" "$TMPDIR/kernel.abs" --format simh-load > /dev/null
dotnet "$REPO/dusky/bin/Release/net9.0/Snova.dll" abs "$REPO/simh/cvit-command-simh.asm" "$TMPDIR/command.abs" --format simh-load --start 3000 > /dev/null
python3 "$REPO/scripts/abs2bin.py" "$TMPDIR/command.abs" "$TMPDIR/command.bin" > /dev/null
printf "Hello from CVIT/Nova!\nThis is a sample text file.\n" > "$TMPDIR/hello.txt"
N1=$(python3 -c "import struct; print(struct.unpack_from(\"<H\", open(\"$TMPDIR/command.bin\",\"rb\").read())[0])")
ENTRY=$(printf "0o%o" $(( 8#3000 + 1 + N1 )))
python3 "$REPO/scripts/mk_cvit_nova.py" "$TMPDIR/cvit-tc08.img" "COMMAND=$TMPDIR/command.bin@0o3000,$ENTRY" "HELLO=$TMPDIR/hello.txt" > /dev/null
python3 "$REPO/simh/convert-tc08-to-dsk.py" "$TMPDIR/cvit-tc08.img" "$TMPDIR/cvit-dsk.img" > /dev/null
echo "Running Dusky batch..."
printf "STA\rCAT\rTYPE HELLO\r\004" | dotnet "$REPO/dusky/bin/Release/net9.0/Snova.dll" --batch "$TMPDIR/cvit-dsk.img" > "$TMPDIR/out.txt" 2>&1 || true
cat "$TMPDIR/out.txt" | tr -d "\000"
