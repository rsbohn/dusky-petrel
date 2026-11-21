; Test persistent kernel sector write/read on a disposable disk image.
; Uses sector 1014, which must be free in the test fixture.
        ORG 0o4000
START:  LDA 2, BUFP
        LDA 0, MARKER
        STA 0, 0,2
        LDA 2, CBP
        JSR @KWRITE
        LDA 2, RESULTP
        STA 0, 0,2
        LDA 2, BUFP
        SUB 0,0
        STA 0, 0,2
        LDA 2, CBP
        JSR @KREAD
        LDA 2, RESULTP
        STA 0, 1,2
        LDA 2, BUFP
        LDA 0, 0,2
        LDA 2, RESULTP
        STA 0, 2,2
        HALT
MARKER: DW 0o12345
BUFP:   DW 0o7000
CBP:    DW CB
KWRITE: DW 0o1005
KREAD:  DW 0o1004
RESULTP: DW 0o4200
CB:     DW 0, 0o1766, 0o7000
        ORG 0o4200
RESULT: DW 0,0,0
