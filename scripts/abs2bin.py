#!/usr/bin/env python3
"""Convert a dusky simh-load .abs file to a flat word image for the CVIT filesystem.

Output layout (little-endian 16-bit words):
    [n1][n1 page-zero words][code words...]

n1 is the number of words assembled below 0o1000 (the member's page-zero
image, e.g. COMMAND's 0o0050 cells).  The kernel loads the member flat at
its directory load address; the member's entry prologue copies the n1
page-zero words to 0o0050 before use.  See docs/cvit-nova.md.

Page-zero pointer cells that reference the member's own code (assembled at
CODE_START, typically 0o3000) are rebased by +(1+n1) to account for the
[n1] prefix shifting the code.  Pointers outside the code region (kernel
vectors at 0o1000, data values) are left alone.  This assumes the directory
load address equals CODE_START; use --load to override.

Usage: abs2bin.py [--load 0o3000] in.abs out.bin
"""

import struct
import sys


CODE_START = 0o3000


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
    args = sys.argv[1:]
    load = CODE_START
    if args and args[0] == "--load":
        load = int(args.pop(1), 8)
        args.pop(0)
    if len(args) != 2:
        sys.exit("usage: abs2bin.py [--load 0o3000] in.abs out.bin")
    src, dst = args
    blocks = parse_abs(src)
    if not blocks:
        sys.exit("error: no data blocks in " + src)
    pz = [(a, w) for a, w in blocks if a < 0o1000]
    code = [(a, w) for a, w in blocks if a >= 0o1000]
    if not pz or not code:
        sys.exit("error: expected both page-zero and code regions")
    pzwords = flat_region(pz, 0o0050, "page-zero")
    codewords = flat_region(code, CODE_START, "code")
    n1 = len(pzwords)
    # Rebase page-zero pointers that target the member's own code.
    # In the .abs, code lives at [CODE_START, CODE_START+len).  In the
    # flat image loaded at `load`, code sits at [load+1+n1, ...).
    # Shift matching pointers by the difference.
    code_end = CODE_START + len(codewords)
    shift = (load + 1 + n1) - CODE_START
    rebased = 0
    for i, w in enumerate(pzwords):
        if CODE_START <= w < code_end:
            pzwords[i] = (w + shift) & 0xFFFF
            rebased += 1
    img = [n1] + pzwords + codewords
    with open(dst, "wb") as f:
        f.write(struct.pack("<" + "H" * len(img), *[w & 0xFFFF for w in img]))
    print(f"wrote {dst}: n1={n1} page-zero words, {len(codewords)} code words, {rebased} pointers rebased by +{shift:o}")


if __name__ == "__main__":
    main()
