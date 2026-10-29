#!/usr/bin/env bash
# Build a bootable cvit/Nova TC08 image from the current sources.
# Usage: scripts/build-image.sh [output.img]
# Requires: dotnet (to build the dusky assembler), python3
# Output: TC08 image with COMMAND (from sd/cvit-command.asm) + HELLO test file.
set -e
cd "$(dirname "$0")/.."

OUT="${1:-/srv/share/dusky/cvit-tc08.img}"
SNOVA="dusky/bin/Release/net9.0/Snova.dll"

if [ ! -f "$SNOVA" ]; then
    echo "Building dusky assembler..."
    dotnet build dusky/ -c Release --nologo -v q
fi

TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

echo "Assembling COMMAND..."
dotnet "$SNOVA" abs sd/cvit-command.asm "$TMPDIR/command.abs" --format simh-load --start 3000

echo "Converting to flat image..."
python3 scripts/abs2bin.py "$TMPDIR/command.abs" "$TMPDIR/command.bin"
# abs2bin.py prints: n1=... ; entry = 0o3000 + 1 + n1
N1=$(python3 -c "import struct; print(struct.unpack_from('<H', open('$TMPDIR/command.bin','rb').read())[0])")
ENTRY=$(printf '0o%o' $(( 0o3000 + 1 + N1 )))
echo "n1=$N1 entry=$ENTRY"

cat > "$TMPDIR/hello.txt" <<'EOF'
Hello from TYPE!
This is a test file for the Dusky emulator.
Line three.
EOF

echo "Building TC08 image..."
python3 scripts/mk_cvit_nova.py "$OUT" \
    "COMMAND=$TMPDIR/command.bin@0o3000,$ENTRY" \
    "HELLO=$TMPDIR/hello.txt"

echo "Done: $OUT"
