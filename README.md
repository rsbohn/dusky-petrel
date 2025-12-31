# Dusky Petrel

Minimal Data General Nova 1210 emulator with an interactive monitor and built-in assembler.

## Build & Run

Build:
```
dotnet build snova/Snova.csproj -c Release
```

Run:
```
dotnet run --project snova/Snova.csproj
```

## Monitor Basics

Numbers default to octal; use `0x` for hex.

- `help` or `help <cmd>`
- `reset [addr]`
- `go <addr> [n]` run from address (optional step limit)
- `run [n]` run until HALT/breakpoint (optional step limit)
- `step [n]`
- `exam <addr> [n]`
- `deposit <addr> <value> [value2 ...]`
- `dis <addr> [n]`
- `break <addr>`, `breaks`
- `asm <file> [addr]`
- `tty read <file>` queue input with ASCII EOT (0x04)

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
- Slow memory: reads from `0o77760` to `0o77767` pause for 100 ms.
- RTC device: `0o21` (17). `DIA` = minutes since midnight (UTC), `DIB`/`DIC` = epoch seconds (low/high, epoch 2000-01-01).

## Samples

Sample assembly programs live in `sd/`.
