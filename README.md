# Dusky Petrel

Minimal Data General Nova 1210 emulator with an interactive monitor and built-in assembler.

## Build & Run

Build:
```
dotnet build dusky/Snova.csproj -c Release
```

Run:
```
dotnet run --project dusky/Snova.csproj
```

## Monitor Basics

Numbers default to octal; use `0x` for hex.

- `help` or `help <cmd>`
- `reset [addr]`
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

### TC08 Tape (host-side)

- `tc status`
- `tc0 attach <path> [new]`, `tc1 attach <path> [new]`
- `tc0 read <block> <addr>`, `tc1 read <block> <addr>`
- `tc0 write <block> <addr>`, `tc1 write <block> <addr>`
- `tc0 verify <block> <addr>`, `tc1 verify <block> <addr>`

Blocks are 129 words (128 data + 1 spare). Drives are `TC0` and `TC1`.

## Emulator Notes

- Memory: 32K words, 15-bit addresses, 16-bit words.
- I/O group: top bits `15..13 = 011` (0x6000 mask).
- Console devices: `TTI` = `0o10` (8), `TTO` = `0o11` (9).
- Paper tape: `PTR` = `0o12` (10), `PTP` = `0o13` (11).
- Line printer: `LPT` = `0o14` (12).
- Watchdog: `WDT` = `0o70` (56).
- Slow memory: reads from `0o77760` to `0o77767` pause for 100 ms.
- RTC device: `0o21` (17). `DIA` = minutes since midnight (UTC), `DIB`/`DIC` = epoch seconds (low/high, epoch 2000-01-01).
- Interrupts: `INTEN` enables interrupts after a one-instruction delay (so `INTEN` + `JMP @0` returns safely), `INTDS` disables, and `INTA` reports the device code.

## Paper Tape & Line Printer

- `ptr read <file>` queues raw 8-bit bytes for the paper tape reader.
- `ptr status` shows queued byte count.
- `ptp attach <file>` selects the output file for the paper tape punch (defaults to `./media/punch.out`).
- `ptp status` shows the current punch output path.
- `lpt status` shows the current line printer output path (defaults to `./media/print.out`).

## Samples

Sample assembly programs live in `sd/`.
Try `sd/moon.asm` for a WEB + JSP example that prints moon phase, moonrise, and moonset for Denver.
