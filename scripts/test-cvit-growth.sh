#!/usr/bin/env bash
# Test directory chain growth: part 1 grows the root chain and fills
# the volume; part 2 runs on the same disk and must find the chain
# full with no room to grow.
set -euo pipefail
cd "$(dirname "$0")/.."
SIMH_NOVA=${SIMH_NOVA:-nova}
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
SNOVA=dusky/bin/Release/net9.0/Snova.dll
scripts/build-image.sh "$TMP/base.dsk" >/dev/null
for pair in 'simh/cvit-kernel-simh.asm kernel' 'sd/cvit-extension.asm extension' 'sd/cvit-growth-test.asm test1' 'sd/cvit-growth-full-test.asm test2'; do
    set -- $pair
    dotnet "$SNOVA" abs "$1" "$TMP/$2.abs" --format simh-load >/dev/null
done
python3 - "$TMP" "$SIMH_NOVA" "$SNOVA" <<'PY'
import pathlib, re, subprocess, sys
root, simh, snova = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3]
expected1 = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 11, 4)
expected2 = (0, 0, 0, 0, 0, 0, 0, 4, 4, 1, 18)
for emulator in ('dusky', 'simh'):
    disk = root / f'growth-{emulator}.dsk'
    disk.write_bytes((root / 'base.dsk').read_bytes())
    if emulator == 'dusky':
        commands = (f'dsk0 attach {disk}\nasm simh/cvit-kernel-simh.asm\n'
                    'asm sd/cvit-extension.asm\nasm sd/cvit-growth-test.asm\n'
                    'go 4000 100000\nexam 6000 7\nexam 6007 7\n'
                    'asm sd/cvit-growth-full-test.asm\n'
                    'go 4000 100000\nexam 6000 6\nexam 6006 5\nquit\n')
        proc = subprocess.run(['dotnet', snova], input=commands, text=True,
                              capture_output=True, timeout=30, check=True)
        def grab(addr, count):
            m = re.search(rf'00{addr}:\s+((?:[0-7]+\s+){{{count - 1}}}[0-7]+)', proc.stdout)
            return tuple(int(v, 8) for v in m.group(1).split()) if m else None
        values1 = (grab('6000', 7) or ()) + (grab('6007', 7) or ())
        values2 = (grab('6000', 6) or ()) + (grab('6006', 5) or ())
        if len(values1) != 14:
            values1 = None
        if len(values2) != 11:
            values2 = None
    else:
        def run(test, last):
            ini = root / f'{test}.ini'
            ini.write_text(f'attach dsk {disk}\nload {root}/kernel.abs\n'
                           f'load {root}/extension.abs\nload {root}/{test}.abs\n'
                           f'go 4000\nex 6000-{last}\ndetach dsk\nexit\n')
            proc = subprocess.run([simh, str(ini)], stdin=subprocess.DEVNULL,
                                  text=True, capture_output=True, timeout=30, check=True)
            found = re.findall(r'^60[0-3][0-7]:\s+([0-7]+)', proc.stdout, re.M)
            return tuple(int(v, 8) for v in found)
        values1 = run('test1', '6015')
        values2 = run('test2', '6012')
        if len(values1) != 14:
            values1 = None
        if len(values2) != 11:
            values2 = None
    if values1 != expected1:
        raise SystemExit(f'{emulator}: growth part 1 values {values1} != {expected1}')
    print(f'PASS: directory chain growth on {emulator}')
    if values2 != expected2:
        raise SystemExit(f'{emulator}: growth part 2 values {values2} != {expected2}')
    print(f'PASS: full-volume directory limit on {emulator}')
PY
