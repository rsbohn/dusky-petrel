; SIMH DSK boot sector stage: installed at sector 0 offsets 0o200..0o377.
; The image builder stores the low kernel in sectors 1021..1023 and
; the high extension in sectors 1018..1020 (decimal).
; BOOT DSK reads sector 0 into page zero, then executes its word at 0o377.
        ORG 0o200
BOOT:   LDA AC0, SECTOR
        DOA AC0, DSK
        LDA AC0, DEST
        DOB AC0, DSK
        NIOS 0,DSK
WAIT:   SKPDN DSK
        JMP WAIT
        DIA AC0, DSK
        MOV AC0, AC0, SZR
        HALT                    ; disk error
        LDA AC0, SECTOR
        INC AC0, AC0
        STA AC0, SECTOR
        LDA AC0, DEST
        LDA AC1, SECTSIZE
        ADD AC1, AC0
        STA AC0, DEST
        LDA AC0, COUNT
        LDA AC1, ONE
        SUB AC1, AC0
        STA AC0, COUNT
        MOV AC0, AC0, SZR
        JMP BOOT
        LDA AC0, PHASE
        MOV AC0, AC0, SZR
        JMP EXTCHECK
        INC AC0, AC0
        STA AC0, PHASE
        LDA AC0, EXTSECT
        STA AC0, SECTOR
        LDA AC0, EXTDEST
        STA AC0, DEST
        LDA AC0, THREE
        STA AC0, COUNT
        JMP BOOT
EXTCHECK:
        JSR @EXTDEST
        LDA AC1, EXTSIG
        SUB# AC1, AC0, SZR
        HALT                    ; extension missing or corrupt
        JMP @KERNEL
EXTSIG: DW 0o12345
PHASE:  DW 0
EXTSECT: DW 0o1772              ; decimal 1018
EXTDEST: DW 0o65000
THREE:   DW 3
SECTOR: DW 0o1775              ; decimal 1021
DEST:   DW 0o1000
SECTSIZE: DW 0o400
COUNT:  DW 3
ONE:    DW 1
KERNEL: DW 0o1000
        ORG 0o377
        JMP BOOT
