; Minimal syscall 6 probe: read first live entry, then halt.
        ORG 0o4000
START:  LDA 0, SIX
        LDA 1, CBP
        JSR @KERNEL
        STA 0, RESULT
        HALT
SIX:    DW 6
CBP:    DW CB
KERNEL: DW 0o1002
RESULT: DW 0o177777
CB:     DW 0, 0, 0, ENTRY
        DW 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
        DW 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
        DW 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
        DW 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
ENTRY:  DW 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
