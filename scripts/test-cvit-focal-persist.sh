#!/usr/bin/env bash
# FOCAL .save -> cold boot -> .load persistence test: save a multi-sector
# program in one boot, restart from the same image, reload it, and
# require the WRITE listing and GO output to match what was saved.
set -euo pipefail
cd "$(dirname "$0")/.."
SIMH_NOVA="${SIMH_NOVA:-nova}"
SNOVA="dusky/bin/Release/net9.0/Snova.dll"
for tool in "$SIMH_NOVA" dotnet python3; do
    command -v "$tool" >/dev/null 2>&1 || { echo "Required command not found: $tool" >&2; exit 1; }
done
dotnet build dusky/Snova.csproj -c Release --nologo -v q >/dev/null
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT
for pair in 'sd/cvit-boot.asm boot' 'simh/cvit-kernel-simh.asm kernel' 'sd/cvit-extension.asm extension'; do
    set -- $pair
    dotnet "$SNOVA" abs "$1" "$TMPDIR/$2.abs" --format simh-load >/dev/null
done
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
python3 scripts/install-dsk-boot.py "$TMPDIR/cvit-dsk.img" \
    "$TMPDIR/boot.abs" "$TMPDIR/kernel.abs" "$TMPDIR/extension.abs" >/dev/null

# The saved program: three long comment lines push the payload past one
# 128-word sector, then a TYPE line whose output proves the reload runs.
python3 - "$TMPDIR" <<'PY'
import sys
tmp = sys.argv[1]
prog = [
    '1.1 C ' + 'A' * 60,
    '1.2 C ' + 'B' * 60,
    '1.3 C ' + 'C' * 60,
    '2.1 T "PERSIST-OK"!',
]
save = ['RUN FOCAL'] + prog + ['.save PROG', 'QUIT']
load = ['RUN FOCAL', '.load PROG', 'WRITE', 'GO', 'QUIT']
for name, lines in (('save', save), ('load', load)):
    data = ''.join(line + '\r' for line in lines) + '\x04'
    open(f'{tmp}/{name}.in', 'w', newline='').write(data)
    esc = (data.replace('\\', '\\\\').replace('"', '\\"').replace('%', '%%')
           .replace('\r', '\\r').replace('\x04', '\\004'))
    ini = (f'attach dsk {tmp}/simh.dsk\n'
           f'send after=1000000,delay=1000000 "{esc}"\n'
           'boot dsk\nexit\n')
    open(f'{tmp}/{name}.ini', 'w').write(ini)
listed = ['01.10 ' + prog[0][4:], '01.20 ' + prog[1][4:], '01.30 ' + prog[2][4:], '02.10 ' + prog[3][4:]]
open(f'{tmp}/prog.txt', 'w').write('\n'.join(listed) + '\n')
PY

status=0
check() {
    # $1 = transcript file; every program line and the GO output must appear.
    while IFS= read -r line; do
        grep -qF "$line" "$1" || { echo "FAIL: missing in transcript: $line" >&2; return 1; }
    done < "$TMPDIR/prog.txt"
    grep -q 'PERSIST-OK' "$1" || { echo "FAIL: GO output missing" >&2; return 1; }
}

for emu in dusky simh; do
    cp "$TMPDIR/cvit-dsk.img" "$TMPDIR/$emu.dsk"
done
# Dusky: two batch runs on the same disk image.
dotnet "$SNOVA" --batch "$TMPDIR/dusky.dsk" < "$TMPDIR/save.in" >/dev/null 2>&1 || true
dotnet "$SNOVA" --batch "$TMPDIR/dusky.dsk" < "$TMPDIR/load.in" > "$TMPDIR/dusky.txt" 2>&1 || true
if check "$TMPDIR/dusky.txt"; then echo "PASS: .save, cold boot, .load, run on dusky"; else status=1; fi
# SIMH: two boots on the same disk image.
"$SIMH_NOVA" "$TMPDIR/save.ini" >/dev/null 2>&1 || true
"$SIMH_NOVA" "$TMPDIR/load.ini" > "$TMPDIR/simh.txt" 2>&1 || true
if check "$TMPDIR/simh.txt"; then echo "PASS: .save, cold boot, .load, run on simh"; else status=1; fi
exit $status
