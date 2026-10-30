#!/usr/bin/env python3
"""Convert a dusky TC08 image to a SIMH DSK image, one block per sector.

TC08: 129 little-endian 16-bit words per block (128 payload + 1 spare).
DSK:  256 little-endian 16-bit words per sector, 1024 sectors per disk.
Block N -> sector N, first 128 words = payload, second half zero.
Usage: convert-tc08-to-dsk.py in.img out.img
"""
import struct, sys
TC08_WORDS = 129
PAYLOAD = 128
SECTOR_WORDS = 256
with open(sys.argv[1], "rb") as f:
    data = f.read()
assert len(data) % (TC08_WORDS * 2) == 0, "not a whole number of TC08 blocks"
blocks = len(data) // (TC08_WORDS * 2)
sectors = max(blocks, 1024)  # at least one full DSK disk
out = bytearray(sectors * SECTOR_WORDS * 2)
for n in range(blocks):
    words = struct.unpack_from("<129H", data, n * TC08_WORDS * 2)
    struct.pack_into("<128H", out, n * SECTOR_WORDS * 2, *words[:PAYLOAD])
with open(sys.argv[2], "wb") as f:
    f.write(out)
print(f"converted {blocks} TC08 blocks -> {sectors} DSK sectors in {sys.argv[2]}")
