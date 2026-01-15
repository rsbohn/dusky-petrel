; Minimal bitmap test
; Test bitmap storage by setting all bits, clearing bit 6 (for 15), printing results

        ORG 0o400

START:  JSR INIT
        JSR CLBIT
        JSR PRINT
        HALT

; Set first word to all 1s
INIT:   LDA AC0, P:ALLF
        STA AC0, P:WORD0
        JMP @INIT

; Clear bit 6 (represents number 15: (15-3)/2 = 6)
CLBIT:  LDA AC0, P:WORD0
        LDA AC1, P:MASK6    ; Bit 6 mask = 0o100 (64)
        COM AC1, AC1        ; Invert mask
        AND AC0, AC1        ; Clear bit
        STA AC0, P:WORD0
        JMP @CLBIT

; Print results
PRINT:  LDA AC2, P:HDR
        JSR PRTS
        ; Show bits for numbers 3, 5, 7, 9, 11, 13, 15, 17, 19
        LDA AC0, 3
        LDA AC1, P:BIT0
        JSR PROW
        LDA AC0, 5
        LDA AC1, P:BIT1
        JSR PROW
        LDA AC0, 7
        LDA AC1, P:BIT2
        JSR PROW
        LDA AC0, 0o11     ; 9
        LDA AC1, P:BIT3
        JSR PROW
        LDA AC0, 0o13     ; 11
        LDA AC1, P:BIT4
        JSR PROW
        LDA AC0, 0o15     ; 13
        LDA AC1, P:BIT5
        JSR PROW
        LDA AC0, 0o17     ; 15
        LDA AC1, P:BIT6
        JSR PROW
        LDA AC0, 0o21     ; 17
        LDA AC1, P:BIT7
        JSR PROW
        LDA AC0, 0o23     ; 19
        LDA AC1, P:BIT8
        JSR PROW
        JMP @PRINT

; Print one row: AC0=number, AC1=bit mask
PROW:   STA AC0, P:PNUM
        STA AC1, P:PMASK
        STA AC3, P:PRET
        ; Print number (octal)
        LDA AC0, P:SPC
        JSR PUTC
        LDA AC0, P:PNUM
        LDA AC1, P:V8
        JSR DIV
        LDA AC2, P:ZERO
        ADD AC0, AC2
        JSR PUTC
        LDA AC0, AC1
        LDA AC2, P:ZERO
        ADD AC0, AC2
        JSR PUTC
        ; Print sep
        LDA AC2, P:SEP
        JSR PRTS
        ; Test bit
        LDA AC0, P:WORD0
        LDA AC1, P:PMASK
        AND AC0, AC1
        MOV AC0, AC0, SZR
        JMP PCMP
        LDA AC2, P:PSTR
        JSR PRTS
        JMP PDN
PCMP:   LDA AC2, P:CSTR
        JSR PRTS
PDN:    LDA AC2, P:NL
        JSR PRTS
        JMP @P:PRET

; Divide AC0 by AC1 -> AC0=quot, AC1=rem
DIV:    STA AC3, P:DRET
        LDA AC2, 0
DIVL:   SUBZ# AC1, AC0, SNC
        JMP DIVD
        INC AC2, AC2
        JMP DIVL
DIVD:   ADD AC0, AC1
        MOV AC0, AC1
        MOV AC2, AC0
        JMP @P:DRET

; Print string at AC2
PRTS:   STA AC3, P:SRET
PRTL:   LDA AC0, @AC2
        MOV AC0, AC0, SZR
        JMP PRTD
        JSR PUTC
        INC AC2, AC2
        JMP PRTL
PRTD:   JMP @P:SRET

; Put char in AC0
PUTC:   STA AC0, P:PCH
        STA AC3, P:CRET
PUTW:   SKPDN TTO
        JMP PUTW
        LDA AC0, P:PCH
        DOA AC0, TTO
        JMP @P:CRET

; Data in same page
DRET:   DW 0
SRET:   DW 0
CRET:   DW 0
PRET:   DW 0
PCH:    DW 0
PNUM:   DW 0
PMASK:  DW 0

V8:     DW 0o10   ; 8
SPC:    DW 0o040
ZERO:   DW 0o060
ALLF:   DW -1

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

MASK6:  DW 0o100  ; Mask for bit 6

WORD0:  DW 0      ; First word of bitmap

HDR:    DW 0o015, 0o012
        .TXT /Num | Status/
        DW 0o015, 0o012, 0
SEP:    .TXT / | /
        DW 0
PSTR:   .TXT /prime    /
        DW 0
CSTR:   .TXT /composite/
        DW 0
NL:     DW 0o015, 0o012, 0
