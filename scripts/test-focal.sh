#!/usr/bin/env bash
# FOCAL/Nova acceptance test: run testdata/focal-session.txt through
# RUN FOCAL on both Dusky (batch mode) and SIMH, and require each
# transcript to match testdata/focal-session.expected.
#   scripts/test-focal.sh            compare
#   scripts/test-focal.sh --update   rewrite the expected file from Dusky
set -euo pipefail
cd "$(dirname "$0")/.."
SIMH_NOVA="${SIMH_NOVA:-nova}"
SNOVA="dusky/bin/Release/net9.0/Snova.dll"
for tool in "$SIMH_NOVA" dotnet python3; do
    command -v "$tool" >/dev/null 2>&1 || { echo "Required command not found: $tool" >&2; exit 1; }
done
[[ -f "$SNOVA" ]] || dotnet build dusky/Snova.csproj -c Release --nologo -v q
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

dotnet "$SNOVA" abs simh/cvit-kernel-simh.asm "$TMPDIR/kernel.abs" --format simh-load >/dev/null
dotnet "$SNOVA" abs simh/cvit-command-simh.asm "$TMPDIR/command.abs" --format simh-load --start 3000 >/dev/null
dotnet "$SNOVA" abs sd/focal.asm "$TMPDIR/focal.abs" --format simh-load >/dev/null
python3 scripts/abs2bin.py "$TMPDIR/command.abs" "$TMPDIR/command.bin" >/dev/null
python3 scripts/abs2flat.py --pz "$TMPDIR/focal.abs" "$TMPDIR/focal.sys" 0o6000 >/dev/null
N1=$(python3 -c "import struct; print(struct.unpack_from('<H', open('$TMPDIR/command.bin','rb').read())[0])")
ENTRY=$(printf '0o%o' $(( 8#3000 + 1 + N1 )))
python3 scripts/mk_cvit_nova.py "$TMPDIR/cvit-tc08.img" \
    "COMMAND=$TMPDIR/command.bin@0o3000,$ENTRY" \
    "FOCAL=$TMPDIR/focal.sys@0o6000,0o6000" >/dev/null
python3 simh/convert-tc08-to-dsk.py "$TMPDIR/cvit-tc08.img" "$TMPDIR/cvit-dsk.img" >/dev/null

# Session input: RUN FOCAL, the test lines (LF -> CR), then EOT so the
# COMMAND prompt reached after QUIT halts the machine.
python3 - "$TMPDIR/session.in" "$TMPDIR/simh.ini" "$TMPDIR" <<'PY'
import sys
out, ini, tmp = sys.argv[1:]
lines = ["RUN FOCAL"] + open("testdata/focal-session.txt").read().splitlines()
data = "".join(line + "\r" for line in lines) + "\x04"
open(out, "w", newline="").write(data)
esc = (data.replace("\\", "\\\\").replace('"', '\\"').replace("%", "%%")
       .replace("\r", "\\r").replace("\x04", "\\004"))
# SIMH drops a character that arrives while the program is busy, so pace
# input well beyond the longest command in the session.
open(ini, "w").write(
    f"attach dsk {tmp}/cvit-dsk.img\nload {tmp}/kernel.abs\n"
    f'send after=200000,delay=200000 "{esc}"\ngo 1000\nexit\n')
PY

# Keep the FOCAL part of a transcript: from the banner to the COMMAND
# prompt that follows QUIT.
extract() {
    tr -d '\000\r' | sed -n '/^FOCAL\/Nova/,/^cvit\/Nova COMMAND/p'
}

dotnet "$SNOVA" --batch "$TMPDIR/cvit-dsk.img" < "$TMPDIR/session.in" 2>&1 | extract > "$TMPDIR/dusky.txt" || true
if [[ "${1:-}" == "--update" ]]; then
    cp "$TMPDIR/dusky.txt" testdata/focal-session.expected
    echo "Updated testdata/focal-session.expected from Dusky."
    exit 0
fi
timeout 60 "$SIMH_NOVA" "$TMPDIR/simh.ini" < /dev/null 2>&1 | extract > "$TMPDIR/simh.txt" || true

status=0
for emu in dusky simh; do
    if diff -u testdata/focal-session.expected "$TMPDIR/$emu.txt" > "$TMPDIR/$emu.diff"; then
        echo "PASS: $emu transcript matches ($(wc -l < "$TMPDIR/$emu.txt") lines)"
    else
        echo "FAIL: $emu transcript differs:" >&2
        cat "$TMPDIR/$emu.diff" >&2
        status=1
    fi
done
exit $status
