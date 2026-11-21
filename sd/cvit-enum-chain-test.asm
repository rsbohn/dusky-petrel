; Enumerate ten entries; the last comes from the second directory block.
        ORG 0o4000
START:  LDA 0, SIX
        LDA 1, CBP
        JSR @KERNEL
        MOV 0,0,SZR
        HALT
        DSZ COUNT
        JMP START
        HALT
SIX:    DW 6
CBP:    DW CB
KERNEL: DW 0o1002
COUNT:  DW 0o12
CB:     DW 0, 0, 0, ENTRY
        DW 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
        DW 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
        DW 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
        DW 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
ENTRY:  DW 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
