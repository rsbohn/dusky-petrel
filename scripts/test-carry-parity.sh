#!/usr/bin/env bash
# Operate-instruction carry parity: run sd/carry-test.asm on SIMH and Dusky
# and require identical carry/result output.
set -euo pipefail
cd "$(dirname "$0")/.."
SIMH_NOVA="${SIMH_NOVA:-nova}"
SNOVA="dusky/bin/Release/net9.0/Snova.dll"
[[ -f "$SNOVA" ]] || dotnet build dusky/Snova.csproj -c Release --nologo -v q
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT
dotnet "$SNOVA" abs sd/carry-test.asm "$TMPDIR/carry.abs" --format simh-load >/dev/null
printf 'load %s\ngo 1000\nexit\n' "$TMPDIR/carry.abs" > "$TMPDIR/carry.ini"
timeout 10 "$SIMH_NOVA" "$TMPDIR/carry.ini" 2>&1 | grep -o '[01]:[0-7]\{6\}' > "$TMPDIR/simh.txt" || true
printf 'asm sd/carry-test.asm\ngo 1000\nexit\n' | dotnet "$SNOVA" 2>&1 | grep -o '[01]:[0-7]\{6\}' > "$TMPDIR/dusky.txt" || true
cases=$(wc -l < "$TMPDIR/simh.txt")
if [[ "$cases" -ne 20 ]]; then
    echo "FAIL: expected 20 SIMH cases, got $cases" >&2
    exit 1
fi
if ! diff -u "$TMPDIR/simh.txt" "$TMPDIR/dusky.txt"; then
    echo "FAIL: Dusky carry results differ from SIMH" >&2
    exit 1
fi
echo "PASS: $cases operate-instruction carry cases match SIMH"
