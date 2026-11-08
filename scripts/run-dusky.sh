#!/usr/bin/env bash
# Build and launch CVIT/Nova (including RUN FOCAL) in Dusky.
# Requires .NET 9 SDK and python3.
# Enter sends CR; Ctrl-D sends EOT to halt and exit.
set -euo pipefail
cd "$(dirname "$0")/.."

for tool in dotnet python3; do
    command -v "$tool" >/dev/null 2>&1 || { echo "Required command not found: $tool" >&2; exit 1; }
done

WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT
SNOVA="dusky/bin/Release/net9.0/Snova.dll"
# Incremental builds are cheap and avoid using a stale assembler.
dotnet build dusky/Snova.csproj -c Release --nologo -v q

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
    README.md=README.md \
    "HELLO=$WORKDIR/hello.txt"
python3 simh/convert-tc08-to-dsk.py "$WORKDIR/cvit-tc08.img" "$WORKDIR/cvit-dsk.img"

dotnet "$SNOVA" --console "$WORKDIR/cvit-dsk.img"
