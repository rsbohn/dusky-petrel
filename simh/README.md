# CVIT/Nova on SIMH — DSK adaptation

CVIT/Nova (see `docs/cvit-nova.md`) adapted to run on the SIMH DG Nova
emulator, which has no TC08/DECtape device. Instead of dusky's custom TC08
at device 0o20, this uses SIMH's DSK fixed-head disk, which also lives at
device 0o20 but speaks a different protocol.

Adapted from `sd/cvit-kernel.asm` and `sd/cvit-command.asm` as of branch
`1028` (merged to main 2026-10-29). The originals are untouched; the
`-simh` files are the SIMH variants.

## What changed

- **Block I/O**: the TC08 primitive (DOA = memory address, DOB = block,
  DOC = drive/read/write, 129-word blocks) is replaced by the SIMH DSK
  primitive (DOA = sector, DOB = memory address, NIOS = read, NIOP = write,
  256-word sectors). The transfer is asynchronous: start, poll `SKPDN`,
  then read `DIA` for error bits (0 = ok).
- **Mapping**: one TC08 block per DSK sector, block numbers preserved.
  Sector = drive * 1024 + block, so TC0: -> DSK disk 0 and TC1: -> DSK
  disk 1. The 128 payload words go in the first half of the sector; the
  second half is zero and ignored. The TC08 129th (spare) word is dropped
  by the converter.
- **Status convention preserved**: AC0 = 1 on success, 5 on any error, so
  callers (STA, CAT) work unchanged.
- **Console**: input via `DIAC`, output via `DOAS`. Dusky ignores the I/O
  pulses and behaves the same, so this shim runs on both emulators; plain
  `DIA`/`DOA` would re-read the last char forever on SIMH because its TTI
  done flag is only cleared by a clear pulse.

Everything above the block primitive (directory format, STA, CAT, the `]`
prompt) is unchanged.

## Building

Assemble with dusky's own assembler (it writes SIMH's `simh-load` format):

```
dotnet run --project dusky/Snova.csproj -- abs simh/cvit-kernel-simh.asm kernel.abs --format simh-load
dotnet run --project dusky/Snova.csproj -- abs simh/cvit-command-simh.asm command.abs --format simh-load --start 3000
```

(`--start 3000` matters for the command: without it the tape's start block
points at page-zero data instead of the code.)

Build the disk image in two steps:

```
python3 scripts/mk_cvit_nova.py cvit-tc08.img README.md=README.md
python3 simh/convert-tc08-to-dsk.py cvit-tc08.img cvit-dsk.img
```

The converter writes one block per sector (first 128 words copied, second
half zeroed), minimum 1024 sectors = one 524288-byte platter.

## Running (stage 1: no bootstrap yet)

In SIMH Nova:

```
attach dsk cvit-dsk.img
load kernel.abs
go 1000        ; prints "cvit/Nova V0.1", then HALT
load command.abs
go 3000        ; prints "cvit/Nova COMMAND V0.1" and the ] prompt
```

Verified 2026-10-28/29: `STA` -> `TC0: CVNV READY`, `CAT` lists the
directory (`README.MD`), an unknown command answers `?WHAT`, and an EOT
byte halts back to the `sim>` prompt. Do not use SIMH `BOOT DSK` for CVIT:
its boot ROM layout (jump to 0o375) is not CVIT's.

## Not in this push

The assembled binaries (`kernel.abs`, `command.abs`) and disk images
(`cvit-tc08.img`, `cvit-dsk.img`) are build artifacts and are not tracked
here; they are reproducible from the sources above. A built set from the
verification run lives at `quack:/srv/share/dusky/`.

## Still open

- Stage-2 DSK bootstrap: a small program that reads the kernel sectors
  into 0o1000 so the kernel is booted from disk instead of LOADed.
- Kernel cold start loading COMMAND from the directory into 0o3000.
- TYPE, then RUN, then Nova FOCAL (per the standing order in
  `docs/cvit-nova.md`).
