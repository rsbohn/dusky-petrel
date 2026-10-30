# Running cvit/Nova on dusky-petrel

This is the current cvit/Nova bring-up: a standalone command interpreter with `STA` and `CAT`. It is not yet a complete bootable cvit system; load it manually in the dusky monitor. The image format is the small TC08 layout made by `scripts/mk_cvit_nova.py`.

## Build and start the emulator

From the repository root:

```sh
dotnet build dusky/Snova.csproj -c Release
dotnet run --project dusky/Snova.csproj
```

The monitor uses octal addresses by default. TC08 images use 129-word physical blocks (128 data words plus a spare word); cvit/Nova uses TC0 as `TC0:`.

## Make a test volume

In another shell, from the repository root:

```sh
python3 scripts/mk_cvit_nova.py /tmp/cvit.img README.md=README.md
printf 'STA\rCAT\r' >/tmp/cvit.in
```

The image maker puts the volume header in block 0, the flat directory in block 1, and member data from block 2 onward. It supports up to ten directory entries in this initial format. Member names are 1–10 characters. Text files are stored as ASCII bytes; binary-like files are stored as little-endian 16-bit words.

## Load and run the command interpreter

At the dusky monitor prompt, enter:

```text
asm sd/cvit-command.asm
 tc0 attach /tmp/cvit.img
 tty read /tmp/cvit.in
go 3000
```

Omit the leading space before `tc0 attach` if copying the commands. The assembler source loads at `0o3000` by default. `tty read` queues the input and appends ASCII EOT; the queued carriage returns submit `STA` and `CAT`.

Expected behavior: the interpreter displays a `]` prompt, `STA` checks block 0 and reports `TC0: CVNV READY`, and `CAT` reads block 1 and lists the packed member names (including `README`). The monitor can also attach a prebuilt image without the helper script.

## Optional: build a command member into the image

The image maker can include binaries and load metadata. For example, after assembling the command and producing a binary file:

```sh
scripts/mk_cvit_nova.py /tmp/cvit.img COMMAND=command.bin@3000 README.md=README.md
```

`COMMAND` defaults to load and entry address `0o3000`; other members default to `0o0200`. Addresses are octal unless prefixed with `#` for decimal or `0x`/`0o` for hexadecimal/octal. The current command interpreter does not automatically load `COMMAND` from the disk: the manual `asm`/`go` steps above are still needed.

For monitor help and other TC08 commands, see `README.md`; design and format details are in `docs/cvit-nova.md`.
