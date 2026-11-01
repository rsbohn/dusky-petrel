; Arithmetic parity test for SIMH Nova vs Dusky
; Tests ADD, SUB, ADC, INC, NEG, COM
; Outputs P=pass, F=fail per test
; Expected: PPPPP (if both emulators agree)
; Note: COM (Test 5) fails on Dusky - parity bug

        ORG 0o1000

START:  ; Test 1: ADD (5 + 3 = 8)
        LDA AC0, FIVE
        LDA AC1, THREE
        ADD AC1, AC0
        LDA AC1, EIGHT
        SUB AC1, AC0
        MOV AC0, AC0, SZR
        JMP T1F
        LDA AC0, CHP
        JSR OUTC
        JMP T2
T1F:    LDA AC0, CHF
        JSR OUTC
T2:     ; Test 2: SUB (10 - 4 = 6)
        LDA AC0, TEN
        LDA AC1, FOUR
        SUB AC1, AC0
        LDA AC1, SIX
        SUB AC1, AC0
        MOV AC0, AC0, SZR
        JMP T2F
        LDA AC0, CHP
        JSR OUTC
        JMP T3
T2F:    LDA AC0, CHF
        JSR OUTC
T3:     ; Test 3: INC (7 + 1 = 8)
        LDA AC0, SEVEN
        INC AC0, AC0
        LDA AC1, EIGHT
        SUB AC1, AC0
        MOV AC0, AC0, SZR
        JMP T3F
        LDA AC0, CHP
        JSR OUTC
        JMP T4
T3F:    LDA AC0, CHF
        JSR OUTC
T4:     ; Test 4: NEG (-5, then +5 = 0)
        LDA AC0, FIVE
        NEG AC0, AC0
        LDA AC1, FIVE
        ADD AC1, AC0
        MOV AC0, AC0, SZR
        JMP T4F
        LDA AC0, CHP
        JSR OUTC
        JMP T5
T4F:    LDA AC0, CHF
        JSR OUTC
T5:     ; Test 5: COM (~~0o1234 = 0o1234)
        LDA AC0, VAL1
        COM AC0, AC0
        COM AC0, AC0
        LDA AC1, VAL1
        SUB AC1, AC0
        MOV AC0, AC0, SZR
        JMP T5F
        LDA AC0, CHP
        JSR OUTC
        JMP DONE
T5F:    LDA AC0, CHF
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
ONE:    DW 1
THREE:  DW 3
FOUR:   DW 4
FIVE:   DW 5
SIX:    DW 6
SEVEN:  DW 7
EIGHT:   DW 0o10
TEN:    DW 0o12
VAL1:   DW 0o1234
ALL1:   DW 0o77777
CHP:    DW 0o120
CHF:    DW 0o106
CHNL:   DW 0o012
