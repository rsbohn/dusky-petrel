; Operate-instruction carry parity test for SIMH Nova vs Dusky.
; Each case prints "c:rrrrrr " (carry, then the 16-bit result in octal).
; Run on both emulators and compare the output line by line.
; Assemble at 0o1000 (asm sd/carry-test.asm, go 1000).

        ORG 0o1000

START:  LDA 0, V124         ; 1: SUBZ 124-40 -> carry 1 (no borrow)
        LDA 1, V40
        SUBZ 1,0
        JSR @PSHOW
        LDA 0, V40          ; 2: SUBZ 40-124 -> carry 0 (borrow)
        LDA 1, V124
        SUBZ 1,0
        JSR @PSHOW
        LDA 0, V5           ; 3: SUBO 5-5 -> base 1, carry out -> 0
        LDA 1, V5
        SUBO 1,0
        JSR @PSHOW
        LDA 0, VM1          ; 4: ADDZ 177777+1 -> 0, carry 1
        LDA 1, V1
        ADDZ 1,0
        JSR @PSHOW
        LDA 0, V1           ; 5: ADDO 1+1 -> 2, carry 1
        LDA 1, V1
        ADDO 1,0
        JSR @PSHOW
        LDA 0, V5           ; 6: ADCZ 5+~3 -> 1, carry 1
        LDA 1, V3
        ADCZ 1,0
        JSR @PSHOW
        LDA 0, V3           ; 7: ADCZ 3+~5 -> 177775, carry 0
        LDA 1, V5
        ADCZ 1,0
        JSR @PSHOW
        SUB 0,0             ; 8: NEGZ 0 -> 0, carry 1
        NEGZ 0,0
        JSR @PSHOW
        LDA 0, V5           ; 9: NEGZ 5 -> 177773, carry 0
        NEGZ 0,0
        JSR @PSHOW
        LDA 0, VM1          ; 10: INCZ 177777 -> 0, carry 1
        INCZ 0,0
        JSR @PSHOW
        LDA 0, V1           ; 11: INCO 1 -> 2, carry 1
        INCO 0,0
        JSR @PSHOW
        LDA 0, V5           ; 12: COMO 5 -> 177772, carry 1
        COMO 0,0
        JSR @PSHOW
        LDA 0, V100K        ; 13: MOVZL 100000 -> 0, carry 1
        MOVZL 0,0
        JSR @PSHOW
        SUB 0,0             ; 14: MOVOR 0 -> 100000, carry 0
        MOVOR 0,0
        JSR @PSHOW
        LDA 0, V100K        ; 15: ADDZL 100000+100000 -> 1, carry 0
        LDA 1, V100K
        ADDZL 1,0
        JSR @PSHOW
        LDA 0, V40          ; 16: SUBZ# leaves AC and carry: carry 1, 40
        LDA 1, V124
        MOVO 1,1
        SUBZ# 1,0
        JSR @PSHOW
        LDA 0, V124         ; 17: SUBZ# skip test sees new carry
        LDA 1, V40
        SUBZ# 1,0,SZC       ; carry 1 -> no skip
        LDA 0, V7
        JSR @PSHOW
        LDA 0, V5           ; 18: SUBC with carry 0 base -> base 1, 0
        LDA 1, V5
        MOVZ 1,1
        SUBC 1,0
        JSR @PSHOW
        LDA 0, V5           ; 19: ANDO keeps base carry 1
        LDA 1, V3
        ANDO 1,0
        JSR @PSHOW
        LDA 0, V3           ; 20: MOVL with carry 1 in
        MOVO 0,0
        MOVL 0,0
        JSR @PSHOW
        LDA 0, CHNL
        JSR @POUTC
        LDA 0, CHCR
        JSR @POUTC
        HALT

PSHOW:  DW SHOW
POUTC:  DW OUTC
V1:     DW 1
V3:     DW 3
V5:     DW 5
V7:     DW 7
V40:    DW 0o40
V124:   DW 0o124
VM1:    DW 0o177777
V100K:  DW 0o100000
CHNL:   DW 0o012
CHCR:   DW 0o015

; SHOW: print carry and AC0 as "c:oooooo ".
SHOW:   STA 3, SHRT
        STA 0, SHV
        LDA 0, CH0
        MOV 0,0,SZC
        INC 0,0
        JSR OUTC
        LDA 0, CHCOL
        JSR OUTC
        LDA 1, SHV          ; top bit (LDA leaves carry alone)
        MOVZL 1,1
        LDA 0, ZERO
        MOVL 0,0
        LDA 1, CH0
        ADD 1,0
        JSR OUTC
        LDA 1, SHV          ; five 3-bit groups
        MOVZL 1,1
        STA 1, SHV
        LDA 0, M5
        STA 0, SHC
SHLP:   LDA 1, SHV
        SUB 0,0
        MOVZL 1,1
        MOVL 0,0
        MOVZL 1,1
        MOVL 0,0
        MOVZL 1,1
        MOVL 0,0
        STA 1, SHV
        LDA 1, CH0
        ADD 1,0
        JSR OUTC
        ISZ SHC
        JMP SHLP
        LDA 0, CHSP
        JSR OUTC
        JMP @SHRT

SHRT:   DW 0
SHV:    DW 0
SHC:    DW 0
M5:     DW 0o177773
ZERO:   DW 0
CH0:    DW 0o060
CHCOL:  DW 0o072
CHSP:   DW 0o040

OUTC:   SKPBZ TTO
        JMP OUTC
        DOAS 0, TTO
        JMP 0,3
