#!/usr/bin/env bash
# Test the full two-save FOCAL order against the directory services.
set -euo pipefail
cd "$(dirname "$0")/.."
SIMH_NOVA=${SIMH_NOVA:-nova}
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
SNOVA=dusky/bin/Release/net9.0/Snova.dll
scripts/build-image.sh "$TMP/base.dsk" >/dev/null
for pair in 'simh/cvit-kernel-simh.asm kernel' 'sd/cvit-extension.asm extension' 'sd/cvit-fow3-test.asm test'; do
    set -- $pair
    dotnet "$SNOVA" abs "$1" "$TMP/$2.abs" --format simh-load >/dev/null
done
python3 - "$TMP" "$SIMH_NOVA" "$SNOVA" <<'PY'
import pathlib, re, subprocess, sys
root, simh, snova = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3]
for emulator in ('dusky', 'simh'):
    disk = root / f'fow3-{emulator}.dsk'
    disk.write_bytes((root / 'base.dsk').read_bytes())
    if emulator == 'dusky':
        commands = (f'dsk0 attach {disk}\nasm simh/cvit-kernel-simh.asm\n'
                    'asm sd/cvit-extension.asm\nasm sd/cvit-fow3-test.asm\n'
                    'go 4000 100000\nexam 6000 6\nexam 6006 6\nquit\n')
        proc = subprocess.run(['dotnet', snova], input=commands, text=True,
                              capture_output=True, timeout=20, check=True)
        m1 = re.search(r'006000:\s+([0-7]+)\s+([0-7]+)\s+([0-7]+)\s+([0-7]+)\s+([0-7]+)\s+([0-7]+)', proc.stdout)
        m2 = re.search(r'006006:\s+([0-7]+)\s+([0-7]+)\s+([0-7]+)\s+([0-7]+)\s+([0-7]+)\s+([0-7]+)', proc.stdout)
        values = tuple(int(v, 8) for v in m1.groups() + m2.groups()) if m1 and m2 else None
    else:
        ini = root / 'fow3.ini'
        ini.write_text(f'attach dsk {disk}\nload {root}/kernel.abs\n'
                       f'load {root}/extension.abs\nload {root}/test.abs\n'
                       'go 4000\nex 6000-6013\ndetach dsk\nexit\n')
        proc = subprocess.run([simh, str(ini)], stdin=subprocess.DEVNULL,
                              text=True, capture_output=True, timeout=20, check=True)
        vals = re.findall(r'^(?:600[0-7]|601[0-3]):\s+([0-7]+)', proc.stdout, re.M)
        values = tuple(int(v, 8) for v in vals) if len(vals) == 12 else None
    # R0 check1=0, R1 reserve1=0, R2 write1=0, R3 publish=0,
    # R4 check2=1, R5 reserve2=0, R6 write2=0, R7 replace=0,
    # R8 lookup=0, R9 reserve2 start, R10 found start == R9,
    # R11 found length = 0o40 (32).
    ok = (values is not None
          and values[:9] == (0, 0, 0, 0, 1, 0, 0, 0, 0)
          and values[9] not in (0, 64) and values[10] == values[9]
          and values[11] == 32)
    if not ok:
        raise SystemExit(f'{emulator}: fow3 values {values}\n{proc.stdout}\n{proc.stderr}')
    print(f'PASS: full two-save order on {emulator} (start2 {values[9]})')
PY
