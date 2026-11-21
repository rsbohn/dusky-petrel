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
printf 'dsk0 attach %s/disk\nasm simh/cvit-kernel-simh.asm\nasm sd/cvit-extension.asm\nasm sd/cvit-enum-test.asm\nrun 100000\nexam 4010 1\nexam 4115 1\nquit\n' "$TMP" | dotnet "$SNOVA" > "$TMP/dusky.out"
grep -Eq '004010: +000000' "$TMP/dusky.out"
grep -Eq '004115: +041517' "$TMP/dusky.out"
printf 'attach dsk %s/disk\nload %s/cvit-kernel-simh.abs\nload %s/cvit-extension.abs\nload %s/cvit-enum-test.abs\ngo 4000\nex 4010\nex 4115\nexit\n' "$TMP" "$TMP" "$TMP" "$TMP" > "$TMP/simh.ini"
"$SIMH_NOVA" "$TMP/simh.ini" </dev/null > "$TMP/simh.out"
grep -Eq '4010:[[:space:]]+000000' "$TMP/simh.out"
grep -Eq '4115:[[:space:]]+041517' "$TMP/simh.out"
echo 'PASS: syscall 6 reads first directory entry on Dusky and SIMH'

# Ten members force a second directory block; the tenth is FILE9.
printf 'x' > "$TMP/member.txt"
specs=()
for i in {0..9}; do specs+=("FILE$i=$TMP/member.txt"); done
python3 scripts/mk_cvit_nova.py "$TMP/chain.tc" "${specs[@]}" >/dev/null
python3 simh/convert-tc08-to-dsk.py "$TMP/chain.tc" "$TMP/chain.dsk" >/dev/null
dotnet "$SNOVA" abs sd/cvit-enum-chain-test.asm "$TMP/chain.abs" --format simh-load >/dev/null
printf 'dsk0 attach %s/chain.dsk\nasm simh/cvit-kernel-simh.asm\nasm sd/cvit-extension.asm\nasm sd/cvit-enum-chain-test.asm\nrun 100000\nexam 4122 1\nquit\n' "$TMP" | dotnet "$SNOVA" > "$TMP/dusky-chain.out"
grep -Eq '004122: +034440' "$TMP/dusky-chain.out"
printf 'attach dsk %s/chain.dsk\nload %s/cvit-kernel-simh.abs\nload %s/cvit-extension.abs\nload %s/chain.abs\ngo 4000\nex 4122\nexit\n' "$TMP" "$TMP" "$TMP" "$TMP" > "$TMP/simh-chain.ini"
"$SIMH_NOVA" "$TMP/simh-chain.ini" </dev/null > "$TMP/simh-chain.out"
grep -Eq '4122:[[:space:]]+034440' "$TMP/simh-chain.out"
echo 'PASS: syscall 6 traverses a second directory block on Dusky and SIMH'

# A version other than 2 is rejected before any directory is read.
cp "$TMP/chain.dsk" "$TMP/bad-header.dsk"
python3 - "$TMP/bad-header.dsk" <<'PY'
import struct, sys
with open(sys.argv[1], 'r+b') as image:
    image.seek(4)
    image.write(struct.pack('<H', 1))
PY
printf 'dsk0 attach %s/bad-header.dsk\nasm simh/cvit-kernel-simh.asm\nasm sd/cvit-extension.asm\nasm sd/cvit-enum-test.asm\nrun 100000\nexam 4010 1\nquit\n' "$TMP" | dotnet "$SNOVA" > "$TMP/dusky-bad.out"
grep -Eq '004010: +000003' "$TMP/dusky-bad.out"
printf 'attach dsk %s/bad-header.dsk\nload %s/cvit-kernel-simh.abs\nload %s/cvit-extension.abs\nload %s/cvit-enum-test.abs\ngo 4000\nex 4010\nexit\n' "$TMP" "$TMP" "$TMP" "$TMP" > "$TMP/simh-bad.ini"
"$SIMH_NOVA" "$TMP/simh-bad.ini" </dev/null > "$TMP/simh-bad.out"
grep -Eq '4010:[[:space:]]+000003' "$TMP/simh-bad.out"
echo 'PASS: syscall 6 rejects unsupported volume versions on Dusky and SIMH'

cp "$TMP/chain.dsk" "$TMP/cycle.dsk"
python3 - "$TMP/cycle.dsk" <<'PY'
import struct, sys
with open(sys.argv[1], 'r+b') as image:
    image.seek(2 * 512 + 114 * 2)
    image.write(struct.pack('<H', 1))
PY
dotnet "$SNOVA" abs sd/cvit-enum-cycle-test.asm "$TMP/cycle.abs" --format simh-load >/dev/null
printf 'dsk0 attach %s/cycle.dsk\nasm simh/cvit-kernel-simh.asm\nasm sd/cvit-extension.asm\nasm sd/cvit-enum-cycle-test.asm\nrun 100000\nexam 4016 2\nquit\n' "$TMP" | dotnet "$SNOVA" > "$TMP/dusky-cycle.out"
grep -Eq '004016: +000003 +000003' "$TMP/dusky-cycle.out"
printf 'attach dsk %s/cycle.dsk\nload %s/cvit-kernel-simh.abs\nload %s/cvit-extension.abs\nload %s/cycle.abs\ngo 4000\nex 4016\nex 4017\nexit\n' "$TMP" "$TMP" "$TMP" "$TMP" > "$TMP/simh-cycle.ini"
python3 - "$SIMH_NOVA" "$TMP/simh-cycle.ini" "$TMP/simh-cycle.out" <<'PY'
import subprocess, sys
with open(sys.argv[3], 'w') as output:
    subprocess.run([sys.argv[1], sys.argv[2]], stdin=subprocess.DEVNULL,
                   stdout=output, stderr=subprocess.STDOUT, check=True, timeout=15)
PY
grep -Eq '4016:[[:space:]]+000003' "$TMP/simh-cycle.out"
grep -Eq '4017:[[:space:]]+000003' "$TMP/simh-cycle.out"
echo 'PASS: syscall 6 detects a directory cycle on Dusky and SIMH'

# Lookup a member in the second block, a missing member, and a cyclic chain.
python3 - "$TMP/missing.asm" <<'PY'
from pathlib import Path
import sys
source = Path('sd/cvit-lookup-test.asm').read_text()
Path(sys.argv[1]).write_text(source.replace('0o34440', '0o35440'))
Path(sys.argv[1]).with_name('first.asm').write_text(source.replace('0o34440', '0o30040'))
PY
check_lookup() {
    local label=$1 disk=$2 source=$3 status=$4 expected=${5:-034440}
    dotnet "$SNOVA" abs "$source" "$TMP/lookup.abs" --format simh-load >/dev/null
    printf 'dsk0 attach %s\nasm simh/cvit-kernel-simh.asm\nasm sd/cvit-extension.asm\nasm %s\nrun 100000\nexam 4010 1\nexam 4023 1\nquit\n' "$disk" "$source" | dotnet "$SNOVA" > "$TMP/lookup-dusky.out"
    grep -Eq "004010: +$status" "$TMP/lookup-dusky.out"
    if [[ $status == 000000 ]]; then grep -Eq "004023: +$expected" "$TMP/lookup-dusky.out"; fi
    printf 'attach dsk %s\nload %s/cvit-kernel-simh.abs\nload %s/cvit-extension.abs\nload %s/lookup.abs\ngo 4000\nex 4010\nex 4023\nexit\n' "$disk" "$TMP" "$TMP" "$TMP" > "$TMP/lookup.ini"
    python3 - "$SIMH_NOVA" "$TMP/lookup.ini" "$TMP/lookup-simh.out" <<'PY'
import subprocess, sys
with open(sys.argv[3], 'w') as output:
    subprocess.run([sys.argv[1], sys.argv[2]], stdin=subprocess.DEVNULL,
                   stdout=output, stderr=subprocess.STDOUT, check=True, timeout=15)
PY
    grep -Eq "4010:[[:space:]]+$status" "$TMP/lookup-simh.out"
    if [[ $status == 000000 ]]; then grep -Eq "4023:[[:space:]]+$expected" "$TMP/lookup-simh.out"; fi
    echo "PASS: lookup $label on Dusky and SIMH"
}
check_lookup 'first-block member' "$TMP/chain.dsk" "$TMP/first.asm" 000000 030040
check_lookup 'second-block member' "$TMP/chain.dsk" sd/cvit-lookup-test.asm 000000
check_lookup 'missing member' "$TMP/chain.dsk" "$TMP/missing.asm" 000001
check_lookup 'cycle' "$TMP/cycle.dsk" "$TMP/missing.asm" 000003
check_lookup 'invalid volume' "$TMP/bad-header.dsk" sd/cvit-lookup-test.asm 000003
cp "$TMP/chain.dsk" "$TMP/tombstone.dsk"
python3 - "$TMP/tombstone.dsk" <<'PY'
import struct, sys
with open(sys.argv[1], 'r+b') as image:
    image.seek(2 * 512 + 11 * 2)
    image.write(struct.pack('<H', 0x8000))
PY
check_lookup 'tombstoned member' "$TMP/tombstone.dsk" sd/cvit-lookup-test.asm 000001
