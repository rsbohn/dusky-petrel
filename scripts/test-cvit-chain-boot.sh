#!/usr/bin/env bash
# Boot with COMMAND beyond the first directory block, then use chained CAT/TYPE/RUN.
set -euo pipefail
cd "$(dirname "$0")/.."
SIMH_NOVA=${SIMH_NOVA:-nova}
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
SNOVA=dusky/bin/Release/net9.0/Snova.dll
dotnet build dusky/Snova.csproj -c Release --nologo -v q >/dev/null
for pair in 'sd/cvit-boot.asm boot' 'simh/cvit-kernel-simh.asm kernel' 'sd/cvit-extension.asm extension' 'sd/focal.asm focal'; do
    set -- $pair
    dotnet "$SNOVA" abs "$1" "$TMP/$2.abs" --format simh-load >/dev/null
done
dotnet "$SNOVA" abs simh/cvit-command-simh.asm "$TMP/command.abs" --format simh-load --start 3000 >/dev/null
python3 scripts/abs2bin.py "$TMP/command.abs" "$TMP/command.bin" >/dev/null
python3 scripts/abs2flat.py --pz "$TMP/focal.abs" "$TMP/focal.sys" 0o6000 >/dev/null
N1=$(python3 -c "import struct; print(struct.unpack_from('<H',open('$TMP/command.bin','rb').read())[0])")
ENTRY=$(printf '0o%o' $((8#3000 + 1 + N1)))
printf 'Chained hello!\n' > "$TMP/hello.txt"
specs=()
for i in {0..8}; do specs+=("FILL$i=$TMP/hello.txt"); done
specs+=("COMMAND=$TMP/command.bin@0o3000,$ENTRY" "HELLO=$TMP/hello.txt" "FOCAL=$TMP/focal.sys@0o6000,0o6000" "FILL8=$TMP/hello.txt")
python3 scripts/mk_cvit_nova.py "$TMP/disk.tc" "${specs[@]}" >/dev/null
python3 simh/convert-tc08-to-dsk.py "$TMP/disk.tc" "$TMP/disk.dsk" >/dev/null
python3 scripts/install-dsk-boot.py "$TMP/disk.dsk" "$TMP/boot.abs" "$TMP/kernel.abs" "$TMP/extension.abs" >/dev/null
printf 'CATALOG\rTYPE HELLO\rRUN FOCAL\rQUIT\r' > "$TMP/input"
printf 'dsk0 attach %s/disk.dsk\ntty read %s/input\ncpu limit 3000000\nboot dsk\nquit\n' "$TMP" "$TMP" | dotnet "$SNOVA" > "$TMP/dusky.out"
printf 'attach dsk %s/disk.dsk\nsend after=200000,delay=200000 "CATALOG\\rTYPE HELLO\\rRUN FOCAL\\rQUIT\\r\\004"\nboot dsk\nexit\n' "$TMP" > "$TMP/simh.ini"
python3 - "$SIMH_NOVA" "$TMP/simh.ini" "$TMP/simh.out" <<'PY'
import subprocess, sys
with open(sys.argv[3], 'w') as output:
    subprocess.run([sys.argv[1], sys.argv[2]], stdin=subprocess.DEVNULL,
                   stdout=output, stderr=subprocess.STDOUT, check=True, timeout=30)
PY
for emulator in dusky simh; do
    tr -d '\r\000' < "$TMP/$emulator.out" > "$TMP/$emulator.clean"
    for text in 'FILL8' 'COMMAND' 'HELLO' 'FOCAL' 'Chained hello!' 'FOCAL/Nova V0.7'; do
        if ! grep -Fq "$text" "$TMP/$emulator.clean"; then
            echo "FAIL: $emulator missing $text" >&2
            cat "$TMP/$emulator.clean" >&2
            exit 1
        fi
    done
    for member in COMMAND HELLO FOCAL; do
        if ! grep -Eq "^${member} *$" "$TMP/$emulator.clean"; then
            echo "FAIL: $emulator CAT missing $member" >&2; exit 1
        fi
    done
    if [[ $(grep -Ec '^FILL8 +\[DUP\] *$' "$TMP/$emulator.clean") -ne 2 ]]; then
        echo "FAIL: $emulator did not flag both duplicate FILL8 entries" >&2
        cat "$TMP/$emulator.clean" >&2; exit 1
    fi
    if [[ $(grep -Fc 'cvit/Nova COMMAND V0.7' "$TMP/$emulator.clean") -lt 2 ]]; then
        echo "FAIL: $emulator did not warm-return from FOCAL" >&2; exit 1
    fi
    echo "PASS: $emulator chained COMMAND boot, CAT, TYPE, RUN and warm return"
done

# Tombstoned names must not trigger duplicate warnings.
cp "$TMP/disk.dsk" "$TMP/tombstone.dsk"
python3 - "$TMP/tombstone.dsk" <<'PY'
import struct, sys
with open(sys.argv[1], 'r+b') as image:
    image.seek(2 * 512 + (3 * 12 + 11) * 2)
    image.write(struct.pack('<H', 0x8000))
PY
printf 'CAT\r' > "$TMP/cat-input"
printf 'dsk0 attach %s/tombstone.dsk\ntty read %s/cat-input\ncpu limit 3000000\nboot dsk\nquit\n' "$TMP" "$TMP" | dotnet "$SNOVA" > "$TMP/tomb-dusky.out"
printf 'attach dsk %s/tombstone.dsk\nsend after=200000,delay=200000 "CAT\\r\\004"\nboot dsk\nexit\n' "$TMP" > "$TMP/tomb.ini"
python3 - "$SIMH_NOVA" "$TMP/tomb.ini" "$TMP/tomb-simh.out" <<'PY'
import subprocess, sys
with open(sys.argv[3], 'w') as output:
    subprocess.run([sys.argv[1], sys.argv[2]], stdin=subprocess.DEVNULL,
                   stdout=output, stderr=subprocess.STDOUT, check=True, timeout=30)
PY
for emulator in dusky simh; do
    tr -d '\r\000' < "$TMP/tomb-$emulator.out" > "$TMP/tomb-$emulator.clean"
    if [[ $(grep -Ec '^FILL8 *$' "$TMP/tomb-$emulator.clean") -ne 1 ]] ||
       grep -Fq '[DUP]' "$TMP/tomb-$emulator.clean"; then
        echo "FAIL: $emulator counted a tombstone as a duplicate" >&2
        cat "$TMP/tomb-$emulator.clean" >&2; exit 1
    fi
    echo "PASS: $emulator CAT ignores tombstoned duplicate"
done
