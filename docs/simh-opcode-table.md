# SIMH Nova Opcode Table

Source: `simh/NOVA/nova_cpu.c` and `simh/NOVA/nova_defs.h` in the local SIMH tree.

## Instruction formats

### Memory reference (MRF)

Format:
```
0  1  2  3  4  5  6  7  8  9 10 11 12 13 14 15
| 0| op  | AC  |in| mode|     displacement      |
```

MRF opcode+AC field (`IR<0:4>` in SIMH comments, `I_GETOPAC` in code):

- `00000` `JMP` : `PC = MA`
- `00001` `JMS` : `AC3 = PC, PC = MA`
- `00010` `ISZ` : `M[MA] = M[MA] + 1, skip if M[MA] == 0`
- `00011` `DSZ` : `M[MA] = M[MA] - 1, skip if M[MA] == 0`
- `001'n` `LDA` : `ACn = M[MA]` (n=0..3)
- `010'n` `STA` : `M[MA] = ACn` (n=0..3)

Addressing modes (`IR<5:7>` / `I_GETMODE`):

- `000` page zero direct      `MA = zext(IR<8:15>)`
- `001` PC relative direct    `MA = PC + sext(IR<8:15>)`
- `010` AC2 relative direct   `MA = AC2 + sext(IR<8:15>)`
- `011` AC3 relative direct   `MA = AC3 + sext(IR<8:15>)`
- `100` page zero indirect    `MA = M[zext(IR<8:15>)]`
- `101` PC relative indirect  `MA = M[PC + sext(IR<8:15>)]`
- `110` AC2 relative indirect `MA = M[AC2 + sext(IR<8:15>)]`
- `111` AC3 relative indirect `MA = M[AC3 + sext(IR<8:15>)]`

Notes:
- Displacement is 8-bit signed for relative modes.
- Autoindex: if indirect address is in `00020-00027`, increment before use;
  if in `00030-00037`, decrement before use.

### I/O transfer (IOT)

Format:
```
0  1  2  3  4  5  6  7  8  9 10 11 12 13 14 15
| 0  1  1| AC  | opcode |pulse|      device     |
```

Opcode field (`I_GETIOT`):
- `0` `NIO`
- `1` `DIA`
- `2` `DOA`
- `3` `DIB`
- `4` `DOB`
- `5` `DIC`
- `6` `DOC`
- `7` `SKP` (I/O skip)

Pulse field (`I_GETPULSE`):
- `0` `N`
- `1` `S`
- `2` `C`
- `3` `P`

For `SKP`, pulse selects skip sense:
- `0` skip if busy
- `1` skip if not busy
- `2` skip if done
- `3` skip if not done

### Operate (OPR)

Format:
```
0  1  2  3  4  5  6  7  8  9 10 11 12 13 14 15
| 1|srcAC|dstAC| opcode |shift|carry|nl|  skip  |
```

ALU opcode (`I_GETALU`):
- `0` COM
- `1` NEG
- `2` MOV
- `3` INC
- `4` ADC
- `5` SUB
- `6` ADD
- `7` AND

Shift (`I_GETSHF`):
- `0` none
- `1` left one
- `2` right one
- `3` byte swap

Carry (`I_GETCRY`):
- `0` load (use existing carry)
- `1` clear
- `2` set
- `3` complement

No-load bit (`nl` / `I_NLD`):
- `0` load result into destination AC
- `1` do not load result

Skip (`I_GETSKP`):
- `0` none
- `1` SKP
- `2` SZC
- `3` SNC
- `4` SZR
- `5` SNR
- `6` SEZ
- `7` SBN

## Device codes (from `nova_defs.h`)

- `0o01` MDV (multiply/divide)
- `0o02` ECC memory control
- `0o03` MMPU control
- `0o10` TTI (console input)
- `0o11` TTO (console output)
- `0o12` PTR (paper tape reader)
- `0o13` PTP (paper tape punch)
- `0o14` CLK (clock)
- `0o15` PLT (plotter)
- `0o16` CDR (card reader)
- `0o17` LPT (line printer)
- `0o20` DSK (fixed head disk)
- `0o22` MTA (mag tape)
- `0o24` DCM (data comm mux)
- `0o30` ADCV (A/D converter)
- `0o30` QTY (4060 multiplexor)
- `0o33` DKP (disk pack)
- `0o34` CAS (cassette)
- `0o34` ALM (ALM/ULM multiplexor)
- `0o43` PIT (programmable interval timer)
- `0o50` TTI1 (second console input)
- `0o51` TTO1 (second console output)
- `0o77` CPU control
