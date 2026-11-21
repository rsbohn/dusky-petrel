#!/usr/bin/env bash
# Vertical slice: syscall 6 reads the first member on both emulators.
set -euo pipefail
cd "$(dirname "$0")/.."
SIMH_NOVA=${SIMH_NOVA:-nova}
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
scripts/build-image.sh "$TMP/disk" >/dev/null
SNOVA=dusky/bin/Release/net9.0/Snova.dll
for source in simh/cvit-kernel-simh.asm sd/cvit-extension.asm sd/cvit-enum-test.asm; do
    name=$(basename "$source" .asm)
    dotnet "$SNOVA" abs "$source" "$TMP/$name.abs" --format simh-load >/dev/null
done
printf 'dsk0 attach %s/disk\nasm simh/cvit-kernel-simh.asm\nasm sd/cvit-extension.asm\nasm sd/cvit-enum-test.asm\nrun 100000\nexam 4010 1\nexam 4015 1\nquit\n' "$TMP" | dotnet "$SNOVA" > "$TMP/dusky.out"
grep -Eq '004010: +000000' "$TMP/dusky.out"
grep -Eq '004015: +041517' "$TMP/dusky.out"
printf 'attach dsk %s/disk\nload %s/cvit-kernel-simh.abs\nload %s/cvit-extension.abs\nload %s/cvit-enum-test.abs\ngo 4000\nex 4010\nex 4015\nexit\n' "$TMP" "$TMP" "$TMP" "$TMP" > "$TMP/simh.ini"
"$SIMH_NOVA" "$TMP/simh.ini" </dev/null > "$TMP/simh.out"
grep -Eq '4010:[[:space:]]+000000' "$TMP/simh.out"
grep -Eq '4015:[[:space:]]+041517' "$TMP/simh.out"
echo 'PASS: syscall 6 reads first directory entry on Dusky and SIMH'
