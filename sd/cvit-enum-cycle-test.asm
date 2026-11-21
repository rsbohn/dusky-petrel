; Enumerate until end/error; RESULT must be 3 for a cyclic chain.
        ORG 0o4000
START:  LDA 0, SIX
        LDA 1, CBP
        JSR @KERNEL
        MOV 0,0,SNR
        JMP START
        STA 0, RESULT
        LDA 0, SIX
        LDA 1, CBP
        JSR @KERNEL
        STA 0, RESULT2
        HALT
SIX:    DW 6
CBP:    DW CB
KERNEL: DW 0o1002
RESULT: DW 0
RESULT2: DW 0
CB:     DW 0, 0, 0, ENTRY
        DW 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
        DW 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
        DW 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
        DW 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
ENTRY:  DW 0,0,0,0,0,0,0,0,0,0,0,0
