#!/usr/bin/env python3
"""Create a SIMH DSK image to test the Nova DSK bootstrap, not CVIT itself."""

import argparse
import struct
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("output", type=Path, help="output DSK image (will be overwritten)")
args = parser.parse_args()

# One 1024-sector platter, 256 little-endian words per sector.
image = bytearray(1024 * 256 * 2)

def word(offset: int, value: int) -> None:
    struct.pack_into("<H", image, offset * 2, value)

# Empty CVIT volume header and directory, matching cvit-filesystem.md.
for offset, value in enumerate((0x4356, 0x4E56, 1, 1, 1, 2, 2)):
    word(offset, value)

# BOOT DSK loads sector 0 at 0 and spins at 0o377 until it is overwritten.
# The second half of the sector is normally zero in a converted CVIT image.
word(0o200, 0o63077)  # HALT: the simulator should stop with PC 0o201.
word(0o377, 0o000200)  # JMP 0o200
args.output.write_bytes(image)
print(f"Wrote {args.output} ({len(image)} bytes); expected HALT at 0o200, PC 0o201")
