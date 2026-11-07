#!/usr/bin/env python3
"""Flatten one contiguous SIMH-load absolute-image region into little-endian words."""
import struct
import sys


def main() -> None:
    if len(sys.argv) != 4:
        raise SystemExit("usage: abs2flat.py input.abs output.bin start-address")
    source, destination, address_text = sys.argv[1:]
    start = int(address_text, 0) if address_text.lower().startswith("0x") else int(address_text, 8)
    data = open(source, "rb").read()
    pos = 0
    while pos < len(data) and data[pos] == 0:
        pos += 1
    words: dict[int, int] = {}
    while pos + 6 <= len(data):
        count, address, _checksum = struct.unpack_from("<HHH", data, pos)
        pos += 6
        if count == 1:
            break
        length = (-count) & 0xFFFF
        block = struct.unpack_from("<" + "H" * length, data, pos)
        pos += 2 * length
        for offset, word in enumerate(block):
            words[address + offset] = word
    if start not in words:
        raise SystemExit(f"error: no words at start address {start:o}")
    end = max(words) + 1
    missing = next((addr for addr in range(start, end) if addr not in words), None)
    if missing is not None:
        raise SystemExit(f"error: image is not contiguous at {missing:o}")
    with open(destination, "wb") as output:
        output.write(struct.pack("<" + "H" * (end - start), *(words[a] for a in range(start, end))))
    print(f"wrote {end - start} words from {start:o} to {end:o} in {destination}")


if __name__ == "__main__":
    main()
