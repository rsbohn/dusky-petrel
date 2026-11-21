#!/usr/bin/env python3
"""Install the CVIT Nova bootstrap and kernel in a converted DSK image."""
import argparse
import struct
from pathlib import Path

from abs2flat import parse_abs

SECTOR_WORDS = 256
KERNEL_SECTOR = 1021  # Last three sectors of the first 1024-sector platter.
KERNEL_START = 0o1000
KERNEL_CAPACITY = 3 * SECTOR_WORDS

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("image", type=Path, help="converted DSK image (modified in place)")
parser.add_argument("boot_abs", help="assembled sd/cvit-boot.asm (SIMH load format)")
parser.add_argument("kernel_abs", help="assembled SIMH DSK kernel (SIMH load format)")
args = parser.parse_args()
image = bytearray(args.image.read_bytes())
if len(image) != 1024 * SECTOR_WORDS * 2:
    raise SystemExit("error: expected exactly one 1024-sector DSK platter")
header = struct.unpack_from("<7H", image)
if header[:2] != (0x4356, 0x4e56):
    raise SystemExit("error: not a CVIT/Nova volume")
if header[6] > KERNEL_SECTOR:
    raise SystemExit("error: CVIT filesystem overlaps reserved kernel sectors")
boot = parse_abs(args.boot_abs)
if 0o200 not in boot or 0o377 not in boot or any(a < 0o200 or a > 0o377 for a in boot):
    raise SystemExit("error: bootstrap must fit in sector 0's second half, with entry at 0o377")
kernel = parse_abs(args.kernel_abs)
if KERNEL_START not in kernel or any(a < KERNEL_START or a >= KERNEL_START + KERNEL_CAPACITY for a in kernel):
    raise SystemExit("error: kernel does not fit the three reserved sectors at 0o1000")
for address, value in boot.items():
    struct.pack_into("<H", image, address * 2, value)
# Clear padding so stale contents cannot become kernel data.
start = KERNEL_SECTOR * SECTOR_WORDS * 2
image[start:start + KERNEL_CAPACITY * 2] = bytes(KERNEL_CAPACITY * 2)
for address, value in kernel.items():
    struct.pack_into("<H", image, start + (address - KERNEL_START) * 2, value)
args.image.write_bytes(image)
print(f"installed bootstrap and {len(kernel)} kernel words in {args.image}")
