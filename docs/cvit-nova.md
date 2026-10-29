# cvit/Nova bring-up notes

`cvit/Nova` is the DG Nova personality inspired by the Hawk/Disk6 `cvit` system.
It keeps the same user feel (`]CAT`, `]TYPE`, `]RUN`) but uses native Nova
words and TC08 block storage.

## Native assumptions

- Memory is 32K 16-bit words.
- TC08 device code is `0o20` (`DSK` in the assembler symbols).
- A TC08 physical block is 129 words; cvit/Nova uses the first 128 words as data.
- Drive names map to TC08 units: `TC0:` and `TC1:`.

## Initial memory layout

| Address | Use |
| --- | --- |
| `0o0200` | conventional assembled program start / later bootstrap |
| `0o1000` | resident cvit/Nova kernel jump table |
| `0o3000` | future `SYSTEM/COMMAND` load address |
| `0o7600` | scratch/block buffer area |

## Kernel jump table

The kernel starts at `0o1000` with stable Nova `JMP` vectors:

| Address | Vector |
| --- | --- |
| `0o1000` | cold start |
| `0o1001` | warm start |
| `0o1002` | syscall dispatch |
| `0o1003` | quit |
| `0o1004` | read block |
| `0o1005` | write block |

Calling convention for early routines:

```text
AC0 = selector / return code
AC1 = control block pointer for syscall-style calls
AC2 = control block pointer for direct block calls, or string pointer for puts
AC3 = return link, Nova JSR convention
```

Return convention:

```text
AC0 = 0 success
AC0 != 0 error/status
```

## TC08 block control block

For direct `read_block` / `write_block`, `AC2` points to:

| Offset | Meaning |
| --- | --- |
| `+0` | drive (`0` = `TC0:`, `1` = `TC1:`) |
| `+1` | block number |
| `+2` | memory address |

The first implementation transfers a full TC08 block through the emulator device.
Only the first 128 words are filesystem payload; word 128 is reserved/ignored.

## First milestone

`sd/cvit-kernel.asm` is a minimal resident kernel skeleton. It currently:

- publishes the jump table at `0o1000`,
- prints a `cvit/Nova` banner,
- provides console `putc`/`puts`,
- provides TC08 read/write block vectors.

`sd/cvit-command.asm` is the first standalone command interpreter.  Load it at
`0o3000`; it prompts with `]`, accepts `STA` and `CAT`, reads TC0 volume and
directory blocks, reports volume readiness, and lists packed flat-directory
names.

Bring-up example:

```sh
python3 scripts/mk_cvit_nova.py /tmp/cvit.img README.md=README.md
printf 'STA\rCAT\r' >/tmp/cat.in
```

Then in the monitor:

```text
asm sd/cvit-command.asm
tc0 attach /tmp/cvit.img
tty read /tmp/cat.in
go 3000
```

The image maker accepts optional member load metadata:

```sh
scripts/mk_cvit_nova.py out.img COMMAND=command.bin@3000 README.md=README.md
```

Addresses are octal by default; use `#` for decimal or `0x`/`0o` prefixes.
`COMMAND` defaults to load/entry address `0o3000`; other members default to
`0o0200`.

Next steps:

1. Add a fixed-location bootstrap that reads the kernel from TC08 into `0o1000`.
2. Teach the kernel cold start to load `COMMAND` from the directory into `0o3000`.
3. Add `TYPE <name>`.
4. Add `RUN <name>`.
