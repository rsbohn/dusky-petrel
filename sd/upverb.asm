; Isolated test for UPVERB.
; Code first at 0o1000, data after.

        ORG 0o1000
START:  JSR @UPVERBP       ; uppercase LINE[0..3]
        HALT               ; halt; ex LINE to verify

; UPVERB: Uppercase LINE[0..3] in place.
UPVERB: STA AC3, UPVRET
        LDA AC2, LINEP
        LDA AC3, FOUR
UPVLP:  LDA AC0, 0,AC2
        STA AC0, UPTMP
        LDA AC1, LOA
        SUB AC1, AC0
        MOV AC0, AC1
        LDA AC0, HIMASK
        AND AC0, AC1
        MOV AC1, AC1, SZR
        JMP UPVNO
        LDA AC0, UPTMP
        LDA AC1, HIZ
        SUB AC0, AC1
        MOV AC1, AC1
        LDA AC0, HIMASK
        AND AC0, AC1
        MOV AC1, AC1, SZR
        JMP UPVNO
        LDA AC0, UPTMP
        LDA AC1, TOUPPER
        SUB AC1, AC0
        STA AC0, 0,AC2
UPVNO:  LDA AC0, ONE
        ADD AC0, AC2
        LDA AC0, NEG1
        ADD AC0, AC3
        MOV AC3, AC3, SNR
        JMP @UPVRET
        JMP UPVLP
UPVRET: DW 0
UPTMP:  DW 0

; Constants and data
LOA:     DW 0o141
HIZ:     DW 0o172
HIMASK:  DW 0o100000
TOUPPER: DW 0o40
ONE:     DW 1
FOUR:    DW 4
NEG1:    DW -1
LINEP:   DW LINE
UPVERBP: DW UPVERB
LINE:   DW 0o163          ; "s" -> "S"
        DW 0o164          ; "t" -> "T"
        DW 0o141          ; "a" -> "A"
        DW 0              ; NUL
        DW 0o505          ; "E" unchanged
        DW 0o520          ; "P" unchanged
