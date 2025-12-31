# Nova Paper Tape Guide

This emulator provides a paper tape reader (PTR) and paper tape punch (PTP).
They are modeled as byte streams with simple ready/busy flags.

## Device codes

- PTR: `0o12` (decimal 10)
- PTP: `0o13` (decimal 11)

## Monitor commands

- `ptr read <file>` queues raw 8-bit bytes into the reader.
- `ptr status` shows queued byte count.
- `ptp attach <file>` sets the punch output file (default: `./media/punch.out`).
- `ptp status` shows the current punch output path.

## I/O behavior

Both devices accept any of `DIA/DIB/DIC` for input and `DOA/DOB/DOC` for output.
Only the low 8 bits of the accumulator are used.

### PTR (reader)

- `DIA/DIB/DIC`: read next byte into AC low 8 bits.
- `NIO C`: clear the input queue.
- `SKPDN`: skip if input is available.
- `SKPDZ`: skip if input is empty.
- `SKPBN/SKPBZ`: return constant false/true (no busy simulation).

### PTP (punch)

- `DOA/DOB/DOC`: append one byte to the punch output file.
- `NIO C`: clear busy/done flags.
- `SKPBN/SKPBZ`: skip on busy/not busy.
- `SKPDN/SKPDZ`: skip on done/not done.

## Notes

- The reader and punch do not enforce line endings or parity.
- Output files are appended; delete them if you want a clean run.
