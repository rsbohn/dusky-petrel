#!/usr/bin/env bash
# Test selector 12 (directory replace, the copy-on-write commit point).
set -euo pipefail
cd "$(dirname "$0")/.."
SIMH_NOVA=${SIMH_NOVA:-nova}
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
SNOVA=dusky/bin/Release/net9.0/Snova.dll
scripts/build-image.sh "$TMP/base.dsk" >/dev/null
for pair in 'simh/cvit-kernel-simh.asm kernel' 'sd/cvit-extension.asm extension' 'sd/cvit-replace-test.asm test1' 'sd/cvit-replace2-test.asm test2'; do
    set -- $pair
    dotnet "$SNOVA" abs "$1" "$TMP/$2.abs" --format simh-load >/dev/null
done
python3 - "$TMP" "$SIMH_NOVA" "$SNOVA" <<'PY'
import pathlib, re, subprocess, sys
root, simh, snova = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3]
for emulator in ('dusky', 'simh'):
    disk = root / f'replace-{emulator}.dsk'
    disk.write_bytes((root / 'base.dsk').read_bytes())
    if emulator == 'dusky':
        commands = (f'dsk0 attach {disk}\nasm simh/cvit-kernel-simh.asm\n'
                    'asm sd/cvit-extension.asm\nasm sd/cvit-replace-test.asm\n'
                    'go 4000 100000\nexam 6000 6\nexam 6006 5\n'
                    'asm sd/cvit-replace2-test.asm\ngo 4000 100000\nexam 6020 4\nquit\n')
        proc = subprocess.run(['dotnet', snova], input=commands, text=True,
                              capture_output=True, timeout=20, check=True)
        m1 = re.search(r'006000:\s+([0-7]+)\s+([0-7]+)\s+([0-7]+)\s+([0-7]+)\s+([0-7]+)\s+([0-7]+)', proc.stdout)
        m2 = re.search(r'006006:\s+([0-7]+)\s+([0-7]+)\s+([0-7]+)\s+([0-7]+)\s+([0-7]+)', proc.stdout)
        m3 = re.search(r'006020:\s+([0-7]+)\s+([0-7]+)\s+([0-7]+)\s+([0-7]+)', proc.stdout)
        values = tuple(int(v, 8) for v in m1.groups() + m2.groups() + m3.groups()) if m1 and m2 and m3 else None
    else:
        vals = []
        for part, ex in (('test1', 'ex 6000-6012'), ('test2', 'ex 6020-6023')):
            ini = root / f'replace-{part}.ini'
            ini.write_text(f'attach dsk {disk}\nload {root}/kernel.abs\n'
                           f'load {root}/extension.abs\nload {root}/{part}.abs\n'
                           f'go 4000\n{ex}\ndetach dsk\nexit\n')
            proc = subprocess.run([simh, str(ini)], stdin=subprocess.DEVNULL,
                                  text=True, capture_output=True, timeout=20, check=True)
            vals += re.findall(r'^(?:600[0-7]|601[0-2]|602[0-3]):\s+([0-7]+)', proc.stdout, re.M)
        values = tuple(int(v, 8) for v in vals) if len(vals) == 15 else None
    # Part 1: publish, lookup (start/length as stored), replace,
    # lookup (new extent, type 2), absent replace = 1, invalid = 3.
    # Part 2 (on part 1's disk): publish = 1 (duplicate), replace = 0,
    # enumeration count = 5 (still exactly one RA), publish = 1.
    # Extent values are octal in the source: 0o100, 0o200, 0o300, 0o500.
    expected = (0, 0, 64, 128, 0, 0, 192, 320, 2, 1, 3, 1, 0, 5, 1)
    if values != expected:
        raise SystemExit(f'{emulator}: replace values {values} != {expected}\n{proc.stdout}\n{proc.stderr}')
    print(f'PASS: directory replace (selector 12) on {emulator}')
PY
