# CVIT/Nova evaluation — 1101

## Assessment

CVIT/Nova is a promising, working bring-up project, but is still a prototype rather than a dependable small operating system. It has crossed several important boundaries: the kernel boots, loads `COMMAND` from a filesystem image, and exposes console and disk services through a jump table.

## Strengths

- **Coherent vertical slice:** Boot, filesystem image creation, command loading, and interactive commands work together rather than existing only as isolated emulator demonstrations.
- **Independent compatibility target:** Running the same disk image on Dusky and SIMH gives the project a valuable second implementation against which to check assumptions.
- **Useful separation:** `COMMAND` calls kernel services instead of duplicating device drivers. The image-building process and disk layout are documented.
- **Clear identity:** The CVIT-inspired interface gives the Nova work a purpose beyond instruction emulation.

## Risks and findings

### Boundary cases need stronger tests

The `TYPE LINES64` investigation exposed two issues in the command source:

1. The directory length was read using `10,AC2`. Assembly numbers default to octal, so this reads decimal offset 8, the load address, rather than the length at decimal offset 10 (`0o12`). For a file with the default load address `0o200`, that gave a length of 128 words.
2. `TYOUT` initialized its per-block count from the entire remaining file length rather than limiting it to the 128-word filesystem payload in a block. Correcting the length alone would not correctly handle a multi-block file.

At the time of this evaluation, changes addressing both issues were present in the working tree in `sd/cvit-command.asm` and `simh/cvit-command-simh.asm`; their full behavior still needs verification. The existing SIMH acceptance test includes `LINES64` in the image but only issues `TYPE HELLO` and checks for substrings. A short-file success does not establish multi-block correctness.

### Address and storage conventions are easy to confuse

Octal offsets, 128-word filesystem payloads, 256-word DSK transfers, and relocated code addresses are individually reasonable, but their interactions are easy to misread. Named constants and explicit, checked invariants would reduce the risk. In particular, a DSK transfer needs 256 words of buffer headroom even though only the first 128 words contain filesystem payload.

### Relocation is heuristic

`scripts/abs2bin.py` rebases page-zero values that fall within the assembled code-address range. A numeric constant in that range could therefore be mistaken for a pointer and changed. Explicit relocation information, or an image layout that avoids the heuristic, would be safer.

The suspected forward-`DW` assembler defect was not reproduced: a fresh build assembled `TYOUTP` as `0o3611`, the address of `TYOUT`. The image conversion correctly shifted that pointer to the relocated code address. A regression test was added at `snova.tests/AssemblerForwardReferenceTests.cs`.

### Smoke tests are not complete acceptance tests

`scripts/test-cvit-simh.sh` checks for expected substrings and can continue after a simulator timeout. This is useful as a smoke test, but does not establish that output is complete or execution terminated normally. The Dusky parity script likewise prints output rather than asserting full expected results.

## Recommended priorities

1. Add end-to-end `TYPE` regression tests on Dusky and SIMH, comparing complete output for empty, short, exact-128-word, multi-block, and partial-final-block text and binary files.
2. Define filesystem offsets, block sizes, calling conventions, and memory regions as named, shared or systematically checked definitions.
3. Make acceptance tests fail on unexpected timeout and verify completion and complete output, not merely expected substrings.
4. Replace or explicitly constrain heuristic relocation before more software depends on it.
5. Build `RUN` and other features on the resulting firmer base.
