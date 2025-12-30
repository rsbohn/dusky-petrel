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
- Console devices: `TTI` = `0o10` (8), `TTO` = `0o11` (9).
- Monitor command `tty read <file>` queues input and appends ASCII EOT (0x04).

## Assembler
- Use the built-in assembler via `asm <file> [addr]`.
- `sd/` holds sample assembly programs.
