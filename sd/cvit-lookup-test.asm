; Lookup FILE9; RESULT receives status and ENTRY receives the directory entry.
        ORG 0o4000
START:  LDA 0, SEVEN
        LDA 1, CBP
        JSR @KERNEL
        STA 0, RESULT
        HALT
SEVEN:  DW 7
CBP:    DW CB
KERNEL: DW 0o1002
RESULT: DW 0o177777
CB:     DW 0, NAME, ENTRY
NAME:   DW 0o43111, 0o46105, 0o34440, 0o20040, 0o20040
ENTRY:  DW 0,0,0,0,0,0,0,0,0,0,0,0
