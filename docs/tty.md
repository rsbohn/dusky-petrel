# Nova Console TTY (SIMH-Compatible)

This document summarizes the console terminal devices used by SIMH Nova
emulation so that Dusky Petrel remains compatible with existing Nova software
and diagnostics.

## Devices

- TTI: console input, device code `0o10`
- TTO: console output, device code `0o11`
- UTTO: unicode console output, device code `0o23`

Both devices expose Register A (8-bit buffer), BUSY and DONE flags, and an
optional interrupt enable/disable state. Registers B and C are unused.

## Nova I/O instruction layout (16-bit word)

```
15..13 = 011  (I/O group)
12..11 = Signal (00=None, 01=Start, 10=Clear, 11=Pulse)
10..8  = Function (NIO/DIA/DOA/.../SKP)
7..6   = AC (AC0-AC3 or skip subtype)
5..0   = Device / Channel (0-63)
```

## Skip instructions (BUSY / DONE)

```
AC=00  SKPBN  skip if BUSY = 1
AC=01  SKPBZ  skip if BUSY = 0
AC=10  SKPDN  skip if DONE = 1
AC=11  SKPDZ  skip if DONE = 0
```

## TTI (console input, 0o10)

- DONE=1 when a character is available in Register A.
- DIA reads A -> AC and clears DONE.
- Input is normally driven from a queued FIFO source.
- The monitor's `tty read` command appends an ASCII EOT (`0x04`) marker at the end
  of the file to signal EOF to Nova software that expects it.

## TTO (console output, 0o11)

- DOA writes AC -> A and initiates character output.
- BUSY indicates output in progress.
- Simple implementations may complete immediately.

## UTTO (unicode output, 0o23)

- DOA/DOB/DOC write a UTF-16 code unit from AC to output.
- The device ignores a leading BOM (0xFEFF) on the first output word.
- Surrogate pairs are combined; malformed sequences emit U+FFFD.

## Echo program

```
LOOP:   SKPDN   TTI         ; wait for character
        JMP     LOOP
        DIA     TTI         ; read char -> AC0
        DOA     TTO         ; echo to console
        JMP     LOOP
```
