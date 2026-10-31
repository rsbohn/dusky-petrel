#!/usr/bin/env bash
# Build and launch CVIT/Nova in SIMH, then leave its console interactive.
set -euo pipefail
cd "$(dirname "$0")/.."

SIMH_NOVA="${SIMH_NOVA:-nova}"
if ! command -v "$SIMH_NOVA" >/dev/null 2>&1; then
    echo "SIMH Nova executable not found: $SIMH_NOVA (set SIMH_NOVA to its path)" >&2
    exit 1
fi
for tool in dotnet python3; do
    command -v "$tool" >/dev/null 2>&1 || { echo "Required command not found: $tool" >&2; exit 1; }
done

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT
SNOVA="dusky/bin/Release/net9.0/Snova.dll"
if [[ ! -f "$SNOVA" ]]; then
    dotnet build dusky/Snova.csproj -c Release --nologo -v q
fi

dotnet "$SNOVA" abs simh/cvit-kernel-simh.asm "$TMPDIR/kernel.abs" --format simh-load
dotnet "$SNOVA" abs simh/cvit-command-simh.asm "$TMPDIR/command.abs" --format simh-load --start 3000
python3 scripts/abs2bin.py "$TMPDIR/command.abs" "$TMPDIR/command.bin"
printf 'Hello from CVIT/Nova!\nThis is a sample text file.\n' > "$TMPDIR/hello.txt"
N1=$(python3 -c "import struct; print(struct.unpack_from('<H', open('$TMPDIR/command.bin','rb').read())[0])")
ENTRY=$(printf '0o%o' $(( 8#3000 + 1 + N1 )))
python3 scripts/mk_cvit_nova.py "$TMPDIR/cvit-tc08.img" \
    "COMMAND=$TMPDIR/command.bin@0o3000,$ENTRY" \
    README.md=README.md \
    "HELLO=$TMPDIR/hello.txt"
python3 simh/convert-tc08-to-dsk.py "$TMPDIR/cvit-tc08.img" "$TMPDIR/cvit-dsk.img"

cat > "$TMPDIR/simh.ini" <<EOF
attach dsk $TMPDIR/cvit-dsk.img
load $TMPDIR/kernel.abs
go 1000
EOF
"$SIMH_NOVA" "$TMPDIR/simh.ini"
