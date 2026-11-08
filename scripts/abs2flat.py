#!/usr/bin/env python3
"""Flatten one contiguous SIMH-load absolute-image region into little-endian words.

usage: abs2flat.py [--pz] input.abs output.bin start-address

With --pz, words assembled below 0o400 (the member's page-zero cells) are
removed from the code region and appended after it as

    [pz-start][pz-count][pz-words...]

The member places a label (conventionally PZIMG) at the very end of its
source so its startup code can copy that block back to page zero.  The
page-zero words must be contiguous.  See sd/focal.asm.
"""
import struct
import sys

PZ_LIMIT = 0o400


def parse_abs(source: str) -> dict[int, int]:
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
    return words


def contiguous(words: dict[int, int], start: int, what: str) -> list[int]:
    end = max(words) + 1
    missing = next((addr for addr in range(start, end) if addr not in words), None)
    if missing is not None:
        raise SystemExit(f"error: {what} is not contiguous at {missing:o}")
    return [words[a] for a in range(start, end)]


def main() -> None:
    args = sys.argv[1:]
    with_pz = False
    if args and args[0] == "--pz":
        with_pz = True
        args = args[1:]
    if len(args) != 3:
        raise SystemExit("usage: abs2flat.py [--pz] input.abs output.bin start-address")
    source, destination, address_text = args
    start = int(address_text, 0) if address_text.lower().startswith("0x") else int(address_text, 8)
    words = parse_abs(source)
    pz = {a: w for a, w in words.items() if a < PZ_LIMIT}
    code = {a: w for a, w in words.items() if a >= PZ_LIMIT}
    if pz and not with_pz:
        raise SystemExit(f"error: image has page-zero words at {min(pz):o}; use --pz")
    if start not in code:
        raise SystemExit(f"error: no words at start address {start:o}")
    if min(code) < start:
        raise SystemExit(f"error: words below start address at {min(code):o}")
    image = contiguous(code, start, "image")
    end = start + len(image)
    if with_pz:
        if not pz:
            raise SystemExit("error: --pz given but image has no page-zero words")
        pzstart = min(pz)
        pzwords = contiguous(pz, pzstart, "page-zero region")
        image += [pzstart, len(pzwords)] + pzwords
        print(f"page zero: {len(pzwords)} words from {pzstart:o}, image at {end:o}")
    with open(destination, "wb") as output:
        output.write(struct.pack("<" + "H" * len(image), *image))
    print(f"wrote {len(image)} words from {start:o} to {start + len(image):o} in {destination}")


if __name__ == "__main__":
    main()
