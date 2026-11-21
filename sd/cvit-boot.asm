; SIMH DSK boot sector stage: installed at sector 0 offsets 0o200..0o377.
; The image builder stores the kernel in sectors 1021..1023 (decimal).
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
        JMP @KERNEL
SECTOR: DW 0o1775              ; decimal 1021
DEST:   DW 0o1000
SECTSIZE: DW 0o400
COUNT:  DW 3
ONE:    DW 1
KERNEL: DW 0o1000
        ORG 0o377
        JMP BOOT
