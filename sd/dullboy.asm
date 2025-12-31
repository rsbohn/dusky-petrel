        ORG 0o200

INIT:   LDA AC1, STRPTR
        STA AC1, PTR

LOOP:   LDA AC0, @PTR     ; Load character from string
        NIO.C TTO         ; Clear TTO flags (optional but safe)
        DOA AC0, TTO      ; Send AC0 to TTO

WAIT:   SKPDN TTO         ; Skip next instruction if TTO is DONE
        BR WAIT           ; Not done? Jump back and wait

        LDA AC1, PTR
        LDAI AC3, 0
        ADDI AC1, 1
        STA AC1, PTR
        LDA AC2, PTR
        LDAI AC3, 0
        SUB AC2, ENDADDR
        BZ AC2, INIT
        BR LOOP

PTR:    DW 0
STRPTR: DW STR
ENDADDR: DW STR_END
STR:    .TXT /All work and no play makes Jack a dull boy./
        DW 0x0D, 0x0A
STR_END: DW 0
