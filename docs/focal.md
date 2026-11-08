# FOCAL/Nova

FOCAL/Nova is a FOCAL interpreter for cvit/Nova, written in Nova assembly
(`sd/focal.asm`) with software floating point. It runs as a CVIT `RUN`
member on both Dusky and SIMH.

```text
]RUN FOCAL

FOCAL/Nova V0.1
*01.10 FOR I=1,5; TYPE %3, I, I^2, !
*GO
   1   1
   2   4
   ...
*QUIT
```

`QUIT` at the `*` prompt, or EOT (Ctrl-D) at any time, returns to the
COMMAND `]` prompt through the kernel warm start (`0o1001`).

## Lines

A line typed with a leading line number is stored; any other line runs
immediately. Line numbers are `group.step`, from `1.01` to `99.99`
(`1.1` is `01.10`). Retyping a number replaces the line; typing a number
alone deletes it. Commands on one line are separated by `;`. Only the
first letter of a command word matters (`T`, `TYPE` and `TYPO` are the
same). Input is upper-cased outside double quotes. Rubout or backspace
erases the last character.

## Commands

| Command | Meaning |
| --- | --- |
| `ASK "text", X, ...` | Print `:` and read one line per variable, evaluated as an expression (an empty line is 0) |
| `COMMENT ...` | Ignore the rest of the line |
| `DO 2` / `DO 2.1` / `DO` | Run group 2, line 2.10, or the whole program, then return here |
| `ERASE` | Clear all variables |
| `ERASE ALL` | Clear variables and the program |
| `ERASE 2` / `ERASE 2.1` | Delete group 2 or line 2.10 |
| `FOR I=a,b; ...` | Run the rest of the line for I = a, a+1, ... b |
| `FOR I=a,s,b; ...` | The same with step s (may be negative) |
| `GOTO 1.3` / `GOTO` | Continue at line 1.30, or at the first line |
| `IF (e) l1,l2,l3` | Go to l1 if e < 0, l2 if e = 0, l3 if e > 0; a missing or empty target continues with the next command |
| `QUIT` | Stop the program; at the `*` prompt, leave FOCAL |
| `RETURN` | End the current `DO` |
| `SET X = e` | Assign |
| `TYPE ...` | Print items: `"text"`, `!` (new line), `#` (carriage return), `%w.d` (format), `$` (all variables), or an expression |
| `WRITE` / `WRITE 2` / `WRITE 2.1` | List the program, a group, or a line |

Group and line arguments are expressions (`DO N`, `GOTO 1+.1`).

## Expressions

Operators, from highest precedence: `^` (integer power), unary `-` / `+`,
`*` `/`, `+` `-`. Brackets `( )`, `[ ]` and `< >` all group. Numbers may
use `E` notation (`1.5E3`).

Variables have one or two significant characters (a letter, then a letter
or digit; more are allowed and ignored), and may take a subscript:
`A(I+1)`. Names beginning with `F` are functions. A variable that has not
been set reads as 0.

| Function | Value |
| --- | --- |
| `FABS(x)` | absolute value |
| `FSGN(x)` | -1, 0 or 1 |
| `FITR(x)` | integer part (toward zero) |
| `FSQT(x)` | square root |

## Output format

`%w.d` prints numbers in `w` digit positions with `d` of them after the
decimal point, right-justified and preceded by a sign column (a space or
`-`). The default is `%8.04`, so `TYPE 3` prints `    3.0000`. A bare
`%` selects E format (` 0.333333E+00`), which is also used whenever a
value needs more than `w` digits.

## Errors

Errors print `?CODE`, plus ` @ gg.ss` when a program line was running, and
return to the `*` prompt.

| Code | Meaning |
| --- | --- |
| `?SYN` | Syntax error |
| `?CMD` | Unknown command |
| `?LIN` | No such line or group, or an invalid line number |
| `?DIV` | Division by zero |
| `?OVF` | Number too large |
| `?FUN` | Unknown function, or `FSQT` of a negative |
| `?MEM` | Program text full |
| `?VAR` | Variable table full (512 variables) |
| `?STK` | Nesting too deep |

## Numbers

Floating point uses the DG single-precision layout: a sign bit, a 7-bit
excess-64 hexadecimal exponent and a 24-bit hex-normalized fraction
(value = 0.F × 16^(E-64)), in two 16-bit words. That gives about six
significant decimal digits. Integers up to 2^24 are exact. Zero is
`0,0`. All arithmetic is done in software (shift-and-add multiply,
restoring divide) using only Nova 1210 instructions.

## Memory map

| Address | Use |
| --- | --- |
| `0o0020` | `SP`, software stack pointer (auto-increment cell) |
| `0o0040`-`0o0377` | constants, globals and routine pointers |
| `0o1000`-`0o2377` | cvit/Nova kernel and directory buffer (left intact) |
| `0o6000`- | interpreter (load and entry address) |
| `0o30000`-`0o55577` | program text, one character per word |
| `0o56000`-`0o57777` | software stack |
| `0o60000`-`0o63777` | variable table, 4 words per variable |
| `0o64000` / `0o64200` | input line / `ASK` buffers |

## Building

The page-zero cells are assembled at `0o0040` in the same source.
`abs2flat.py --pz` appends them after the code as
`[start][count][words]`, at the `PZIMG` label that ends `sd/focal.asm`.
The startup code copies them back to page zero.

```sh
Snova abs sd/focal.asm focal.abs --format simh-load
python3 scripts/abs2flat.py --pz focal.abs focal.sys 0o6000
python3 scripts/mk_cvit_nova.py cvit.img COMMAND=... "FOCAL=focal.sys@0o6000,0o6000"
```

`scripts/build-image.sh` includes FOCAL. `scripts/test-focal.sh` runs
`testdata/focal-session.txt` on Dusky and SIMH and compares both
transcripts with `testdata/focal-session.expected` (`--update` rewrites
the expected file from Dusky).

## Not yet

- Transcendental functions (`FSIN`, `FCOS`, `FEXP`, `FLOG`, `FATN`) and `FRAN`
- `MODIFY`, and loading or saving programs on the CVIT disk
- Breaking out of a running program (Ctrl-C) without halting the machine
