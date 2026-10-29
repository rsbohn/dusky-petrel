#!/usr/bin/env python3
"""Build a tiny cvit/Nova TC08 image.

Usage:
  scripts/mk_cvit_nova.py out.img NAME=path[@load[,entry]] [NAME=path ...]

This is intentionally simple for bring-up:
- block 0 is a volume header
- block 1 is a flat directory
- payload data starts at block 2
- each physical TC08 block is 129 little-endian 16-bit words
- only the first 128 words of each block are cvit/Nova payload
"""

from __future__ import annotations

import argparse
import math
import os
import struct
from pathlib import Path

WORDS_PER_BLOCK = 129
DATA_WORDS_PER_BLOCK = 128
DIR_ENTRY_WORDS = 12
DIR_ENTRIES = DATA_WORDS_PER_BLOCK // DIR_ENTRY_WORDS

TYPE_TXT = 1
TYPE_BIN = 2
TYPE_SYS = 3


def pack_name(name: str) -> list[int]:
    clean = name.upper().strip()
    if not clean or len(clean) > 10:
        raise ValueError(f"member name must be 1..10 chars: {name!r}")
    clean = clean.ljust(10)
    words: list[int] = []
    for i in range(0, 10, 2):
        words.append((ord(clean[i]) << 8) | ord(clean[i + 1]))
    return words


def read_member_words(path: Path) -> tuple[int, list[int]]:
    data = path.read_bytes()
    if path.suffix.lower() in {".txt", ".text"}:
        return TYPE_TXT, [b for b in data]

    if len(data) % 2:
        data += b"\0"
    words = [struct.unpack_from("<H", data, i)[0] for i in range(0, len(data), 2)]
    typ = TYPE_SYS if path.suffix.lower() in {".sys", ".abs"} else TYPE_BIN
    return typ, words


def write_block(f, words: list[int]) -> None:
    padded = (words + [0] * WORDS_PER_BLOCK)[:WORDS_PER_BLOCK]
    f.write(struct.pack("<" + "H" * WORDS_PER_BLOCK, *[w & 0xFFFF for w in padded]))


def parse_address(text: str) -> int:
    text = text.strip()
    if text.startswith("#"):
        return int(text[1:], 10)
    if text.lower().startswith(("0x", "0o", "0b")):
        return int(text, 0)
    return int(text, 8)


def parse_member(spec: str) -> tuple[str, Path, int | None, int | None]:
    if "=" not in spec:
        raise ValueError(f"member spec must be NAME=path[@load[,entry]]: {spec}")
    name, path_text = spec.split("=", 1)
    load: int | None = None
    entry: int | None = None
    if "@" in path_text:
        path_text, meta = path_text.rsplit("@", 1)
        parts = [p for p in meta.split(",") if p]
        if len(parts) > 2:
            raise ValueError(f"member metadata must be @load[,entry]: {spec}")
        if parts:
            load = parse_address(parts[0])
            entry = parse_address(parts[1]) if len(parts) > 1 else load
    return name, Path(path_text), load, entry


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("output", type=Path)
    ap.add_argument("members", nargs="*")
    args = ap.parse_args()

    members = [parse_member(s) for s in args.members]
    if len(members) > DIR_ENTRIES:
        raise SystemExit(f"too many members for first directory block; max {DIR_ENTRIES}")

    directory = [0] * DATA_WORDS_PER_BLOCK
    payload_blocks: list[list[int]] = []
    next_block = 2

    for index, (name, path, load, entry) in enumerate(members):
        typ, words = read_member_words(path)
        default_addr = 0o3000 if name.upper() == "COMMAND" else 0o0200
        load_addr = default_addr if load is None else load
        entry_addr = load_addr if entry is None else entry
        block_count = max(1, math.ceil(len(words) / DATA_WORDS_PER_BLOCK))
        start_block = next_block
        next_block += block_count

        for b in range(block_count):
            chunk = words[b * DATA_WORDS_PER_BLOCK : (b + 1) * DATA_WORDS_PER_BLOCK]
            payload_blocks.append(chunk)

        off = index * DIR_ENTRY_WORDS
        directory[off : off + 5] = pack_name(name)
        directory[off + 5] = typ
        directory[off + 6] = start_block
        directory[off + 7] = block_count
        directory[off + 8] = load_addr
        directory[off + 9] = entry_addr
        directory[off + 10] = len(words)
        directory[off + 11] = 0

    header = [0] * DATA_WORDS_PER_BLOCK
    header[0] = (ord("C") << 8) | ord("V")
    header[1] = (ord("N") << 8) | ord("V")
    header[2] = 1          # format version
    header[3] = 1          # directory start block
    header[4] = 1          # directory block count
    header[5] = 2          # first payload block
    header[6] = next_block # next free block

    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("wb") as f:
        write_block(f, header)
        write_block(f, directory)
        for block in payload_blocks:
            write_block(f, block)

    print(f"wrote {args.output} ({next_block} TC08 blocks)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
