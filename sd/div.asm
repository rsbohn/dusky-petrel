; Division subroutine for Nova (working)
; Input:  AC0 = dividend, AC1 = divisor
; Output: AC0 = quotient, AC1 = remainder
; Uses:   AC2 as counter
; Notes:  If divisor is zero, returns quotient 0 and remainder = original AC0.

        ORG 0o200

DIV:    STA AC3, DRET
        STA AC0, DDIV
        MOV AC1, AC1, SNR
        JMP DZDIV
        LDA AC2, 0
DIVL:   SUBZ AC1, AC0, SZC
        JMP DIVD
        INC AC2, AC2
        JMP DIVL
DIVD:   ADD AC1, AC0
        MOV AC0, AC1
        MOV AC2, AC0
        JMP @DRET
DZDIV:  LDA AC0, 0
        LDA AC1, DDIV
        JMP @DRET

DRET:   DW 0
DDIV:   DW 0
