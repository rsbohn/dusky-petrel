; Skip/branch parity test for SIMH Nova vs Dusky
; Outputs a string: S=skipped, N=not skipped, J=jmp ok, R=jsr/ret ok
; Expected: SNSNJR (if both emulators agree)
;
; TTO device = 0o11

        ORG 0o1000

START:  ; Test 1: SZR with AC0=0 (should SKIP)
        LDA AC0, ZERO
        MOV AC0, AC0, SZR
        JMP T1N
        LDA AC0, CHS
        JSR OUTC
        JMP T2
T1N:    LDA AC0, CHN
        JSR OUTC
T2:     ; Test 2: SZR with AC0=1 (should NOT skip)
        LDA AC0, ONE
        MOV AC0, AC0, SZR
        JMP T2N
        LDA AC0, CHS
        JSR OUTC
        JMP T3
T2N:    LDA AC0, CHN
        JSR OUTC
T3:     ; Test 3: SNR with AC0=0 (should NOT skip)
        LDA AC0, ZERO
        MOV AC0, AC0, SNR
        JMP T3N
        LDA AC0, CHS
        JSR OUTC
        JMP T4
T3N:    LDA AC0, CHN
        JSR OUTC
T4:     ; Test 4: SNR with AC0=1 (should SKIP)
        LDA AC0, ONE
        MOV AC0, AC0, SNR
        JMP T4N
        LDA AC0, CHS
        JSR OUTC
        JMP T5
T4N:    LDA AC0, CHN
        JSR OUTC
T5:     ; Test 5: JMP (unconditional)
        JMP T5OK
        LDA AC0, CHN
        JSR OUTC
        JMP T6
T5OK:   LDA AC0, CHJ
        JSR OUTC
T6:     ; Test 6: JSR and return
        JSR SUBR
        LDA AC0, CHR
        JSR OUTC
        JMP DONE
SUBR:   JMP 0,AC3
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
CHS:    DW 0o123
CHN:    DW 0o116
CHJ:    DW 0o112
CHR:    DW 0o122
CHNL:   DW 0o012
