#!/usr/bin/env python3
"""Convert a dusky simh-load .abs file to a flat word image for the CVIT filesystem.

Output layout (little-endian 16-bit words):
    [n1][n1 page-zero words][code words...]

n1 is the number of words assembled below 0o1000 (the member's page-zero
image, e.g. COMMAND's 0o0050 cells).  The kernel loads the member flat at
its directory load address; the member's entry prologue copies the n1
page-zero words to 0o0050 before use.  See docs/cvit-nova.md.

Usage: abs2bin.py in.abs out.bin
"""

import struct
import sys


def parse_abs(path: str) -> list[tuple[int, list[int]]]:
    data = open(path, "rb").read()
    i = 0
    while i < len(data) and data[i] == 0:
        i += 1  # leader
    blocks = []
    while i + 6 <= len(data):
        count, addr, _cksum = struct.unpack_from("<HHH", data, i)
        i += 6
        if count == 1:
            break  # terminal start block: no data
        n = (-count) & 0xFFFF
        words = list(struct.unpack_from("<" + "H" * n, data, i))
        i += 2 * n
        blocks.append((addr, words))
    return blocks


def flat_region(blocks: list[tuple[int, list[int]]], base: int, name: str) -> list[int]:
    blocks = sorted(blocks)
    out: list[int] = []
    expect = base
    for addr, words in blocks:
        if addr != expect:
            sys.exit(f"error: {name} region not contiguous at {addr:o} (expected {expect:o})")
        out += words
        expect += len(words)
    return out


def main() -> None:
    src, dst = sys.argv[1], sys.argv[2]
    blocks = parse_abs(src)
    if not blocks:
        sys.exit("error: no data blocks in " + src)
    pz = [(a, w) for a, w in blocks if a < 0o1000]
    code = [(a, w) for a, w in blocks if a >= 0o1000]
    if not pz or not code:
        sys.exit("error: expected both page-zero and code regions")
    pzwords = flat_region(pz, 0o0050, "page-zero")
    codewords = flat_region(code, 0o3000, "code")
    img = [len(pzwords)] + pzwords + codewords
    with open(dst, "wb") as f:
        f.write(struct.pack("<" + "H" * len(img), *[w & 0xFFFF for w in img]))
    print(f"wrote {dst}: n1={len(pzwords)} page-zero words, {len(codewords)} code words")


if __name__ == "__main__":
    main()
