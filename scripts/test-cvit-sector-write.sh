#!/usr/bin/env bash
# Exercise kernel block writes on disposable images in Dusky and SIMH.
set -euo pipefail
cd "$(dirname "$0")/.."
SIMH_NOVA=${SIMH_NOVA:-nova}
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
SNOVA=dusky/bin/Release/net9.0/Snova.dll
scripts/build-image.sh "$TMP/base.dsk" >/dev/null
python3 - "$TMP/base.dsk" <<'PY'
import struct, sys
with open(sys.argv[1], 'rb') as image:
    header = struct.unpack('<7H', image.read(14))
    if header[6] > 1014:
        raise SystemExit('test sector 1014 is allocated')
PY
cp "$TMP/base.dsk" "$TMP/dusky.dsk"
cp "$TMP/base.dsk" "$TMP/simh.dsk"
for pair in 'simh/cvit-kernel-simh.asm kernel' 'sd/cvit-extension.asm extension' 'sd/cvit-write-test.asm test'; do
    set -- $pair
    dotnet "$SNOVA" abs "$1" "$TMP/$2.abs" --format simh-load >/dev/null
done
printf 'dsk0 attach %s/dusky.dsk\nasm simh/cvit-kernel-simh.asm\nasm sd/cvit-extension.asm\nasm sd/cvit-write-test.asm\nrun 100000\nexam 4200 3\nquit\n' "$TMP" | dotnet "$SNOVA" > "$TMP/dusky.out"
grep -Eq '004200: +000001 +000001 +012345' "$TMP/dusky.out"
printf 'attach dsk %s/simh.dsk\nload %s/kernel.abs\nload %s/extension.abs\nload %s/test.abs\ngo 4000\nex 4200-4202\ndetach dsk\nexit\n' "$TMP" "$TMP" "$TMP" "$TMP" > "$TMP/simh.ini"
python3 - "$SIMH_NOVA" "$TMP/simh.ini" "$TMP/simh.out" <<'PY'
import subprocess, sys
with open(sys.argv[3], 'w') as output:
    subprocess.run([sys.argv[1], sys.argv[2]], stdin=subprocess.DEVNULL,
                   stdout=output, stderr=subprocess.STDOUT, check=True, timeout=15)
PY
grep -Eq '4200:[[:space:]]+000001' "$TMP/simh.out"
grep -Eq '4201:[[:space:]]+000001' "$TMP/simh.out"
grep -Eq '4202:[[:space:]]+012345' "$TMP/simh.out"
python3 - "$TMP/dusky.dsk" "$TMP/simh.dsk" <<'PY'
import struct, sys
for path in sys.argv[1:]:
    with open(path, 'rb') as image:
        image.seek(1014 * 512)
        value, = struct.unpack('<H', image.read(2))
    if value != 0o12345:
        raise SystemExit(f'{path}: persisted word {value:o}, expected 12345')
print('PASS: kernel sector write/read persisted on Dusky and SIMH')
PY
