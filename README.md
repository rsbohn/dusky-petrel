# Dusky Petrel

A Data General Nova 1210 emulator — and home of **CVIT/Nova**, a small
disk operating system that boots from its own disk image.

## CVIT/Nova V0.7

CVIT is an operator-at-the-terminal system for the Nova: a resident
kernel, a `]`-prompt command interpreter (COMMAND), and a FOCAL
interpreter with software floating point, all served by a chained-
directory filesystem with runtime write support. The same disk image
boots on Dusky and on SIMH.

At the `]` prompt:

- `STA` — volume status
- `CAT` — list the directory
- `TYPE <name>` — print a text member (`TYPE HELP` prints the on-disk help)
- `RUN <name>` — run a system member, e.g. `RUN FOCAL`; the program
  returns to the `]` prompt when it quits
- Ctrl-D (EOT) — halt

In FOCAL (the `*` prompt), `.save NAME` saves your program to disk —
saving over an existing name replaces it copy-on-write — and
`.load NAME` loads it back, even after a cold boot.

### Quick start

Get `cvit-dsk.img` from the
[v0.7 release](https://github.com/rsbohn/dusky-petrel/releases/tag/v0.7),
or build it yourself (see below). Then:

**Dusky** (build the emulator first, next section):

```
dsk0 attach cvit-dsk.img
boot dsk
```

**SIMH:**

```
attach dsk cvit-dsk.img
boot dsk
```

Build the image from source instead:

```
scripts/build-image.sh            # writes ./cvit-dsk.img
```

### Sample session

```
cvit/Nova V0.7

cvit/Nova COMMAND V0.7
]STA
DSK0: CVNV READY
]CAT
DSK0:
COMMAND
FOCAL
README.MD
HELP
HELLO
]TYPE HELLO
Hello from CVIT/Nova!
This is a sample text file.
]RUN FOCAL

FOCAL/Nova V0.7
*1.10 TYPE "HELLO FROM FOCAL"!
*GO
HELLO FROM FOCAL
*QUIT

cvit/Nova COMMAND V0.7
]
```

### CVIT documentation

- `docs/cvit-nova.md` — kernel, boot sequence, and syscall interface
- `docs/cvit-filesystem.md` — the filesystem specification (format
  version 2, chained directory, write support; signed off 2026-11-25)
- `docs/cvit-filesystem-api-draft.md` — filesystem selector contract
- `docs/focal.md` — FOCAL/Nova language notes
- `HELP.txt` — the help text shipped as member HELP on the image

## The Emulator

Minimal Nova 1210 emulator with an interactive monitor and built-in
assembler.

### Build & Run

Build:
```
dotnet build dusky/Snova.csproj -c Release
```

Run:
```
dotnet run --project dusky/Snova.csproj
```

### Monitor Basics

Numbers default to octal; use `0x` for hex.

- `help` or `help <cmd>`
- `reset [addr]`
- `boot dsk` reset the CPU and DSK controller, then boot the attached DSK0 image
- `go <addr|symbol> [n]` run from address or symbol (optional step limit)
- `run [n]` run until HALT/breakpoint (optional step limit)
- `step [n]`
- `exam <addr> [n]`
- `deposit <addr> <value> [value2 ...]`
- `dis <addr> [n]`
- `syms` list loaded assembler symbols
- `break <addr>`, `breaks`
- `asm <file> [addr]`
- `tty read <file>` queue input with ASCII EOT (0x04)
- `ptr read <file>` queue input for paper tape reader
- `ptp attach <file>` set output file for paper tape punch
- `lpt status` show line printer output path

#### TC08 Tape (host-side)

- `tc status`
- `tc0 attach <path> [new]`, `tc1 attach <path> [new]`
- `tc0 read <block> <addr>`, `tc1 read <block> <addr>`
- `tc0 write <block> <addr>`, `tc1 write <block> <addr>`
- `tc0 verify <block> <addr>`, `tc1 verify <block> <addr>`

Blocks are 129 words (128 data + 1 spare). Drives are `TC0` and `TC1`.

#### SIMH-style DSK

The block controller at `0o20` also accepts raw DSK images, with 1024 sectors
of 256 little-endian 16-bit words per drive. Attach a DSK image with
`dsk0 attach <path>` or `dsk1 attach <path>`; use `[new]` to create a blank
image, and `dsk status` to inspect the units. When a DSK image is attached to
a unit, it takes precedence over TC08 media on that unit. This format is
compatible with `convert-tc08-to-dsk.py` output and the SIMH CVIT image.

The existing Dusky `--console` launcher still loads the kernel from the
host rather than booting it from the image. Set `cpu limit <n>` before
booting an untested image to avoid running indefinitely.
`scripts/test-dsk-boot.sh` tests both emulators.

### Emulator Notes

- Memory: 32K words, 15-bit addresses, 16-bit words.
- I/O group: top bits `15..13 = 011` (0x6000 mask).
- Console devices: `TTI` = `0o10` (8), `TTO` = `0o11` (9).
- Paper tape: `PTR` = `0o12` (10), `PTP` = `0o13` (11).
- Line printer: `LPT` = `0o14` (12).
- Watchdog: `WDT` = `0o70` (56).
- Slow memory: reads from `0o77760` to `0o77767` pause for 100 ms.
- RTC device: `0o21` (17). `DIA` = minutes since midnight (UTC), `DIB`/`DIC` = epoch seconds (low/high, epoch 2000-01-01).
- Interrupts: `INTEN` enables interrupts after a one-instruction delay (so `INTEN` + `JMP @0` returns safely), `INTDS` disables, and `INTA` reports the device code.

### Paper Tape & Line Printer

- `ptr read <file>` queues raw 8-bit bytes for the paper tape reader.
- `ptr status` shows queued byte count.
- `ptp attach <file>` selects the output file for the paper tape punch (defaults to `./media/punch.out`).
- `ptp status` shows the current punch output path.
- `lpt status` shows the current line printer output path (defaults to `./media/print.out`).

### Samples

Sample assembly programs live in `sd/`.
Try `sd/moon.asm` for a WEB + JSP example that prints moon phase, moonrise, and moonset for Denver.
