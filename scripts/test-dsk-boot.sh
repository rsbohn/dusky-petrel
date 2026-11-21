#!/usr/bin/env bash
# Build one image and boot it on both emulators, exercising warm return.
set -euo pipefail
cd "$(dirname "$0")/.."
SIMH_NOVA=${SIMH_NOVA:-nova}
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
scripts/build-image.sh "$TMP/cvit.dsk" >/dev/null
printf 'STA\rCAT\rTYPE HELLO\rRUN FOCAL\rQUIT\r' > "$TMP/input"
printf 'dsk0 attach %s/cvit.dsk\ntty read %s/input\ncpu limit 2000000\nboot dsk\nquit\n' "$TMP" "$TMP" | \
    dotnet dusky/bin/Release/net9.0/Snova.dll > "$TMP/dusky.out"
cat > "$TMP/simh.ini" <<EOF
attach dsk $TMP/cvit.dsk
send after=200000,delay=200000 "STA\rCAT\rTYPE HELLO\rRUN FOCAL\rQUIT\r\004"
boot dsk
exit
EOF
"$SIMH_NOVA" "$TMP/simh.ini" </dev/null > "$TMP/simh.out"
for emulator in dusky simh; do
    tr -d '\r\000' < "$TMP/$emulator.out" > "$TMP/$emulator.clean"
    for expected in 'cvit/Nova V0.1' 'CVNV READY' 'FOCAL/Nova V0.1' 'Hello from CVIT/Nova!' 'cvit/Nova COMMAND V0.1'; do
        if ! grep -Fq "$expected" "$TMP/$emulator.clean"; then
            echo "FAIL: $emulator missing $expected" >&2
            cat "$TMP/$emulator.clean" >&2
            exit 1
        fi
    done
    if [[ $(grep -Fc 'cvit/Nova COMMAND V0.1' "$TMP/$emulator.clean") -lt 2 ]]; then
        echo "FAIL: $emulator did not return from FOCAL" >&2
        exit 1
    fi
    grep -Fq 'HALT' "$TMP/$emulator.clean" || { echo "FAIL: $emulator did not halt" >&2; exit 1; }
    echo "PASS: $emulator boot, commands, FOCAL, and warm return"
done
