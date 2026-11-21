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
specs+=("COMMAND=$TMP/command.bin@0o3000,$ENTRY" "HELLO=$TMP/hello.txt" "FOCAL=$TMP/focal.sys@0o6000,0o6000")
python3 scripts/mk_cvit_nova.py "$TMP/disk.tc" "${specs[@]}" >/dev/null
python3 simh/convert-tc08-to-dsk.py "$TMP/disk.tc" "$TMP/disk.dsk" >/dev/null
python3 scripts/install-dsk-boot.py "$TMP/disk.dsk" "$TMP/boot.abs" "$TMP/kernel.abs" "$TMP/extension.abs" >/dev/null
printf 'CAT\rTYPE HELLO\rRUN FOCAL\rQUIT\r' > "$TMP/input"
printf 'dsk0 attach %s/disk.dsk\ntty read %s/input\ncpu limit 3000000\nboot dsk\nquit\n' "$TMP" "$TMP" | dotnet "$SNOVA" > "$TMP/dusky.out"
printf 'attach dsk %s/disk.dsk\nsend after=200000,delay=200000 "CAT\\rTYPE HELLO\\rRUN FOCAL\\rQUIT\\r\\004"\nboot dsk\nexit\n' "$TMP" > "$TMP/simh.ini"
python3 - "$SIMH_NOVA" "$TMP/simh.ini" "$TMP/simh.out" <<'PY'
import subprocess, sys
with open(sys.argv[3], 'w') as output:
    subprocess.run([sys.argv[1], sys.argv[2]], stdin=subprocess.DEVNULL,
                   stdout=output, stderr=subprocess.STDOUT, check=True, timeout=30)
PY
for emulator in dusky simh; do
    tr -d '\r\000' < "$TMP/$emulator.out" > "$TMP/$emulator.clean"
    for text in 'FILL8' 'COMMAND' 'HELLO' 'FOCAL' 'Chained hello!' 'FOCAL/Nova V0.1'; do
        if ! grep -Fq "$text" "$TMP/$emulator.clean"; then
            echo "FAIL: $emulator missing $text" >&2
            cat "$TMP/$emulator.clean" >&2
            exit 1
        fi
    done
    for member in FILL8 COMMAND HELLO FOCAL; do
        if ! grep -Eq "^${member} *$" "$TMP/$emulator.clean"; then
            echo "FAIL: $emulator CAT missing $member" >&2; exit 1
        fi
    done
    if [[ $(grep -Fc 'cvit/Nova COMMAND V0.1' "$TMP/$emulator.clean") -lt 2 ]]; then
        echo "FAIL: $emulator did not warm-return from FOCAL" >&2; exit 1
    fi
    echo "PASS: $emulator chained COMMAND boot, CAT, TYPE, RUN and warm return"
done
