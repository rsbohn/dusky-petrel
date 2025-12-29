# Nova Assembler

This project includes a minimal two-pass assembler for the built-in Nova monitor.
Use it from the monitor with:

```
asm <file> [start]
```

The assembler loads words into memory and sets the PC to the lowest assembled
address unless you provide an explicit start address.

## Syntax basics

- Comments: `;` or `//`
- Labels: `label:`
- Tokens are separated by whitespace or commas.
- Numbers are octal by default; use `0x` (hex), `0o` (octal), `0b` (binary).
- Expressions support `+` and `-` with labels and numbers.

## Directives

- `ORG <expr>`: set the assembly location counter.
- `DW <expr> [expr ...]`: emit one or more literal words.

## Addressing

- `@expr` for indirect addressing.
- `P:expr` to force current-page addressing.
- If you omit `P:`, the assembler will choose zero-page or current-page when
  possible and will error if the target is not reachable.

## Instruction forms

Memory-reference instructions:

```
LDA ACn, addr
STA ACn, addr
ADD ACn, addr
SUB ACn, addr
AND ACn, addr
OR  ACn, addr
XOR ACn, addr
JSR ACn, addr
ISZ [ACn,] addr
```

Branch instructions:

```
BR addr
BZ [ACn,] addr
BNZ [ACn,] addr
```

I/O instructions (SIMH Nova layout):

```
DIA [ACn,] dev
DOA [ACn,] dev
DIB [ACn,] dev
DOB [ACn,] dev
DIC [ACn,] dev
DOC [ACn,] dev
NIO[.S|.C|.P] dev
SKPBN dev
SKPBZ dev
SKPDN dev
SKPDZ dev
```

Predefined device symbols:

```
TTI = 0o10
TTO = 0o11
```

Immediate and shift:

```
LDAI ACn, imm
ADDI ACn, imm    ; -128..255
SHL  ACn, count
SHLL ACn, count
SHR  ACn, count
SHRL ACn, count
```

Misc:

```
NOP
HALT
```
