#!/usr/bin/env bash
# Acceptance smoke tests for the SIMH CVIT/Nova image: STA, CAT, and TYPE.
set -euo pipefail
cd "$(dirname "$0")/.."

SIMH_NOVA="${SIMH_NOVA:-nova}"
for tool in "$SIMH_NOVA" dotnet python3; do
    command -v "$tool" >/dev/null 2>&1 || { echo "Required command not found: $tool" >&2; exit 1; }
done

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT
SNOVA="dusky/bin/Release/net9.0/Snova.dll"
if [[ ! -f "$SNOVA" ]]; then
    dotnet build dusky/Snova.csproj -c Release --nologo -v q
fi

dotnet "$SNOVA" abs simh/cvit-kernel-simh.asm "$TMPDIR/kernel.abs" --format simh-load
dotnet "$SNOVA" abs simh/cvit-command-simh.asm "$TMPDIR/command.abs" --format simh-load --start 3000
python3 scripts/abs2bin.py "$TMPDIR/command.abs" "$TMPDIR/command.bin"
printf 'Hello from CVIT/Nova!\nThis is a sample text file.\n' > "$TMPDIR/hello.txt"
N1=$(python3 -c "import struct; print(struct.unpack_from('<H', open('$TMPDIR/command.bin','rb').read())[0])")
ENTRY=$(printf '0o%o' $(( 8#3000 + 1 + N1 )))
python3 scripts/mk_cvit_nova.py "$TMPDIR/cvit-tc08.img" \
    "COMMAND=$TMPDIR/command.bin@0o3000,$ENTRY" \
    README.md=README.md "HELLO=$TMPDIR/hello.txt"
python3 simh/convert-tc08-to-dsk.py "$TMPDIR/cvit-tc08.img" "$TMPDIR/cvit-dsk.img"

cat > "$TMPDIR/simh.ini" <<EOF
attach dsk $TMPDIR/cvit-dsk.img
load $TMPDIR/kernel.abs
send after=100000,delay=1000 "STA\\rCAT\\rTYPE HELLO\\r\\004"
go 1000
EOF
# EOT halts the simulated CPU; the timeout also bounds the run if a regression
# prevents that input from being consumed. The harness works on macOS and Linux.
python3 - "$SIMH_NOVA" "$TMPDIR/simh.ini" "$TMPDIR/output.txt" <<'PY'
import subprocess, sys
sim, ini, output = sys.argv[1:]
try:
    result = subprocess.run([sim, ini], capture_output=True, text=True, timeout=15)
except subprocess.TimeoutExpired as exc:
    stdout = exc.stdout or ""
    stderr = exc.stderr or ""
    if isinstance(stdout, bytes): stdout = stdout.decode(errors="replace")
    if isinstance(stderr, bytes): stderr = stderr.decode(errors="replace")
    open(output, "w").write((stdout + stderr).replace(chr(0), ""))
else:
    open(output, "w").write((result.stdout + result.stderr).replace(chr(0), ""))
PY

assert_output() {
    local expected=$1
    if ! grep -Fq "$expected" "$TMPDIR/output.txt"; then
        echo "FAIL: expected output not found: $expected" >&2
        echo "--- SIMH output ---" >&2
        cat "$TMPDIR/output.txt" >&2
        exit 1
    fi
    echo "PASS: $expected"
}

assert_output 'TC0: CVNV READY'
assert_output 'COMMAND'
assert_output 'README'
assert_output 'HELLO'
assert_output 'Hello from CVIT/Nova!'
assert_output 'This is a sample text file.'
echo 'CVIT/SIMH acceptance tests passed.'
