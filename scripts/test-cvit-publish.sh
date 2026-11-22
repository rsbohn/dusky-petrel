#!/usr/bin/env bash
# Test directory preflight, publication, and duplicate rejection.
set -euo pipefail
cd "$(dirname "$0")/.."
SIMH_NOVA=${SIMH_NOVA:-nova}
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
SNOVA=dusky/bin/Release/net9.0/Snova.dll
scripts/build-image.sh "$TMP/base.dsk" >/dev/null
for pair in 'simh/cvit-kernel-simh.asm kernel' 'sd/cvit-extension.asm extension' 'sd/cvit-publish-test.asm test'; do
    set -- $pair
    dotnet "$SNOVA" abs "$1" "$TMP/$2.abs" --format simh-load >/dev/null
done
python3 - "$TMP" "$SIMH_NOVA" "$SNOVA" <<'PY'
import pathlib, re, subprocess, sys
root, simh, snova = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3]
for emulator in ('dusky', 'simh'):
    disk = root / f'publish-{emulator}.dsk'
    disk.write_bytes((root / 'base.dsk').read_bytes())
    if emulator == 'dusky':
        commands = (f'dsk0 attach {disk}\nasm simh/cvit-kernel-simh.asm\n'
                    'asm sd/cvit-extension.asm\nasm sd/cvit-publish-test.asm\n'
                    'go 4000 100000\nexam 4210 6\nexam 4216 3\nquit\n')
        proc = subprocess.run(['dotnet', snova], input=commands, text=True,
                              capture_output=True, timeout=20, check=True)
        match = re.search(r'004210:\s+([0-7]+)\s+([0-7]+)\s+([0-7]+)\s+([0-7]+)\s+([0-7]+)\s+([0-7]+)', proc.stdout)
        checks = re.search(r'004216:\s+([0-7]+)\s+([0-7]+)\s+([0-7]+)', proc.stdout)
        values = tuple(int(v, 8) for v in match.groups() + checks.groups()) if match and checks else None
    else:
        ini = root / 'publish.ini'
        ini.write_text(f'attach dsk {disk}\nload {root}/kernel.abs\n'
                       f'load {root}/extension.abs\nload {root}/test.abs\n'
                       'go 4000\nex 4210-4220\ndetach dsk\nexit\n')
        proc = subprocess.run([simh, str(ini)], stdin=subprocess.DEVNULL,
                              text=True, capture_output=True, timeout=20, check=True)
        found = re.findall(r'^(?:421[0-7]|4220):\s+([0-7]+)', proc.stdout, re.M)
        values = tuple(int(v, 8) for v in found) if len(found) == 9 else None
    # Publish and lookup succeed; original TXT metadata is unchanged.
    # Preflight succeeds without publishing, then a duplicate is refused.
    expected = (0, 0, 1, 2, 1, 1, 0, 1, 1)
    if values != expected:
        raise SystemExit(f'{emulator}: publication/lookup values {values} != {expected}\n{proc.stdout}\n{proc.stderr}')
    print(f'PASS: directory publication and lookup on {emulator}')
PY
