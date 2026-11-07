# CVIT/Nova Filesystem Specification

## Overview

The CVIT/Nova filesystem is a simple flat filesystem for bring-up, inspired
by the TC08 DECtape format. It is intentionally minimal: no subdirectories,
no fragmentation, no free-space bitmap beyond a next-free-block pointer.

Images are built by `scripts/mk_cvit_nova.py` and converted to SIMH DSK
format by `simh/convert-tc08-to-dsk.py`.

## Physical Block Format

Each physical block is 129 little-endian 16-bit words on disk.

| Words | Description |
|-------|-------------|
| 0–127 | Filesystem payload (128 words) |
| 128   | Unused (TC08 block mark area, not used by CVIT) |

**Constants:**
- `WORDS_PER_BLOCK = 129` (physical)
- `DATA_WORDS_PER_BLOCK = 128` (payload)

On SIMH DSK, each TC08 block maps to one 256-word DSK sector
(sector = drive * 1024 + block). Only the first 128 words contain
filesystem data; the remaining 128 words are ignored.

**Note:** A DSK transfer needs 256 words of buffer headroom even though
only 128 words are payload. The kernel loader writes 128 words of zero
padding after loading an image to satisfy this.

## Volume Layout

| Block | Contents |
|-------|----------|
| 0     | Volume header |
| 1     | Directory (flat, single block) |
| 2+    | File payload data |

## Volume Header (Block 0)

128 words. All values are 16-bit.

| Offset | Contents |
|--------|----------|
| 0      | Magic: `CV` (`(ord("C") << 8) | ord("V")`) |
| 1      | Magic: `NV` (`(ord("N") << 8) | ord("V")`) |
| 2      | Format version (currently 1) |
| 3      | Directory start block (currently 1) |
| 4      | Directory block count (currently 1) |
| 5      | First payload block (currently 2) |
| 6      | Next free block |
| 7–127  | Reserved (zero) |

## Directory (Block 1)

A flat array of 12-word entries. Maximum entries per block:
`DIR_ENTRIES = 128 / 12 = 10` (integer division).

Currently only a single directory block is supported.

### Directory Entry Format (12 words)

| Offset (decimal) | Offset (octal) | Contents |
|------------------|----------------|----------|
| 0–4              | 0–4            | File name, 10 chars packed as 5 words (2 chars/word, big-endian within word: `(c1 << 8) | c2`). Uppercase, space-padded. |
| 5                | 5              | File type: 1=TXT, 2=BIN, 3=SYS |
| 6                | 6              | Start block (first payload block) |
| 7                | 7              | Block count |
| 8                | 10             | Load address (Nova memory address where file should be loaded) |
| 9                | 11             | Entry address (where to jump after loading) |
| 10               | 12             | Length in words (see below) |
| 11               | 13             | Reserved (zero) |

**IMPORTANT:** Assembly language numbers default to octal. When accessing
the length field from assembly, use octal offset `12`, not decimal `10`.
(The octal-10/decimal-10 confusion caused the TYPE truncation bug of
2026-11-01.)

### Length Semantics

The length field (offset 10 decimal / 12 octal) contains:
- For `TYPE_TXT` (1): byte count (each byte stored as one 16-bit word)
- For `TYPE_BIN` (2) and `TYPE_SYS` (3): word count

### File Types

| Value | Name | Description |
|-------|------|-------------|
| 1     | `TYPE_TXT` | Text file. Stored as one byte per 16-bit word. Suffixes: `.txt`, `.text`, `.md`. |
| 2     | `TYPE_BIN` | Binary file. Stored as little-endian 16-bit words. |
| 3     | `TYPE_SYS` | Executable/system file. Stored as little-endian 16-bit words; `RUN` loads it at the directory load address and jumps to the entry address. Suffixes: `.sys`, `.abs`. |

### Default Addresses

If not specified on the `mk_cvit_nova.py` command line:
- `COMMAND` member: load address `0o3000`
- All other members: load address `0o0200` (override for executable members as needed)
- Entry address defaults to load address if not specified.

Specify explicit addresses as `NAME=path@load,entry` (octal by default,
`#` prefix for decimal, `0x`/`0o`/`0b` for explicit base).

## Name Encoding

Member names are 1–10 characters, uppercased, space-padded to 10.
Packed as 5 words, 2 characters per word, big-endian within the word:
`word[i] = (ord(name[2*i]) << 8) | ord(name[2*i+1])`.

## Kernel Memory Map (relevant to filesystem)

| Address | Description |
|---------|-------------|
| `0o1000` | Kernel base |
| `0o2000` | `DIRBUF`: kernel directory buffer (256 words) |
| `0o3000` | `COMMAND` load address (from directory) |
| `0o7600` | Scratch block buffer area |

The `COMMAND` program uses its own `DIRP` pointer (initialized to `0o7600`)
as a block buffer for directory and file data. Note: the directory is
read into this buffer, then file blocks overwrite it — the directory
must be re-read if needed after file I/O.

## COMMAND Binary Format

The `COMMAND` member is a flat word image:
```
[n1][n1 page-zero words][code...]
```
- `n1`: count of page-zero words to relocate
- The entry address (from directory) points to `load + 1 + n1`, the
  prologue that copies page-zero words to `0o0050` before running.

`scripts/abs2bin.py` converts the assembler output to this format,
rebasing page-zero pointer values by the code offset. `scripts/abs2flat.py`
flattens one contiguous absolute-image region for a raw `TYPE_SYS` member.
`RUN` currently loads a SYS member's 128-word payload blocks at the directory
load address and jumps to its entry address; it does not save CPU state or
return to COMMAND after the program finishes. The `calendar` test member is
assembled at `0o2000` and uses that as both load and entry address:

```sh
dotnet Snova.dll abs sd/calendar.asm /tmp/calendar.abs --format simh-load
python3 scripts/abs2flat.py /tmp/calendar.abs /tmp/calendar.sys 0o2000
# Include CALENDAR=/tmp/calendar.sys@0o2000,0o2000 when building the image.
```

`scripts/test-cvit-simh.sh` builds the image and exercises `RUN CALENDAR` on
SIMH; the same image also runs in Dusky.

## References

- `scripts/mk_cvit_nova.py`: image builder (authoritative definition)
- `simh/convert-tc08-to-dsk.py`: TC08 to DSK conversion
- `scripts/abs2bin.py`: assembler output to loadable binary
- `docs/cvit-nova.md`: kernel and boot documentation
