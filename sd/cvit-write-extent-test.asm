; Reserve two blocks and write 130 words, with markers in each block.
        ORG 0o4000
START:  LDA 1, ALLOCP
        LDA 0, EIGHT
        JSR @KSYS
        LDA 2, RESULTP
        STA 0, 0,2
        MOV 0,0,SZR
        HALT
        LDA 2, ALLOCP
        LDA 0, 2,2
        LDA 2, RESULTP
        STA 0, 2,2
        LDA 2, WRITECBP
        STA 0, 1,2
        LDA 2, FIRSTP
        LDA 0, FIRST
        STA 0, 0,2
        LDA 2, SECONDP
        LDA 0, SECOND
        STA 0, 0,2
        LDA 1, WRITECBP
        LDA 0, NINE
        JSR @KSYS
        LDA 2, RESULTP
        STA 0, 1,2
        HALT
EIGHT: DW 0o10
NINE: DW 0o11
KSYS: DW 0o1002
ALLOCP: DW 0o4203
WRITECBP: DW 0o4206
RESULTP: DW 0o4200
FIRSTP: DW 0o7000
SECONDP: DW 0o7200
FIRST: DW 0o12345
SECOND: DW 0o54321
        ORG 0o4200
RESULT: DW 0o177777,0o177777,0o177777
ALLOC:  DW 0,2,0o177777
WRITE:  DW 0,0,0o7000,0o202
