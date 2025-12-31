        ORG 0o200

INIT:   LDA AC1, STRPTR
        STA AC1, W

LOOP:   LDA AC0, @W  ; Load character from string
        NIOC AC0, TTO     ; Clear TTO flags (optional but safe)
        DOAS AC0, TTO      ; Send AC0 to TTO
	LDA AC0, @SLOWMEM  ; Read Slowly

WAIT:   SKPDN TTO         ; Skip next instruction if TTO is DONE
        JMP WAIT          ; Not done? Jump back and wait

        LDA AC1, W
        LDA AC3, ONE
        ADDZ AC3, AC1
        STA AC1, W
        LDA AC2, W
        LDA AC3, ENDADDR
        SUBZ AC3, AC2
        MOV AC2, AC2, SNR
        JMP INIT
        JMP LOOP

W:      DW 0
STRPTR: DW STR
ENDADDR: DW STR_END
ONE:    DW 1
STR:    .TXT /All work and no play makes Jack a dull boy./
        DW 0x0D, 0x0A
STR_END: DW 0
SLOWMEM: DW 077760
