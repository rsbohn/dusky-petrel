; Exercise two monotonic allocations: one sector, then two sectors.
        ORG 0o4000
START:  LDA 1, CBP
        LDA 0, EIGHT
        JSR @KSYS
        LDA 2, RESULTP
        STA 0, 0,2
        LDA 2, CBP
        LDA 0, 2,2
        LDA 2, RESULTP
        STA 0, 1,2
        LDA 2, CBP
        LDA 0, TWO
        STA 0, 1,2
        LDA 1, CBP
        LDA 0, EIGHT
        JSR @KSYS
        LDA 2, RESULTP
        STA 0, 2,2
        LDA 2, CBP
        LDA 0, 2,2
        LDA 2, RESULTP
        STA 0, 3,2
        HALT
EIGHT:  DW 0o10
TWO:    DW 2
KSYS:   DW 0o1002
CBP:    DW 0o4204
RESULTP: DW 0o4200
        ORG 0o4200
RESULT: DW 0,0,0,0
CB:     DW 0,1,0o177777
