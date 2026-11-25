# CVIT/Nova Filesystem Specification

Status: SIGNED OFF by Randall Bohn, 2026-11-25 (reconciled 2026-11-25 against
the shipped code in playa:~/build/dusky-petrel at 7534845 "solid space").
This draft supersedes the 2026-11-02 read-only draft. Changes from that
draft are listed under "Reconciliation notes" at the end.

## Overview

The CVIT/Nova filesystem is a simple flat filesystem, inspired by the
TC08 DECtape format. It is intentionally minimal: no subdirectories,
no fragmentation, no free-space bitmap. Free space is managed
append-only by advancing a next-free-block pointer (the volume
high-water mark) in the volume header.

Version 2 of the format adds a chained directory and runtime write
support. Version 1 images are not supported; rebuild them with the
current builder.

Images are built by `scripts/mk_cvit_nova.py` and converted to SIMH DSK
format by `simh/convert-tc08-to-dsk.py`. A bootable image is produced
only by `scripts/build-image.sh`, which installs the bootstrap, kernel,
and extension into the reserved sectors after conversion.

V1 scope: a single drive, the boot volume, addressed as `SYS:`. The
kernel's sector addressing (`sector = drive * 1024 + block`) and the
drive field in filesystem control blocks can name drive 1, but no
command is verified against a second image and a second drive is not
a v1 promise.

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
only 128 words are payload. Filesystem I/O uses the bounce buffer at
`0o77000`–`0o77377` (see Kernel Memory Map).

## Volume Layout

| Block | Contents |
|-------|----------|
| 0     | Volume header (second half of sector 0 holds the bootstrap) |
| 1     | First directory block |
| 2 …   | Further directory blocks, if the builder created a chain |
| 1 + directory count | First payload block |
| … up to 1014 | File payload data, allocated append-only |
| 1015–1020 | Reserved: kernel extension (loaded at `0o65000`–`0o67777`) |
| 1021–1023 | Reserved: kernel (loaded at `0o1000`–`0o2377`) |

The image builder rejects filesystems that overlap sectors 1015–1023.
The header's next-free-block value describes filesystem data only; the
allocator must never allocate at or beyond sector 1015.

## Volume Header (Block 0)

128 words. All values are 16-bit.

| Offset | Contents |
|--------|----------|
| 0      | Magic: `CV` (`(ord("C") << 8) | ord("V")`) |
| 1      | Magic: `NV` (`(ord("N") << 8) | ord("V")`) |
| 2      | Format version (2, chained directory) |
| 3      | Directory start block (1) |
| 4      | Directory block count (number of blocks the builder created; the runtime chain may grow beyond this — see Directory) |
| 5      | First payload block (`1 + directory block count` at build time) |
| 6      | Next free block (allocation high-water mark) |
| 7–127  | Reserved (zero) |

Allocation rewrites the header's full 256-word sector, so the
bootstrap in sector 0's second half is preserved.

## Directory

The directory is a chain of blocks. Each block holds **9 file
entries** followed by one **link entry**:

- `DIR_ENTRY_WORDS = 12`
- `DIR_ENTRIES = 128 / 12 - 1 = 9` file entries per block
- The link entry starts at word offset 108 (decimal).
- **Link word 6** (offset 114 decimal) is the next directory block
  number, or 0 at the end of the chain. All other link words are zero.

Directory links must point to blocks 1 through 1014. Readers must
validate the chain rather than loop forever: enumeration tracks
visited blocks in a caller-owned bitmap and rejects a block that
would be visited twice (a cycle) or is out of range. The builder
creates chains whose links are strictly increasing; the runtime
growth path appends exactly one new block at the end of the chain
(see Publication and growth).

Header word 4 records how many directory blocks the builder created.
The authoritative chain at runtime is the link chain itself, followed
from the directory start block.

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
| 11               | 13             | Reserved, except: bit 15 set marks a **tombstone** (see below) |

**IMPORTANT:** Assembly language numbers default to octal. When accessing
the length field from assembly, use octal offset `12`, not decimal `10`.
(The octal-10/decimal-10 confusion caused the TYPE truncation bug of
2026-11-01.)

### Empty entries and tombstones

- An entry whose first name word is zero is **unused**.
- An entry with **bit 15 of word 11 set** is a **tombstone**: a deleted
  member. The name, extent, and other metadata are retained for
  recovery.
- Enumeration and lookup skip both unused entries and tombstones.
- A tombstoned name may be re-saved, and a tombstoned (or unused) slot
  may be reused by publication.

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
The member names used on a shipped volume use A–Z, 0–9, `.`, `-`, `_`.
Packed as 5 words, 2 characters per word, big-endian within the word:
`word[i] = (ord(name[2*i]) << 8) | ord(name[2*i+1])`.

## Allocation and Writing

Allocation is append-only. There is no free list and no reuse of
payload extents in v1; space leaked by an interrupted write is not
reclaimed at runtime.

The write sequence for a new member is, in order:

1. **Reserve** — advance the header next-free pointer past the new
   extent (selector 8, or the direct FSALLOC vector below). The header
   write is the reservation: once it succeeds, the extent is allocated
   even if a later step fails.
2. **Write data** — write the payload blocks into the reserved extent
   (selector 9).
3. **Publish last** — write the directory entry (selector 10) only
   after the payload is complete. The directory entry is the commit
   point: a member exists exactly when a live entry names it.

### Filesystem selectors

Filesystem operations are selectors 6–12 through the kernel syscall
vector at `0o1002` (AC0 = selector on entry and status on return,
AC1 = control block pointer). The full control-block layouts and
buffer rules are the contract in `docs/cvit-filesystem-api-draft.md`;
the summary here is normative for behaviour.

| Selector | Operation | Statuses |
|----------|-----------|----------|
| 6 | Enumerate directory entries (skips unused and tombstones) | 0 entry, 1 end, 2 disk error, 3 invalid volume/directory |
| 7 | Look up a member by name (first live match) | 0 found, 1 not found, 2 disk error, 3 invalid volume/directory |
| 8 | Reserve a contiguous extent by advancing next-free | 0 ok, 2 I/O error, 3 invalid, 4 does not fit before sector 1015 |
| 9 | Write a reserved extent (128 payload words/sector, zero-padded) | 0 ok, 2 I/O error, 3 invalid or crossing into reserved sectors |
| 10 | Publish a new directory entry | 0 ok, 1 duplicate live name, 2 I/O error, 3 invalid, 4 directory full and cannot grow |
| 11 | Preflight publication (same checks as 10, writes nothing, reserves nothing) | same as 10 |
| 12 | Replace: switch a live entry to a newly written extent | 0 switched, 1 no live member with that name, 2 I/O error, 3 invalid |

Selectors 10 and 11 reject a duplicate live name **anywhere in the
chain** before selecting a slot. Slot selection takes the first unused
or tombstoned slot in chain order.

### Publication and growth

If the last linked directory block has no free slot, selector 10
**grows the chain by one block**:

1. Reserve one sector through the kernel direct FSALLOC vector
   (`CV_ALLOC` at `0o1011`; the syscall dispatcher is not reentrant,
   so resident services must not call back through it).
2. Format the new block (all entries unused, link word 0).
3. Link it from the old last block.
4. Publish the entry into its first slot.

Format-before-link means a crash mid-growth never leaves a linked,
unformatted block. Selector 11 performs the same decision without
reserving: it succeeds in the growth case only if one more sector
would fit under the allocator end limit. Status 4 from selectors
10/11 therefore means: the chain is full **and** the volume has no
sector left to grow with.

### Replace (copy-on-write re-save)

FOCAL's `.save` preflights with selector 11. If the name is already
live, `.save` reserves and writes a new extent (selectors 8 and 9)
and then calls selector 12, which switches the live directory entry
to the new extent. The old version survives until the switch; a crash
before the switch leaves the old version valid and leaks the new
extent. If the entry vanished between preflight and replace, `.save`
falls back to publication (selector 10).

### FSALLOC

`FSALLOC`, the allocator behind selector 8 and the `CV_ALLOC` direct
vector (`0o1011`), lives at `0o2202` — above DIRBUF, inside the
3-sector kernel span (`0o1000`–`0o2377`). Control block:
`[drive, count, returned start]`. Statuses: 0 success, 2 I/O error,
3 invalid control block/header, 4 no space before sector 1015.
A failed header write may nevertheless have reached the disk; callers
must not assume the extent is free or reclaim it after an error.

## Kernel Memory Map (relevant to filesystem)

| Address | Description |
|---------|-------------|
| `0o1000` | Kernel base; jump table `0o1000`–`0o1011` (cold, warm, syscall, quit, read/write block, getc/putc/puts, `CV_ALLOC` at `0o1011`) |
| `0o2000` | `DIRBUF`: kernel directory buffer (256 words). Lookup's private cursor uses `0o2040`–`0o2157` inside this workspace; callers must not overlap it. |
| `0o2202` | `FSALLOC` (see above) |
| `0o3000` | `COMMAND` load address (from directory) |
| `0o65000`–`0o67777` | Resident kernel extension (selectors 6–12). RUN programs must preserve this region. |
| `0o77000`–`0o77377` | DSK bounce buffer (256 words) for filesystem I/O |

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

`RUN` loads a SYS member's 128-word payload blocks at the directory
load address and jumps to its entry address. **A RUN program returns
to COMMAND by jumping to the warm-start vector at `0o1001`; the kernel
reloads COMMAND from disk**, since the program may have overwritten
COMMAND's memory and page-zero cells. (This corrects the 2026-11-02
draft, which said RUN does not return.)

The `calendar` test member is assembled at `0o2000` and uses that as
both load and entry address:

```sh
dotnet Snova.dll abs sd/calendar.asm /tmp/calendar.abs --format simh-load
python3 scripts/abs2flat.py /tmp/calendar.abs /tmp/calendar.sys 0o2000
# Include CALENDAR=/tmp/calendar.sys@0o2000,0o2000 when building the image.
```

`scripts/test-cvit-simh.sh` builds the image and exercises `RUN CALENDAR` on
SIMH; the same image also runs in Dusky.

## References

- `scripts/mk_cvit_nova.py`: image builder (authoritative for the built format)
- `scripts/build-image.sh`: bootable image build (bootstrap, kernel, extension)
- `scripts/install-dsk-boot.py`: installs reserved-sector payloads into the DSK image
- `simh/convert-tc08-to-dsk.py`: TC08 to DSK conversion
- `scripts/abs2bin.py`: assembler output to loadable binary
- `sd/cvit-extension.asm`: resident extension (selectors 6–12)
- `simh/cvit-kernel-simh.asm` / `sd/cvit-kernel.asm`: kernel, FSALLOC, jump table
- `docs/cvit-filesystem-api-draft.md`: selector control-block contract
- `docs/cvit-nova.md`: kernel and boot documentation

## Reconciliation notes (2026-11-25, vs the 2026-11-02 draft)

1. Format version 1 → **2**; single directory block → **chained
   directory**, 9 entries + link entry per block (was: 10 entries,
   single block).
2. Volume header words 4–5 are now variable (directory count, first
   payload = 1 + count), not fixed at 1 and 2.
3. Reserved sectors specified in full: 1015–1020 extension,
   1021–1023 kernel, data ceiling 1014, bootstrap in sector 0's
   second half.
4. Word 11 of a directory entry is no longer simply "reserved":
   bit 15 is the tombstone mark. Empty-entry and tombstone skip
   semantics added.
5. Write support specified: append-only allocation, the
   reserve → write → publish-last order, selectors 6–12, duplicate
   rejection, chain growth (format-before-link), and selector-12
   replace (copy-on-write re-save).
6. FSALLOC documented at its as-built address `0o2202`, with the
   `CV_ALLOC` direct vector at `0o1011`.
7. Kernel memory map updated: DIRBUF lookup cursor range, extension
   at `0o65000`–`0o67777`, bounce buffer at `0o77000`–`0o77377`
   (replacing the draft's `0o7600` scratch description).
8. RUN semantics corrected: RUN programs **do** return to COMMAND,
   via the warm-start vector at `0o1001` and a COMMAND reload.

## Sign-off

Signed off by Randall Bohn: x  Date: 2026-11-25
