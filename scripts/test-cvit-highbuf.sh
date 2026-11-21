#!/usr/bin/env bash
# Verify kernel DSK reads work with the 256-word buffer at 0o77000.
set -euo pipefail
cd "$(dirname "$0")/.."
SIMH_NOVA=${SIMH_NOVA:-nova}
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
SNOVA=dusky/bin/Release/net9.0/Snova.dll
scripts/build-image.sh "$TMP/base.dsk" >/dev/null
for pair in 'simh/cvit-kernel-simh.asm kernel' 'sd/cvit-highbuf-test.asm test'; do
    set -- $pair
    dotnet "$SNOVA" abs "$1" "$TMP/$2.abs" --format simh-load >/dev/null
done
python3 - "$TMP" "$SIMH_NOVA" "$SNOVA" <<'PY'
import pathlib, re, struct, subprocess, sys
root, simh, snova = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3]
image = (root / 'base.dsk').read_bytes()
expected = (1, *struct.unpack_from('<2H', image, 2 * 512))
for emulator in ('dusky', 'simh'):
    disk = root / f'highbuf-{emulator}.dsk'
    disk.write_bytes(image)
    if emulator == 'dusky':
        commands = (f'dsk0 attach {disk}\nasm simh/cvit-kernel-simh.asm\n'
                    'asm sd/cvit-highbuf-test.asm\ngo 4000\nexam 4200 3\nquit\n')
        proc = subprocess.run(['dotnet', snova], input=commands, text=True,
                              capture_output=True, timeout=20, check=True)
        match = re.search(r'004200:\s+([0-7]+)\s+([0-7]+)\s+([0-7]+)', proc.stdout)
        values = tuple(int(x, 8) for x in match.groups()) if match else None
    else:
        ini = root / 'highbuf.ini'
        ini.write_text(f'attach dsk {disk}\nload {root}/kernel.abs\n'
                       f'load {root}/test.abs\ngo 4000\nex 4200-4202\nexit\n')
        proc = subprocess.run([simh, str(ini)], stdin=subprocess.DEVNULL,
                              text=True, capture_output=True, timeout=20, check=True)
        found = re.findall(r'^420[0-2]:\s+([0-7]+)', proc.stdout, re.M)
        values = tuple(int(x, 8) for x in found) if len(found) == 3 else None
    if values != expected:
        raise SystemExit(f'{emulator}: high-buffer read {values} != {expected}\n{proc.stdout}\n{proc.stderr}')
    print(f'PASS: 0o77000 sector read on {emulator}: {values}')
PY
