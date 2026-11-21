#!/usr/bin/env bash
# Reserve an extent and write filesystem payloads on both emulators.
set -euo pipefail
cd "$(dirname "$0")/.."
SIMH_NOVA=${SIMH_NOVA:-nova}
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
SNOVA=dusky/bin/Release/net9.0/Snova.dll
scripts/build-image.sh "$TMP/base.dsk" >/dev/null
for pair in 'simh/cvit-kernel-simh.asm kernel' 'sd/cvit-extension.asm extension' 'sd/cvit-write-extent-test.asm test' 'sd/cvit-write-boundary-test.asm boundary'; do
    set -- $pair
    dotnet "$SNOVA" abs "$1" "$TMP/$2.abs" --format simh-load >/dev/null
done
python3 - "$TMP" "$SIMH_NOVA" "$SNOVA" <<'PY'
import pathlib, re, struct, subprocess, sys
root, simh, snova = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3]
source = bytearray((root / 'base.dsk').read_bytes())
start = struct.unpack_from('<H', source, 12)[0]
if start + 2 > 1015: raise SystemExit('fixture has insufficient free space')
source[start * 512:(start + 2) * 512] = b'\xaa' * 1024
for case in ('normal', 'empty', 'invalid-source'):
    for emulator in ('dusky', 'simh'):
        disk = root / f'{case}-{emulator}.dsk'
        disk.write_bytes(source)
        deposit = ('4211 0' if case == 'empty' else
                   '4210 64777' if case == 'invalid-source' else None)
        if emulator == 'dusky':
            commands = (f'dsk0 attach {disk}\nasm simh/cvit-kernel-simh.asm\n'
                        'asm sd/cvit-extension.asm\nasm sd/cvit-write-extent-test.asm\n' +
                        (f'deposit {deposit}\n' if deposit else '') +
                        'run 100000\nexam 4200 3\nquit\n')
            proc = subprocess.run(['dotnet', snova], input=commands, text=True,
                                  capture_output=True, timeout=20, check=True)
            match = re.search(r'004200:\s+([0-7]+)\s+([0-7]+)\s+([0-7]+)', proc.stdout)
            values = tuple(int(x, 8) for x in match.groups()) if match else None
        else:
            ini = root / 'write.ini'
            ini.write_text(f'attach dsk {disk}\nload {root}/kernel.abs\n'
                           f'load {root}/extension.abs\nload {root}/test.abs\n' +
                           (f'dep {deposit}\n' if deposit else '') +
                           'go 4000\nex 4200-4202\ndetach dsk\nexit\n')
            proc = subprocess.run([simh, str(ini)], stdin=subprocess.DEVNULL,
                                  text=True, capture_output=True, timeout=20, check=True)
            matches = re.findall(r'^420[0-2]:\s+([0-7]+)', proc.stdout, re.M)
            values = tuple(int(x, 8) for x in matches) if len(matches) == 3 else None
        expected = (0, 3 if case == 'invalid-source' else 0, start)
        if values != expected:
            raise SystemExit(f'{case}/{emulator}: {values} != {expected}\n{proc.stdout}\n{proc.stderr}')
        expected_image = bytearray(source)
        struct.pack_into('<H', expected_image, 12, start + 2)
        if case != 'invalid-source':
            blocks = 1 if case == 'empty' else 2
            expected_image[start * 512:(start + blocks) * 512] = bytes(blocks * 512)
            if case == 'normal':
                struct.pack_into('<H', expected_image, start * 512, 0o12345)
                struct.pack_into('<H', expected_image, (start + 1) * 512, 0o54321)
        if disk.read_bytes() != expected_image:
            raise SystemExit(f'{case}/{emulator}: image contents or padding differ')
        print(f'PASS: {case} reserved-extent write on {emulator}')

# Illegal starts and extents must be rejected before changing any disk data.
for case, sector in (('cross-reserved', '1766'), ('reserved-start', '1767'),
                     ('wrapped-start', '177777'), ('header-sector', '0')):
    for emulator in ('dusky', 'simh'):
        disk = root / f'{case}-{emulator}.dsk'
        disk.write_bytes(source)
        if emulator == 'dusky':
            commands = (f'dsk0 attach {disk}\nasm simh/cvit-kernel-simh.asm\n'
                        'asm sd/cvit-extension.asm\nasm sd/cvit-write-boundary-test.asm\n'
                        f'deposit 4202 {sector}\nrun 100000\nexam 4200 1\nquit\n')
            proc = subprocess.run(['dotnet', snova], input=commands, text=True,
                                  capture_output=True, timeout=20, check=True)
            valid = re.search(r'004200:\s+000003', proc.stdout)
        else:
            ini = root / 'boundary.ini'
            ini.write_text(f'attach dsk {disk}\nload {root}/kernel.abs\n'
                           f'load {root}/extension.abs\nload {root}/boundary.abs\n'
                           f'dep 4202 {sector}\ngo 4000\nex 4200\ndetach dsk\nexit\n')
            proc = subprocess.run([simh, str(ini)], stdin=subprocess.DEVNULL,
                                  text=True, capture_output=True, timeout=20, check=True)
            valid = re.search(r'^4200:\s+000003', proc.stdout, re.M)
        if not valid or disk.read_bytes() != source:
            raise SystemExit(f'{case}/{emulator}: expected rejection with unchanged disk\n{proc.stdout}\n{proc.stderr}')
        print(f'PASS: {case} write rejection on {emulator}')
PY
