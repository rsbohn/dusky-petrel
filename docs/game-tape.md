# Game Location Tape

This document describes the TU56 DECtape image created for a game that uses random location names.

## Overview

The tape image `game.tu56` contains 64 blocks (0o100 octal blocks), with each block containing a place name stored in the first 64 words. Place names are ASCII text, zero-terminated, with 2 characters per 16-bit word (high byte first, low byte second).

## Tape Format

- **Total blocks**: 64 (0o100 octal)
- **Block size**: 129 words (258 bytes)
  - 128 data words
  - 1 checksum/block number word (set to 0)
- **Data encoding**: Little-endian 16-bit words (as expected by TC08 BinaryReader)
- **Character encoding**: 2 ASCII characters per word (high byte = first char, low byte = second char)
- **String termination**: Zero word (0x0000)

## Location Names

The tape contains 64 unique location names:

| Block (Octal) | Block (Decimal) | Location Name          |
|---------------|-----------------|------------------------|
| 000           | 0               | The Ancient Harbor     |
| 001           | 1               | Misty Moorlands        |
| 002           | 2               | Crystal Caverns        |
| 003           | 3               | Abandoned Observatory  |
| 004           | 4               | Whispering Woods       |
| 005           | 5               | Forgotten Temple       |
| 006           | 6               | Floating Islands       |
| 007           | 7               | Underground Lake       |
| 010           | 8               | Storm Peak Summit      |
| 011           | 9               | Desert Oasis           |
| 012           | 10              | Frozen Tundra          |
| 013           | 11              | Volcanic Forge         |
| 014           | 12              | Sunken City Ruins      |
| 015           | 13              | Enchanted Garden       |
| 016           | 14              | Shadow Valley          |
| 017           | 15              | Celestial Tower        |
| 020           | 16              | Deep Forest Glade      |
| 021           | 17              | Rocky Cliffs           |
| 022           | 18              | Merchant's Bazaar      |
| 023           | 19              | Hidden Sanctuary       |
| 024           | 20              | The Great Library      |
| 025           | 21              | Moonlit Beach          |
| 026           | 22              | Mountain Pass          |
| 027           | 23              | Old Mill               |
| 030           | 24              | Dragon's Lair          |
| 031           | 25              | Sacred Grove           |
| 032           | 26              | Windswept Plains       |
| 033           | 27              | Coral Reef             |
| 034           | 28              | Ice Palace             |
| 035           | 29              | Ruins of Atlantis      |
| 036           | 30              | Mystic Falls           |
| 037           | 31              | Bone Yard              |
| 040           | 32              | Golden Fields          |
| 041           | 33              | Dark Abyss             |
| 042           | 34              | Sky Bridge             |
| 043           | 35              | Emerald Mines          |
| 044           | 36              | Ghost Town             |
| 045           | 37              | Serpent's Nest         |
| 046           | 38              | Lighthouse Point       |
| 047           | 39              | Canyon Echo            |
| 050           | 40              | Wizard's Tower         |
| 051           | 41              | Fishing Village        |
| 052           | 42              | Jungle Canopy          |
| 053           | 43              | Stone Circle           |
| 054           | 44              | Pirate Cove            |
| 055           | 45              | Silver Lake            |
| 056           | 46              | Thunder Mountain       |
| 057           | 47              | Silk Road Outpost      |
| 060           | 48              | Swamp of Sorrows       |
| 061           | 49              | Paradise Valley        |
| 062           | 50              | Fortress Ruins         |
| 063           | 51              | Starlight Plateau      |
| 064           | 52              | Burning Sands          |
| 065           | 53              | River Crossing         |
| 066           | 54              | Cloud City             |
| 067           | 55              | Haunted Mansion        |
| 070           | 56              | Pearl Lagoon           |
| 071           | 57              | Amber Forest           |
| 072           | 58              | The Crossroads         |
| 073           | 59              | Sapphire Grotto        |
| 074           | 60              | Eternal Spring         |
| 075           | 61              | Ravens Nest            |
| 076           | 62              | The Lost Garden        |
| 077           | 63              | Iron Gate Keep         |

## Creating the Tape

The tape was created using `create_game_tape.py`:

```bash
python3 create_game_tape.py game.tu56
```

This creates a 16,512-byte file (64 blocks × 129 words × 2 bytes).

## Using the Tape

### Demo Program

The file `sd/gametest.asm` reads a random block from TC08 and displays its location name:

```
snova> tc0 attach media/game.tu56
snova> asm sd/gametest.asm 100
snova> go 100
Hidden Sanctuary
snova> go 100
Dragon's Lair
snova> go 100
Mystic Falls
```

Each run (1 second apart) shows a different location!

The demo program:
1. Reads the RTC DIB (device 0o21) to get epoch seconds (low word)
   - **DIB changes every second** for true per-second randomness
   - DIA (minutes) only changes every ~60 seconds
2. Masks the value to 0-63 range for random block selection
3. Uses TC08 device I/O to load the block:
   - DOA: Set transfer address (0o1000)
   - DOB: Set block number
   - DOC: Set control word (0o2 = read from drive 0)
   - NIOS: Start the I/O operation
   - SKPDN: Wait for completion
4. Checks for errors
5. Prints the location name from the buffer

### TC08 Device Protocol

The program uses the TC08 controller (device code 0o20) with this I/O sequence:

```assembly
LDA 0, BUFBASE     ; Transfer address = 0o1000
DOA 0, 0o20        ; Set address in TC08

LDA 0, RNDBLK      ; Block number (0-63)
DOB 0, 0o20        ; Set block in TC08

LDA 0, RDCMD       ; Control: 0o2 = read
DOC 0, 0o20        ; Set control in TC08

NIOS 0, 0o20       ; Start I/O operation

WAIT: SKPDN 0o20   ; Skip if done
      JMP WAIT     ; Wait for completion

DIC 0, 0o20        ; Read status
; Check bit 2 for errors
```

### String Format

Each location name is stored as:
- 2 ASCII characters per 16-bit word
- High byte = first character
- Low byte = second character  
- Terminated with a zero word (0x0000)

Example: "Forgotten Temple"
```
Word    Octal   Hex     Chars
0       043157  0x4777  'F' 'o'
1       071147  0x7267  'r' 'g'
2       067564  0x6F74  'o' 't'
3       072145  0x7465  't' 'e'
4       067040  0x6E20  'n' ' '
5       052145  0x5465  'T' 'e'
6       066560  0x6D70  'm' 'p'
7       066145  0x6C65  'l' 'e'
8       000000  0x0000  (terminator)
```

## Future Enhancements

- Add full location descriptions (can use remaining words in each block)
- Add connections/exits to other locations
- Add items or NPCs at each location
- Implement random block selection in assembly code
