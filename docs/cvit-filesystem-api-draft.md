# CVIT filesystem API draft

The contract below is not yet implemented in full. A vertical slice of
selector 6 exists: it scans linked version 2 directory blocks using
control-block words 0 (drive), 1 (block), 2 (index), and 3 (output
pointer). It skips empty and tombstoned entries and returns 0 (entry), 1
(end), 2 (disk error), or 3 (invalid header, out-of-range link, or
cycle). On initialization it checks the volume signature, version, and root
block and clears the caller-owned bitmap. Directory blocks are marked in that
bitmap before being visited. End and error states are terminal until the
caller resets the cursor. Selector 7 performs name lookup using a private
cursor and propagates enumeration errors. Caller buffer overlap is not yet
validated, so callers must obey the buffer restrictions below.
`scripts/test-cvit-enum-slice.sh` exercises enumeration and lookup on both
emulators, including chained directories, missing and tombstoned members,
invalid versions, and cycles.

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

Both DSK volumes reserve blocks 1015 through 1023. Directory links must
point to blocks 1 through 1014. Implementations must reject invalid or cyclic
chains rather than looping forever. Block zero is the volume header, not a
directory block.

## Read-only operations

Selectors 6 (enumerate) and 7 (lookup) are available through the existing
kernel syscall vector at 0o1002. AC1 points to a caller-owned control block. AC0
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
cursor. On end, the kernel sets cursor block to 0o177777; further calls return
end without I/O. On error, it sets cursor block to 0o177776; further calls
return invalid-directory status without I/O. The original call returns the
specific disk or invalid-directory error. On end or error, output is
unspecified. Callers must preserve the cursor block, entry index, and bitmap
between calls; set block and entry index to zero to restart. The output area
must not overlap the control block or kernel workspace.

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

## Contiguous block reservation

Selector 8 reserves blocks by advancing the version 2 volume header's
high-water mark. AC1 points to three words: drive (0 or 1), requested block
count, and an output start block. AC0 returns 0 on success, 2 for an I/O
error, 3 for an invalid drive, zero count, or invalid header, and 4 if the
request does not fit before reserved block 1015. The output word is written
only on success. The header's full 256-word sector is read and written so
that the bootstrap in its second half is preserved. The operation uses the
shared extension buffer and is non-reentrant.

A failed header write may nevertheless have reached the disk. The caller must
not assume the extent was free or reclaim it after an error; an interrupted
operation may leak space. This service reserves space only: it does not write
file payloads, create directory entries, tombstone old entries, or validate
that pre-existing extents agree with the high-water mark. Use it only on a
valid volume. `scripts/test-cvit-alloc.sh` tests persistence, disk-full
handling, invalid headers and bootstrap preservation on both emulators.

## Writing a reserved extent

Selector 9 accepts a four-word control block: drive, starting block, source
address, and length in words. It writes `max(1, ceil(length / 128))` sectors,
using 128 payload words per sector. It zero-pads the last payload and the
unused second half of every physical sector. A zero-length write writes one
zeroed sector. AC0 returns 0 on success, 2 on I/O error, or 3 for invalid
arguments or a range crossing into reserved sectors. Source data must end at
or below `0o65000`, and must not overlap kernel-owned memory; the latter is a
caller obligation, not a runtime check.

The caller must supply an extent exclusively reserved for this write: this
low-level service **does not verify ownership** and can overwrite live file
data if given its blocks. A write error can leave an extent partially written;
the reservation remains allocated. This operation is non-reentrant and uses
the shared sector buffer. `scripts/test-cvit-write-extent.sh` checks padding,
zero length, invalid source addresses, and disk boundaries on both emulators.

Lookup's private cursor now uses `0o2040–0o2157` within the kernel's existing
DIRBUF workspace. Callers must not overlap that workspace when invoking it.

## Directory entry publication

Selectors 10 (publish) and 11 (preflight) take AC1 = `[drive, entry_pointer]`,
where the entry has 12 words. Status is 0 success, 1 duplicate live name,
2 I/O error, 3 invalid drive/volume/entry, or 4 directory full. Both reject
a duplicate live name anywhere in the linked directory. If the name is
absent, they validate the chain before selecting the first unused or
tombstoned slot. They do not add directory blocks.

Selector 11 checks the name, type, live flag, and availability of a slot;
it does not reserve space or write anything. The caller can preflight,
reserve and write its payload, then pass the complete entry to selector 10.
Selector 10 checks again and publishes the directory entry. It does not
verify ownership or completeness of the payload; that is the caller's
responsibility. A write failure after allocation may leak reserved blocks.
Replacing an existing live name is not supported.

## Required validation before adoption

Additional tests are needed for interleaved cursors, I/O errors, malformed
links, buffer bounds, and execution through disk boot and host-assisted modes.
The boot loader and COMMAND use the read-only API. FOCAL uses the write
API for create-only saves. Directory growth and crash-safe replacement
require further implementation.
