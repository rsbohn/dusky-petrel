# Dusky Petrel Agent Notes

## Project
- `snova/` is a minimal Data General Nova 1210 emulator and monitor.
- The monitor is interactive and runs from `snova/Program.cs`.

## Build & Run
- Build: `dotnet build snova/Snova.csproj -c Release`
- Run: `dotnet run --project snova/Snova.csproj`

## Emulator Conventions
- Memory: 32K words (15-bit addresses), 16-bit words, octal by default.
- I/O: Nova I/O group uses top bits `15..13 = 011` (0x6000 mask).
- Device codes: use decimal literals with octal comments (e.g., `16 // 0o20`).
- Console devices: `TTI` = `0o10` (8), `TTO` = `0o11` (9).
- Monitor command `tty read <file>` queues input and appends ASCII EOT (0x04).
- Slow memory: `0o77760`–`0o77767` reads pause for 100 ms.
- TC08: monitor commands `tc status`, `tc0 attach|read|write`, `tc1 attach|read|write`.
- RTC: device `0o21` (17) provides minutes since midnight (DIA) and epoch seconds since 2000-01-01 (DIB/DIC low/high).

## Assembler
- Use the built-in assembler via `asm <file> [addr]`.
- `sd/` holds sample assembly programs.
