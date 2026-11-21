# CVIT filesystem API draft

This is a proposed implementation contract, not an implemented API.

## Directory format

The volume header word 2 must be 2. Version 2 has a chain of directory
blocks; each block has nine file entries followed by a link entry. The next
block number is link word 6; zero ends the chain. Other link words are zero.
All entry offsets here are decimal. A file entry occupies 12 words. Version 1
is not supported; rebuild old images with the current builder.

For version 2, propose marking a tombstone by setting bit 15 of entry word
11, retaining the name, extent and other metadata for recovery. Live entries
have that bit clear. A zero first name word is unused. Enumeration skips both
unused entries and tombstones.

The bootable DSK volume reserves blocks 1018 through 1023. Directory links
must point to blocks 1 through 1017. Implementations must reject invalid or
cyclic chains rather than looping forever. Block zero is the volume header,
not a directory block.

## Read-only operations

Propose adding selectors 6 (enumerate) and 7 (lookup) to the existing kernel
syscall vector at 0o1002. AC1 points to a caller-owned control block. AC0
returns 0 for success, 1 for end/not found, 2 for disk error, or 3 for an
invalid volume or directory. Other registers are clobbered.

Enumeration control block, word offsets:

| Offset | Meaning |
| --- | --- |
| 0 | Drive (0 or 1) |
| 1 | Cursor block; set to 0 to start |
| 2 | Cursor entry index; set to 0 to start |
| 3 | Pointer to caller-owned 12-word output entry |
| 4–67 | 64-word visited-block bitmap, initialized by the kernel on start |

On start, block and entry index must both be zero. The kernel clears the
bitmap, reads the volume header, and records the first directory block. For
block `b`, bitmap word `4 + (b / 16)` uses bit `b % 16`. Before following a
nonzero link, validate the block number, reject it if its bit is already set,
and otherwise set its bit. This rejects a cycle before revisiting a block.
Each cursor owns its bitmap, so enumeration calls on distinct cursors may be
interleaved. A single invocation is non-reentrant because it uses shared
kernel scratch storage.

On success the kernel copies one live entry to the output and advances the
cursor. On end or error, output is unspecified. Callers must preserve the
cursor block, entry index, and bitmap between calls; set block and entry index
to zero to restart. The output area must not overlap the control block or
kernel workspace.

Lookup control block:

| Offset | Meaning |
| --- | --- |
| 0 | Drive (0 or 1) |
| 1 | Pointer to five packed, uppercase, space-padded name words |
| 2 | Pointer to caller-owned 12-word output entry |

Lookup returns the first matching live entry and leaves output unspecified on
failure. Both operations read through the kernel sector I/O interface and
must not overwrite caller buffers, the resident extension, or a running
program. Shared sector buffers imply a non-reentrant implementation unless
explicitly protected.

## Required validation before adoption

The cursor layout and syscall selectors above have not been implemented or
validated. Test both disk-boot and host-assisted execution on Dusky and SIMH,
including unsupported versions, multi-block version 2 directories, skipped
tombstones and empty entries, missing names, I/O errors, invalid links and
cycles. Update the boot loader and COMMAND only after the API passes these
tests. Write allocation and crash-safe replacement require a separate design.
