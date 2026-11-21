#!/usr/bin/env bash
# Validate high-water reservation and failure handling on disposable images.
set -euo pipefail
cd "$(dirname "$0")/.."
SIMH_NOVA=${SIMH_NOVA:-nova}
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
SNOVA=dusky/bin/Release/net9.0/Snova.dll
scripts/build-image.sh "$TMP/base.dsk" >/dev/null
for pair in 'simh/cvit-kernel-simh.asm kernel' 'sd/cvit-extension.asm extension' 'sd/cvit-alloc-test.asm test'; do
    set -- $pair
    dotnet "$SNOVA" abs "$1" "$TMP/$2.abs" --format simh-load >/dev/null
done
python3 - "$TMP" "$SIMH_NOVA" "$SNOVA" <<'PY'
import pathlib, re, struct, subprocess, sys
root, simh, snova = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3]
original = (root / 'base.dsk').read_bytes()
base = struct.unpack_from('<H', original, 12)[0]
for case in ('normal', 'full', 'invalid', 'zero-count', 'oversize'):
    source = bytearray(original)
    if case == 'full': struct.pack_into('<H', source, 12, 1014)
    if case == 'invalid': struct.pack_into('<H', source, 4, 1)
    start = struct.unpack_from('<H', source, 12)[0]
    expected = ((0, start, 0, start + 1) if case == 'normal' else
                (0, start, 4, start) if case == 'full' else
                (3, 0xffff, 3, 0xffff) if case == 'invalid' else
                (3 if case == 'zero-count' else 4, 0xffff, 0, start))
    next_block = start + (3 if case == 'normal' else 1 if case == 'full' else
                          0 if case == 'invalid' else 2)
    count = '0' if case == 'zero-count' else '177777' if case == 'oversize' else None
    for emulator in ('dusky', 'simh'):
        disk = root / f'{case}-{emulator}.dsk'
        disk.write_bytes(source)
        if emulator == 'dusky':
            commands = (f'dsk0 attach {disk}\nasm simh/cvit-kernel-simh.asm\n'
                        'asm sd/cvit-extension.asm\nasm sd/cvit-alloc-test.asm\n'
                        + (f'deposit 4205 {count}\n' if count is not None else '') +
                        'run 100000\nexam 4200 4\nquit\n')
            proc = subprocess.run(['dotnet', snova], input=commands, text=True,
                                  capture_output=True, timeout=20, check=True)
            match = re.search(r'004200:\s+([0-7]+)\s+([0-7]+)\s+([0-7]+)\s+([0-7]+)', proc.stdout)
            values = tuple(int(x, 8) for x in match.groups()) if match else None
        else:
            ini = root / 'alloc.ini'
            ini.write_text(f'attach dsk {disk}\nload {root}/kernel.abs\n'
                           f'load {root}/extension.abs\nload {root}/test.abs\n' +
                           (f'dep 4205 {count}\n' if count is not None else '') +
                           'go 4000\nex 4200-4203\ndetach dsk\nexit\n')
            proc = subprocess.run([simh, str(ini)], stdin=subprocess.DEVNULL,
                                  text=True, capture_output=True, timeout=20, check=True)
            matches = re.findall(r'^420[0-3]:\s+([0-7]+)', proc.stdout, re.M)
            values = tuple(int(x, 8) for x in matches) if len(matches) == 4 else None
        if values != expected:
            raise SystemExit(f'{case}/{emulator}: {values} != {expected}\n{proc.stdout}\n{proc.stderr}')
        actual = disk.read_bytes()
        expected_image = bytearray(source)
        struct.pack_into('<H', expected_image, 12, next_block)
        if actual != expected_image:
            raise SystemExit(f'{case}/{emulator}: disk changed outside high-water mark or has wrong value')
        print(f'PASS: {case} allocation on {emulator}')
PY
