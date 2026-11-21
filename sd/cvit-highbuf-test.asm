; Verify kernel block reads can DMA a full sector into high RAM at 0o77000.
        ORG 0o4000
START:  LDA 1, CBP
        LDA 0, FOUR
        JSR @KSYS
        LDA 2, RESULTP
        STA 0, 0,2
        LDA 2, BUFFERP
        LDA 0, 0,2
        LDA 2, RESULTP
        STA 0, 1,2
        LDA 2, BUFFERP
        LDA 0, 1,2
        LDA 2, RESULTP
        STA 0, 2,2
        HALT
KSYS:   DW 0o1002
FOUR:   DW 4
CBP:    DW CB
CB:     DW 0, 2, 0o77000
RESULTP: DW RESULT
BUFFERP: DW 0o77000
        ORG 0o4200
RESULT: DW 0,0,0
