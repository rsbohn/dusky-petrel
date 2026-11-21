; Invoke the extent writer directly with a caller-controlled test CB.
        ORG 0o4000
START:  LDA 1, CBP
        LDA 0, NINE
        JSR @KSYS
        LDA 2, RESULTP
        STA 0, 0,2
        HALT
NINE:   DW 0o11
KSYS:   DW 0o1002
CBP:    DW 0o4201
RESULTP: DW 0o4200
        ORG 0o4200
RESULT: DW 0o177777
CB:     DW 0, 0o1766, 0o7000, 0o201
