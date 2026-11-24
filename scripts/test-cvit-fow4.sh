#!/usr/bin/env bash
# Test the two-save order on a member in the second directory block.
set -euo pipefail
cd "$(dirname "$0")/.."
SIMH_NOVA=${SIMH_NOVA:-nova}
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
SNOVA=dusky/bin/Release/net9.0/Snova.dll
scripts/build-image.sh "$TMP/base.dsk" >/dev/null
for pair in 'simh/cvit-kernel-simh.asm kernel' 'sd/cvit-extension.asm extension' 'sd/cvit-fow4-test.asm test'; do
    set -- $pair
    dotnet "$SNOVA" abs "$1" "$TMP/$2.abs" --format simh-load >/dev/null
done
python3 - "$TMP" "$SIMH_NOVA" "$SNOVA" <<'PY'
import pathlib, re, subprocess, sys
root, simh, snova = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3]
for emulator in ('dusky', 'simh'):
    disk = root / f'fow4-{emulator}.dsk'
    disk.write_bytes((root / 'base.dsk').read_bytes())
    if emulator == 'dusky':
        commands = (f'dsk0 attach {disk}\nasm simh/cvit-kernel-simh.asm\n'
                    'asm sd/cvit-extension.asm\nasm sd/cvit-fow4-test.asm\n'
                    'go 4000 300000\nexam 6000 7\nexam 6007 7\nquit\n')
        proc = subprocess.run(['dotnet', snova], input=commands, text=True,
                              capture_output=True, timeout=20, check=True)
        m1 = re.search(r'006000:\s+([0-7]+)\s+([0-7]+)\s+([0-7]+)\s+([0-7]+)\s+([0-7]+)\s+([0-7]+)\s+([0-7]+)', proc.stdout)
        m2 = re.search(r'006007:\s+([0-7]+)\s+([0-7]+)\s+([0-7]+)\s+([0-7]+)\s+([0-7]+)\s+([0-7]+)\s+([0-7]+)', proc.stdout)
        values = tuple(int(v, 8) for v in m1.groups() + m2.groups()) if m1 and m2 else None
    else:
        ini = root / 'fow4.ini'
        ini.write_text(f'attach dsk {disk}\nload {root}/kernel.abs\n'
                       f'load {root}/extension.abs\nload {root}/test.abs\n'
                       'go 4000\nex 6000-6015\ndetach dsk\nexit\n')
        proc = subprocess.run([simh, str(ini)], stdin=subprocess.DEVNULL,
                              text=True, capture_output=True, timeout=20, check=True)
        vals = re.findall(r'^(?:600[0-7]|601[0-5]):\s+([0-7]+)', proc.stdout, re.M)
        values = tuple(int(v, 8) for v in vals) if len(vals) == 14 else None
    # RDUM=0 (dummy publishes), RD6=0 (lookup finds block-2 dummy),
    # check1=0, reserve1=0, write1=0, publish=0, check2=1, reserve2=0,
    # write2=0, replace=0, lookup=0, start2, found start == start2,
    # found length = 0o40 (32).
    ok = (values is not None
          and values[:11] == (0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0)
          and values[11] not in (0, 64) and values[12] == values[11]
          and values[13] == 32)
    if not ok:
        raise SystemExit(f'{emulator}: fow4 values {values}\n{proc.stdout}\n{proc.stderr}')
    print(f'PASS: two-save order in block 2 on {emulator} (start2 {values[11]})')
PY
