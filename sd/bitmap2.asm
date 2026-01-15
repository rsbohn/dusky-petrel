; Minimal bitmap test - all in zero page
; Test: Mark odd multiples of five in bitmap, print status for 3-19

        ORG 0

; Entry point at 0o200
        ORG 0o200

START:  JSR INIT
        JSR PRINT
        HALT

; Set WORD0 bits for odd multiples of five (5 and 15)
INIT:   LDA AC0, MFIVE
        STA AC0, WORD0
        JMP 0, AC3

; Print results table
PRINT:  STA AC3, PRTRET
        LDA AC2, HDRP
        JSR PRTS
        
        LDA AC0, N3
        LDA AC1, BIT0
        JSR PROW
        
        LDA AC0, N5
        LDA AC1, BIT1
        JSR PROW
        
        LDA AC0, N7
        LDA AC1, BIT2
        JSR PROW
        
        LDA AC0, N9
        LDA AC1, BIT3
        JSR PROW
        
        LDA AC0, N11
        LDA AC1, BIT4
        JSR PROW
        
        LDA AC0, N13
        LDA AC1, BIT5
        JSR PROW
        
        LDA AC0, N15
        LDA AC1, BIT6
        JSR PROW
        
        LDA AC0, N17
        LDA AC1, BIT7
        JSR PROW
        
        LDA AC0, N19
        LDA AC1, BIT8
        JSR PROW
        
        JMP @PRTRET

; Print one row: AC0=number, AC1=bit mask
PROW:   STA AC0, PNUM
        STA AC1, PMASK
        STA AC3, PRET
        
        ; Print number in octal
        LDA AC0, SPC
        JSR PUTC
        LDA AC0, PNUM
        LDA AC1, V8
        JSR DIV
        STA AC1, PNUM      ; Save remainder
        LDA AC2, ZERO
        ADD AC2, AC0
        JSR PUTC
        LDA AC0, PNUM      ; Get remainder
        LDA AC2, ZERO
        ADD AC2, AC0
        JSR PUTC
        
        ; Print separator
        LDA AC2, SEPP
        JSR PRTS
        
        ; Test bit in WORD0
        LDA AC0, WORD0
        LDA AC1, PMASK
        AND AC1, AC0
        MOV AC0, AC0, SNR
        JMP PCMP
        
        ; Multiple of five
        LDA AC2, PSTRP
        JSR PRTS
        JMP PDN
        
PCMP:   ; Not a multiple of five
        LDA AC2, CSTRP
        JSR PRTS
        
PDN:    LDA AC2, NLP
        JSR PRTS
        JMP @PRET

; Divide AC0 by AC1, return quotient in AC0, remainder in AC1
; If divisor is zero, return quotient 0 and remainder = original AC0.
DIV:    STA AC3, DRET
        STA AC0, DDIV
        MOV AC1, AC1, SNR
        JMP DZDIV
        LDA AC2, ZW
DIVL:   SUBZ AC1, AC0, SZC
        JMP DIVD
        INC AC2, AC2
        JMP DIVL
DIVD:   ADD AC1, AC0
        MOV AC0, AC1
        MOV AC2, AC0
        JMP @DRET
DZDIV:  LDA AC0, ZW
        LDA AC1, DDIV
        JMP @DRET

; Print string at AC2 (zero-terminated)
PRTS:   STA AC3, SRET
PRTL:   LDA AC0, 0, AC2
        MOV AC0, AC0, SNR
        JMP PRTD
        JSR PUTC
        INC AC2, AC2
        JMP PRTL
PRTD:   JMP @SRET

; Put character in AC0 to TTO
PUTC:   STA AC0, PCH
        STA AC3, CRET
PUTW:   SKPDN TTO
        JMP PUTW
        LDA AC0, PCH
        DOA AC0, TTO
        JMP @CRET

; Data area in zero page
        ORG 0o0

DRET:   DW 0
DDIV:   DW 0
SRET:   DW 0
CRET:   DW 0
PRET:   DW 0
PRTRET: DW 0
PCH:    DW 0
PNUM:   DW 0
PMASK:  DW 0

V8:     DW 0o10   ; 8 decimal
SPC:    DW 0o040  ; space
ZERO:   DW 0o060  ; '0'
MFIVE:  DW 0o102  ; bits for 5 (bit1) and 15 (bit6)
ZW:     DW 0      ; constant zero

N3:     DW 3
N5:     DW 5
N7:     DW 7
N9:     DW 0o11   ; 9
N11:    DW 0o13   ; 11
N13:    DW 0o15   ; 13
N15:    DW 0o17   ; 15
N17:    DW 0o21   ; 17
N19:    DW 0o23   ; 19

; Bit masks for positions 0-8
BIT0:   DW 1
BIT1:   DW 2
BIT2:   DW 4
BIT3:   DW 0o10
BIT4:   DW 0o20
BIT5:   DW 0o40
BIT6:   DW 0o100
BIT7:   DW 0o200
BIT8:   DW 0o400

WORD0:  DW 0      ; first bitmap word

HDR:    DW 0o015, 0o012
        .TXT /Num | Status/
        DW 0o015, 0o012, 0

SEP:    .TXT / | /
        DW 0

PSTR:   .TXT /multiple /
        DW 0

CSTR:   .TXT /not      /
        DW 0

NL:     DW 0o015, 0o012, 0

HDRP:   DW HDR
SEPP:   DW SEP
PSTRP:  DW PSTR
CSTRP:  DW CSTR
NLP:    DW NL
