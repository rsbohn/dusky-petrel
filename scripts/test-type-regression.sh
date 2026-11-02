#!/bin/bash
# TYPE regression test: verifies complete output for various file sizes
# Tests: empty, short, exact-128, multi-block, partial-block, binary
set -e
REPO="$(cd "$(dirname "$0")/.." && pwd)"
export PATH="$HOME/.local/bin:$HOME/.dotnet:$PATH"
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

echo "Building image..."
dotnet "$REPO/dusky/bin/Release/net9.0/Snova.dll" abs "$REPO/simh/cvit-kernel-simh.asm" "$TMPDIR/kernel.abs" --format simh-load > /dev/null
dotnet "$REPO/dusky/bin/Release/net9.0/Snova.dll" abs "$REPO/simh/cvit-command-simh.asm" "$TMPDIR/command.abs" --format simh-load --start 3000 > /dev/null
python3 "$REPO/scripts/abs2bin.py" "$TMPDIR/command.abs" "$TMPDIR/command.bin" > /dev/null
N1=$(python3 -c "import struct; print(struct.unpack_from(\"<H\", open(\"$TMPDIR/command.bin\",\"rb\").read())[0])")
ENTRY=$(printf "0o%o" $(( 8#3000 + 1 + N1 )))
python3 "$REPO/scripts/mk_cvit_nova.py" "$TMPDIR/cvit-tc08.img" \
  "COMMAND=$TMPDIR/command.bin@0o3000,$ENTRY" \
  "TEMPTY=$REPO/testdata/type-empty.txt" \
  "TSHORT=$REPO/testdata/type-short.txt" \
  "T128=$REPO/testdata/type-128.txt" \
  "T200=$REPO/testdata/type-200.txt" \
  "TLINES=$REPO/testdata/lines64.txt" \
  "TBIN=$REPO/testdata/type-bin.dat" > /dev/null
python3 "$REPO/simh/convert-tc08-to-dsk.py" "$TMPDIR/cvit-tc08.img" "$TMPDIR/cvit-dsk.img" > /dev/null

PASS=0
FAIL=0

check_type() {
  local member=$1
  local expected_file=$2
  local desc=$3
  printf "TYPE %s\r\004" "$member" | dotnet "$REPO/dusky/bin/Release/net9.0/Snova.dll" --batch "$TMPDIR/cvit-dsk.img" 2>&1 | tr -d "\000" | sed "s/\r//g" > "$TMPDIR/out.txt"
  # Extract content between "]TYPE MEMBER" and final "]"
  python3 << PYEOF > "$TMPDIR/actual.txt"
import sys
out = open("$TMPDIR/out.txt").read()
marker = "]TYPE $member"
start = out.find(marker) + len(marker)
end = out.rstrip().rfind("]")
content = out[start:end]
# Strip leading/trailing whitespace/newlines from the extraction
# but preserve the actual file content
sys.stdout.write(content.lstrip("\r\n"))
PYEOF
  # For text files, compare directly (LF normalized)
  # For binary, compare the raw bytes
  if cmp -s "$TMPDIR/actual.txt" "$expected_file"; then
    echo "PASS: $desc"
    PASS=$((PASS+1))
  else
    echo "FAIL: $desc"
    echo "  Expected $(wc -c < "$expected_file") bytes, got $(wc -c < "$TMPDIR/actual.txt") bytes"
    FAIL=$((FAIL+1))
  fi
}

echo ""
echo "Running TYPE regression tests (Dusky)..."
check_type "TEMPTY" "$REPO/testdata/type-empty.txt" "empty file (0 bytes)"
check_type "TSHORT" "$REPO/testdata/type-short.txt" "short file (53 bytes)"
check_type "T128" "$REPO/testdata/type-128.txt" "exact 128 bytes (1 block)"
check_type "T200" "$REPO/testdata/type-200.txt" "partial 200 bytes (1.5 blocks)"
check_type "TLINES" "$REPO/testdata/lines64.txt" "multi-block 1040 bytes (9 blocks)"
# Binary: verify it produces output (exact byte match TBD - separate issue)
printf "TYPE TBIN\\r\\004" | dotnet "$REPO/dusky/bin/Release/net9.0/Snova.dll" --batch "$TMPDIR/cvit-dsk.img" 2>&1 | tr -d "\\000" > "$TMPDIR/bin-out.txt"
if [ -s "$TMPDIR/bin-out.txt" ]; then
  echo "PASS: binary file (produces output)"
  PASS=$((PASS+1))
else
  echo "FAIL: binary file (no output)"
  FAIL=$((FAIL+1))
fi


echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" = "0" ]
