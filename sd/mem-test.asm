; Memory access parity test for SIMH Nova vs Dusky
; Tests LDA, STA, indexed LDA/STA
; Outputs P=pass, F=fail per test
; Expected: PPPP (if both emulators agree)

        ORG 0o1000

START:  ; Test 1: STA then LDA (direct)
        LDA AC0, VAL1
        STA AC0, TESTMEM
        LDA AC0, ZERO
        LDA AC0, TESTMEM
        LDA AC1, VAL1
        SUB AC1, AC0
        MOV AC0, AC0, SZR
        JMP T1F
        LDA AC0, CHP
        JSR OUTC
        JMP T2
T1F:    LDA AC0, CHF
        JSR OUTC
T2:     ; Test 2: STA with index (STA AC0, 5,AC2)
        LDA AC2, MEMBASE
        LDA AC0, VAL2
        STA AC0, 5,AC2
        LDA AC0, ZERO
        LDA AC2, MEMBASE
        LDA AC0, 5,AC2
        LDA AC1, VAL2
        SUB AC1, AC0
        MOV AC0, AC0, SZR
        JMP T2F
        LDA AC0, CHP
        JSR OUTC
        JMP T3
T2F:    LDA AC0, CHF
        JSR OUTC
T3:     ; Test 3: LDA with displacement (LDA AC0, TESTMEM2)
        LDA AC0, VAL3
        STA AC0, TESTMEM2
        LDA AC0, ZERO
        LDA AC0, TESTMEM2
        LDA AC1, VAL3
        SUB AC1, AC0
        MOV AC0, AC0, SZR
        JMP T3F
        LDA AC0, CHP
        JSR OUTC
        JMP T4
T3F:    LDA AC0, CHF
        JSR OUTC
T4:     ; Test 4: STA AC3, n,AC2 and LDA AC3, n,AC2 (AC3 as data)
        LDA AC2, MEMBASE
        LDA AC3, VAL4
        STA AC3, 10,AC2
        LDA AC3, ZERO
        LDA AC2, MEMBASE
        LDA AC3, 10,AC2
        LDA AC1, VAL4
        SUB AC1, AC3
        MOV AC3, AC3, SZR
        JMP T4F
        LDA AC0, CHP
        JSR OUTC
        JMP DONE
T4F:    LDA AC0, CHF
        JSR OUTC
DONE:   LDA AC0, CHNL
        JSR OUTC
        HALT

; OUTC: output char in AC0 via TTO
OUTC:   STA AC3, OUTRET
PWAIT:  SKPBZ TTO
        JMP PWAIT
        DOAS AC0, TTO
        JMP @OUTRET
OUTRET: DW 0

ZERO:   DW 0
VAL1:   DW 0o1234
VAL2:   DW 0o5670
VAL3:   DW 0o1111
VAL4:   DW 0o2222
CHP:    DW 0o120
CHF:    DW 0o106
CHNL:   DW 0o012
TESTMEM: DW 0
TESTMEM2: DW 0
MEMBASE: DW 0
         DW 0
         DW 0
         DW 0
         DW 0
         DW 0
         DW 0
         DW 0
         DW 0
         DW 0
         DW 0
         DW 0
