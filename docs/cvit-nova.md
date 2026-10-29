# cvit/Nova bring-up notes

`cvit/Nova` is the DG Nova personality inspired by the Hawk/Disk6 `cvit` system.
It keeps the same user feel (`]CAT`, `]TYPE`, `]RUN`) but uses native Nova
words and TC08 block storage.

## Native assumptions

- Memory is 32K 16-bit words.
- TC08 device code is `0o20` (`DSK` in the assembler symbols).
- A TC08 physical block is 129 words; cvit/Nova uses the first 128 words as data.
- Drive names map to TC08 units: `TC0:` and `TC1:`.

## Initial memory layout

| Address | Use |
| --- | --- |
| `0o0200` | conventional assembled program start / later bootstrap |
| `0o1000` | resident cvit/Nova kernel jump table |
| `0o2000` | kernel directory buffer (DIRBUF, 256 words) |
| `0o3000` | `COMMAND` load address (from directory) |
| `0o7600` | scratch/block buffer area |

## Kernel jump table

The kernel starts at `0o1000` with stable Nova `JMP` vectors. Each vector is
`JMP @V_xxx` through a pointer cell, so the routines can live anywhere in
the kernel image. Existing vector addresses are preserved:

| Address | Vector | Description |
| --- | --- | --- |
| `0o1000` | cold start | Print banner, load COMMAND from disk, transfer control |
| `0o1001` | warm start | (reserved) |
| `0o1002` | syscall dispatch | AC0 = selector (see below) |
| `0o1003` | quit | HALT the machine |
| `0o1004` | read block | AC2 = control block (drive, block, mem) |
| `0o1005` | write block | AC2 = control block (drive, block, mem) |
| `0o1006` | GETC | Read one character from console into AC0 (blocking) |
| `0o1007` | PUTC | Write AC0 to console |
| `0o1010` | PUTS | Write NUL-terminated string at AC2 to console |

### Direct-call convention

Call via `JSR @V_xxx` (e.g., `JSR @KPUTSP` where `KPUTSP` holds `0o1010`).
AC3 holds the return link per Nova JSR convention.

- **GETC** (`0o1006`): No input; returns character in AC0. Blocks until
  a character is available. Uses `DIAC` (clear-on-read) for correct
  SIMH behavior.
- **PUTC** (`0o1007`): Input AC0 = character to write. Uses `DOAS`.
- **PUTS** (`0o1010`): Input AC2 = pointer to NUL-terminated string.
- **READBLK** (`0o1004`): Input AC2 = pointer to 3-word control block
  (drive, block, memory address). Returns AC0 = 1 on success, 5 on error
  (SIMH) or 0/1 (dusky).
- **QUIT** (`0o1003`): No input; does not return (HALTs).

### Syscall dispatch (`0o1002`)

AC0 = selector on entry:

| Selector | Service | Inputs |
| --- | --- | --- |
| 1 | putc | AC0 = char (on entry, selector overwritten) |
| 2 | getc | Returns char in AC0 |
| 3 | puts | AC2 = string pointer |
| 4 | read block | AC2 = control block |
| 5 | write block | AC2 = control block |

Returns AC0 = 0 on success, nonzero on error (except getc, which returns
the character).

## Boot sequence

1. **Cold start** (`0o1000`): Prints `cvit/Nova V0.1` banner via PUTS.
2. **LOADCMD**: Reads TC0 directory (block 1) into DIRBUF at `0o2000`
   via READBLK. Scans the 11-word directory entries for the name
   `COMMAND` (5 packed words: `0o41517, 0o46515, 0o40516, 0o42040, 0o20040`).
3. **Load**: For the matching entry, reads `block count` blocks starting
   at `start block` into the `load address` (128 payload words per block).
   The COMMAND member is a flat word image: `[n1][n1 page-zero words][code...]`.
4. **Transfer**: Jumps to the `entry address` from the directory, which is
   `load + 1 + n1` — the prologue that copies the page-zero words to
   `0o0050` before running.
5. **COMMAND** prints its own banner (`cvit/Nova COMMAND V0.1`) and the
   `]` prompt. It uses only kernel services for console and disk I/O.
6. **EOT** (Ctrl-D, `0o004`) at the prompt: COMMAND jumps to the kernel
   quit vector (`0o1003`), which HALTs.

Failure paths: `?DSK` if the directory read fails; `?NOCMD` if no COMMAND
entry is found. Both return to cold start, which HALTs.

## COMMAND member format

Built by `scripts/abs2bin.py` from a `simh-load` `.abs` file. The tool
requires a contiguous page-zero region starting at `0o0050` and a code
region starting at the load address (typically `0o3000`).

Output is a flat binary: `[n1][n1 words][code words...]` where `n1` is the
page-zero word count. The image maker (`scripts/mk_cvit_nova.py`) accepts:

```sh
scripts/mk_cvit_nova.py out.img COMMAND=command.bin@3000,3105 README.md=README.md
```

The `@load,entry` suffix sets the directory load address and entry address.
Entry must equal `load + 1 + n1` (computed by `abs2bin.py`).

## TC08 block control block

For direct `read_block` / `write_block`, `AC2` points to:

| Offset | Meaning |
| --- | --- |
| `+0` | drive (`0` = `TC0:`, `1` = `TC1:`) |
| `+1` | block number |
| `+2` | memory address |

The first implementation transfers a full TC08 block through the emulator device.
Only the first 128 words are filesystem payload; word 128 is reserved/ignored.

On SIMH, one TC08 block maps to one 256-word DSK sector:
`sector = drive * 1024 + block`. The sector buffer must have 256 words of
headroom, though only the first 128 hold filesystem data.

## Build and test

```sh
# Assemble (dusky)
dotnet Snova.dll abs sd/cvit-kernel.asm kernel.abs --format simh-load
dotnet Snova.dll abs sd/cvit-command.asm command.abs --format simh-load --start 3000

# Convert command to disk member format
python3 scripts/abs2bin.py command.abs command.bin

# Build disk image (entry = load + 1 + n1, reported by abs2bin.py)
python3 scripts/mk_cvit_nova.py cvit.img COMMAND=command.bin@3000,3105 README.md=README.md

# Convert to SIMH DSK (256-word sectors)
python3 simh/convert-tc08-to-dsk.py cvit.img cvit-dsk.img
```

SIMH smoke test (no manual load of COMMAND):

```text
attach dsk cvit-dsk.img
load kernel.abs
go 1000
```

Expected: kernel banner, COMMAND auto-loads from disk, `]` prompt.
`STA` → `TC0: CVNV READY`; `CAT` → lists `COMMAND` and `README.MD`;
`FOO` → `?WHAT`; EOT → HALT.

## Status

- [x] Kernel jump table with GETC/PUTC/PUTS (vectors `0o1006`-`0o1010`)
- [x] COMMAND uses kernel services; no duplicate device drivers
- [x] Cold start loads COMMAND from disk; EOT returns to kernel HALT
- [x] STA and CAT preserved
- [ ] TYPE command (next)
- [ ] RUN command (after TYPE)
- [ ] Nova FOCAL with software floating point (after RUN)
