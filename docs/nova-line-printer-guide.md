# Nova Line Printer Guide

This emulator provides a simple line printer (LPT) that writes bytes to a host file.

## Device code

- LPT: `0o14` (decimal 12)

## Monitor command

- `lpt status` shows the current output path (default: `./media/print.out`).

## I/O behavior

The line printer accepts any of `DOA/DOB/DOC` for output.
Only the low 8 bits of the accumulator are used.

- `DOA/DOB/DOC`: append one byte to the output file.
- `NIO C`: clear busy/done flags.
- `SKPBN/SKPBZ`: skip on busy/not busy.
- `SKPDN/SKPDZ`: skip on done/not done.

## Notes

- The emulator does not interpret line endings; emit `0x0A` or `0x0D` as needed.
- Output files are appended; delete them if you want a clean run.
