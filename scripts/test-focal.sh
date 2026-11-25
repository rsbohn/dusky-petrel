#!/usr/bin/env bash
# FOCAL/Nova acceptance test: run testdata/focal-session.txt through
# RUN FOCAL on both Dusky (batch mode) and SIMH (disk boot), and require each
# transcript to match testdata/focal-session.expected.
#   scripts/test-focal.sh            compare
#   scripts/test-focal.sh --update   rewrite the expected file from Dusky
set -euo pipefail
cd "$(dirname "$0")/.."
SIMH_NOVA="${SIMH_NOVA:-nova}"
SNOVA="dusky/bin/Release/net9.0/Snova.dll"
for tool in "$SIMH_NOVA" dotnet python3; do
    command -v "$tool" >/dev/null 2>&1 || { echo "Required command not found: $tool" >&2; exit 1; }
done
dotnet build dusky/Snova.csproj -c Release --nologo -v q
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

dotnet "$SNOVA" abs sd/cvit-boot.asm "$TMPDIR/boot.abs" --format simh-load >/dev/null
dotnet "$SNOVA" abs simh/cvit-kernel-simh.asm "$TMPDIR/kernel.abs" --format simh-load >/dev/null
dotnet "$SNOVA" abs sd/cvit-extension.asm "$TMPDIR/extension.abs" --format simh-load >/dev/null
dotnet "$SNOVA" abs simh/cvit-command-simh.asm "$TMPDIR/command.abs" --format simh-load --start 3000 >/dev/null
dotnet "$SNOVA" abs sd/focal.asm "$TMPDIR/focal.abs" --format simh-load >/dev/null
python3 scripts/abs2bin.py "$TMPDIR/command.abs" "$TMPDIR/command.bin" >/dev/null
python3 scripts/abs2flat.py --pz "$TMPDIR/focal.abs" "$TMPDIR/focal.sys" 0o6000 >/dev/null
N1=$(python3 -c "import struct; print(struct.unpack_from('<H', open('$TMPDIR/command.bin','rb').read())[0])")
ENTRY=$(printf '0o%o' $(( 8#3000 + 1 + N1 )))
# Build independent reader fixtures, without relying on LOCAL WRITE.
python3 - "$TMPDIR" <<'PY'
from pathlib import Path
import struct
import sys

root = Path(sys.argv[1])
header = [0x464F, 0x434C, 1]

def record(number, text):
    return [number, *text.encode('ascii'), 0]

def member(name, words):
    (root / f'{name}.bin').write_bytes(struct.pack(f'<{len(words)}H', *words))

# The second record crosses a sector boundary.
lines = record(110, 'C ' + 'A' * 60) + record(120, 'C ' + 'B' * 60)
member('foo', header + lines + record(130, 'T "LOADED"!') + [0])
# Not discovered until after records have been copied from both sectors.
member('badfoo', header + lines + record(101, 'T "PARTIAL"!') + [0])
member('empty', header + [0])
full = []
for i in range(163):
    full += record(101 + i + i // 99, 'C ' + 'X' * 64)
full += record(265, 'T "AT LIMIT"!'.ljust(49)) + [0]
assert len(full) == 0o55600 - 0o30000
member('fullfoo', header + full)
member('toobig', header + full + [0])
(root / 'wrong.txt').write_text('Not a FOCAL program.\n')
PY
fillers=()
for i in {1..8}; do fillers+=("FILL$i=$TMPDIR/wrong.txt"); done
python3 scripts/mk_cvit_nova.py "$TMPDIR/cvit-tc08.img" \
    "COMMAND=$TMPDIR/command.bin@0o3000,$ENTRY" \
    "FOCAL=$TMPDIR/focal.sys@0o6000,0o6000" \
    "FOO=$TMPDIR/foo.bin" "BADFOO=$TMPDIR/badfoo.bin" "EMPTY=$TMPDIR/empty.bin" \
    "FULLFOO=$TMPDIR/fullfoo.bin" "TOOBIG=$TMPDIR/toobig.bin" "WRONG=$TMPDIR/wrong.txt" \
    "${fillers[@]}" >/dev/null
python3 simh/convert-tc08-to-dsk.py "$TMPDIR/cvit-tc08.img" "$TMPDIR/cvit-dsk.img" >/dev/null
python3 scripts/install-dsk-boot.py "$TMPDIR/cvit-dsk.img" \
    "$TMPDIR/boot.abs" "$TMPDIR/kernel.abs" "$TMPDIR/extension.abs" >/dev/null
for emu in dusky simh; do
    cp "$TMPDIR/cvit-dsk.img" "$TMPDIR/$emu.dsk"
done

# Session input: RUN FOCAL, the test lines (LF -> CR), then EOT so the
# COMMAND prompt reached after QUIT halts the machine.
python3 - "$TMPDIR/session.in" "$TMPDIR/simh.ini" "$TMPDIR" <<'PY'
import sys
out, ini, tmp = sys.argv[1:]
lines = ["RUN FOCAL"] + open("testdata/focal-session.txt").read().splitlines()
data = "".join(line + "\r" for line in lines) + "\x04"
open(out, "w", newline="").write(data)
# SEND appends to the input queue. Split before escaping to stay below
# SIMH's command-line limit for long sessions.
def send(chunk):
    esc = (chunk.replace("\\", "\\\\").replace('"', '\\"').replace("%", "%%")
           .replace("\r", "\\r").replace("\x04", "\\004"))
    # Allow time to stream and validate a full program before the next line.
    return f'send after=1000000,delay=1000000 "{esc}"\n'

open(ini, "w").write(
    f"attach dsk {tmp}/simh.dsk\n"
    + "".join(send(data[i:i+256]) for i in range(0, len(data), 256))
    + "boot dsk\nexit\n")
PY

# Keep the FOCAL part of a transcript: from the banner to the COMMAND
# prompt that follows QUIT.
extract() {
    tr -d '\000\r' | sed -n '/^FOCAL\/Nova/,/^cvit\/Nova COMMAND/p'
}

dotnet "$SNOVA" --batch "$TMPDIR/dusky.dsk" < "$TMPDIR/session.in" 2>&1 | extract > "$TMPDIR/dusky.txt" || true
if [[ "${1:-}" == "--update" ]]; then
    cp "$TMPDIR/dusky.txt" testdata/focal-session.expected
    echo "Updated testdata/focal-session.expected from Dusky."
    exit 0
fi
python3 - "$SIMH_NOVA" "$TMPDIR/simh.ini" <<'PY' | extract > "$TMPDIR/simh.txt"
import subprocess, sys
try:
    result = subprocess.run([sys.argv[1], sys.argv[2]], stdin=subprocess.DEVNULL,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                            timeout=60)
    sys.stdout.buffer.write(result.stdout)
except subprocess.TimeoutExpired as exc:
    sys.stdout.buffer.write(exc.stdout or b'')
PY

status=0
for emu in dusky simh; do
    if diff -u testdata/focal-session.expected "$TMPDIR/$emu.txt" > "$TMPDIR/$emu.diff"; then
        echo "PASS: $emu transcript matches ($(wc -l < "$TMPDIR/$emu.txt") lines)"
    else
        echo "FAIL: $emu transcript differs:" >&2
        cat "$TMPDIR/$emu.diff" >&2
        status=1
    fi
done
if [[ $status == 0 ]]; then
    python3 - "$TMPDIR" <<'PY'
import pathlib, struct, sys

root = pathlib.Path(sys.argv[1])
original = (root / 'cvit-dsk.img').read_bytes()
next_free = struct.unpack_from('<H', original, 12)[0]
# Both saves occupy the last slots in block 2. A9-B_C.TXT is saved three
# times in the session: the first save allocates at next_free, and each
# re-save is a copy-on-write replace allocating a fresh 2-block extent,
# so the live entry starts at next_free + 4.
for emu in ('dusky', 'simh'):
    disk = (root / f'{emu}.dsk').read_bytes()
    block = next_free + 4
    for slot, name in enumerate(('A9-B_C.TXT', 'SAVEMPTY'), start=7):
        entry = struct.unpack_from('<12H', disk, 2 * 512 + slot * 24)
        assert struct.pack('>5H', *entry[:5]).decode().rstrip() == name, (emu, entry)
        typ, start, count, load, run, length, flags = entry[5:]
        assert (typ, start, load, run, flags) == (2, block, 0, 0, 0), (emu, entry)
        assert count == (length + 127) // 128, (emu, entry)
        words = []
        for sector in range(block, block + count):
            words.extend(struct.unpack_from('<128H', disk, sector * 512))
        assert words[:3] == [0x464F, 0x434C, 1], (emu, name)
        assert not any(words[length-1:]), (emu, name)
        if name == 'SAVEMPTY':
            assert length == 4 and count == 1, (emu, entry)
        else:
            assert count > 1 and words[3] == 110, (emu, entry)
        block += count
    # NOSLOT no longer fails: publication grows the chain by one block.
    # Its payload is at block, the new directory block at block + 1, and
    # block 2 link word points at the new block.
    entry = struct.unpack_from('<12H', disk, (block + 1) * 512)
    assert struct.pack('>5H', *entry[:5]).decode().rstrip() == 'NOSLOT', (emu, entry)
    assert (entry[5], entry[6], entry[7], entry[10]) == (2, block, 1, 4), (emu, entry)
    assert struct.unpack_from('<H', disk, 2 * 512 + 9 * 24 + 12)[0] == block + 1, emu
    assert struct.unpack_from('<H', disk, 12)[0] == block + 2, emu
    print(f'PASS: {emu} saved members persisted; CoW and chain growth accounted')
PY
fi
exit $status
