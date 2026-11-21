#!/usr/bin/env bash
# Build a self-contained, SIMH-compatible bootable CVIT/Nova DSK image.
# Usage: scripts/build-image.sh [output.dsk]
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="${1:-cvit-dsk.img}"
SNOVA="dusky/bin/Release/net9.0/Snova.dll"
WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

dotnet build dusky/Snova.csproj -c Release --nologo -v q
dotnet "$SNOVA" abs sd/cvit-boot.asm "$WORKDIR/boot.abs" --format simh-load
dotnet "$SNOVA" abs simh/cvit-kernel-simh.asm "$WORKDIR/kernel.abs" --format simh-load
dotnet "$SNOVA" abs simh/cvit-command-simh.asm "$WORKDIR/command.abs" --format simh-load --start 3000
python3 scripts/abs2bin.py "$WORKDIR/command.abs" "$WORKDIR/command.bin"
dotnet "$SNOVA" abs sd/focal.asm "$WORKDIR/focal.abs" --format simh-load
python3 scripts/abs2flat.py --pz "$WORKDIR/focal.abs" "$WORKDIR/focal.sys" 0o6000
printf 'Hello from CVIT/Nova!\nThis is a sample text file.\n' > "$WORKDIR/hello.txt"
N1=$(python3 -c "import struct, sys; print(struct.unpack_from('<H', open(sys.argv[1], 'rb').read())[0])" "$WORKDIR/command.bin")
ENTRY=$(printf '0o%o' $(( 8#3000 + 1 + N1 )))
python3 scripts/mk_cvit_nova.py "$WORKDIR/cvit-tc08.img" \
    "COMMAND=$WORKDIR/command.bin@0o3000,$ENTRY" \
    "FOCAL=$WORKDIR/focal.sys@0o6000,0o6000" \
    README.md=README.md "HELLO=$WORKDIR/hello.txt"
mkdir -p "$(dirname "$OUT")"
python3 simh/convert-tc08-to-dsk.py "$WORKDIR/cvit-tc08.img" "$OUT"
python3 scripts/install-dsk-boot.py "$OUT" "$WORKDIR/boot.abs" "$WORKDIR/kernel.abs"
echo "Bootable DSK image: $OUT"
