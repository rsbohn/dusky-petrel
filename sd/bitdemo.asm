; Simple bitmap test - compact version that fits in one page
; Tests bitmap storage for Sieve of Eratosthenes
; Sets all bits to 1, clears bits for 15 and 25, then prints test results

        ORG 0o300

; Entry point
START:  JSR INIT
        JSR MARK
        JSR TEST
        HALT

; Init bitmap to all 1s
INIT:   LDA AC0, MAP
        LDA AC1, -1
        STA AC1, @AC0
        INC AC0, AC0
        STA AC1, @AC0
        INC AC0, AC0
        STA AC1, @AC0
        JMP @INIT

; Clear bits for 15 and 25
MARK:   LDA AC0, BIT15
        JSR CLRB
        LDA AC0, BIT25
        JSR CLRB
        JMP @MARK

; Clear bit - AC0 has word+bit info
; Low byte = bit position, high byte = word offset
CLRB:   STA AC3, RET1
        ; Extract word offset (divide by 256)
        MOV AC0, AC1
        SHRL AC1, 8
        LDA AC2, MAP
        ADD AC1, AC2        ; AC1 = word address
        ; Extract bit position (mod 256)
        LDA AC2, 0o377
        AND AC0, AC2        ; AC2 = bit position
        ; Make mask
        LDA AC2, 1
CLRL:   MOV AC0, AC0, SZR
        JMP CLRD
        ADD AC2, AC2
        LDA AC1, 1
        SUB AC0, AC1
        JMP CLRL
CLRD:   ; Clear the bit
        COM AC2, AC2
        LDA AC1, MAP
        ; Assume word 0 for now (simplified)
        LDA AC0, @AC1
        AND AC0, AC2
        STA AC0, @AC1
        JMP @RET1

; Test values and print
TEST:   LDA AC2, HDR
        JSR PRTS
        ; Test a few values
        LDA AC0, 3
        JSR ROW
        LDA AC0, 5
        JSR ROW
        LDA AC0, 7
        JSR ROW
        LDA AC0, 0o11     ; 9
        JSR ROW
        LDA AC0, 0o13     ; 11
        JSR ROW
        LDA AC0, 0o15     ; 13
        JSR ROW
        LDA AC0, 0o17     ; 15
        JSR ROW
        LDA AC0, 0o21     ; 17
        JSR ROW
        LDA AC0, 0o23     ; 19
        JSR ROW
        LDA AC0, 0o25     ; 21
        JSR ROW
        LDA AC0, 0o27     ; 23
        JSR ROW
        LDA AC0, 0o31     ; 25
        JSR ROW
        JMP @TEST

; Print one row - number in AC0
ROW:    STA AC0, NUM
        STA AC3, RET2
        ; Print number
        LDA AC0, 0o040
        JSR PUTC
        LDA AC0, NUM
        LDA AC1, 0o10     ; 8
        JSR DIVV
        LDA AC2, 0o060
        ADD AC0, AC2
        JSR PUTC
        LDA AC0, AC1
        LDA AC2, 0o060
        ADD AC0, AC2
        JSR PUTC
        ; Sep
        LDA AC2, SEP
        JSR PRTS
        ; Test bit (simplified - just show first word)
        LDA AC0, NUM
        SUB AC0, 3
        ; Check if bit is set
        LDA AC1, MAP
        LDA AC2, @AC1
        LDA AC1, 1
ROTL:   MOV AC0, AC0, SZR
        JMP ROTD
        ADD AC1, AC1
        LDA AC3, 1
        SUB AC0, AC3
        JMP ROTL
ROTD:   AND AC1, AC2
        MOV AC1, AC1, SZR
        JMP COMP
        LDA AC2, PRIM
        JSR PRTS
        JMP RODN
COMP:   LDA AC2, CMPS
        JSR PRTS
RODN:   LDA AC2, CRLF
        JSR PRTS
        JMP @RET2

; Divide AC0 by AC1 -> AC0=quot, AC1=rem
DIVV:   STA AC3, RET3
        LDA AC2, 0
DIVL:   SUBZ# AC1, AC0, SNC
        JMP DIVD
        INC AC2, AC2
        JMP DIVL
DIVD:   ADD AC0, AC1
        MOV AC0, AC1
        MOV AC2, AC0
        JMP @RET3

; Print string at AC2
PRTS:   STA AC3, RET4
PRTL:   LDA AC0, @AC2
        MOV AC0, AC0, SZR
        JMP PRTD
        JSR PUTC
        INC AC2, AC2
        JMP PRTL
PRTD:   JMP @RET4

; Put char in AC0
PUTC:   STA AC0, CH
        STA AC3, RET5
PUTW:   SKPDN TTO
        JMP PUTW
        LDA AC0, CH
        DOA AC0, TTO
        JMP @RET5

; Data
RET1:   DW 0
RET2:   DW 0
RET3:   DW 0
RET4:   DW 0
RET5:   DW 0
NUM:    DW 0
CH:     DW 0

; Bit encodings: word_offset*256 + bit_position
; bit_pos = (num-3)/2 % 16, word_offset = (num-3)/2 / 16
BIT15:  DW 6    ; (15-3)/2 = 6
BIT25:  DW 0o13 ; (25-3)/2 = 11

MAP:    DW MAPP
HDR:    DW 0o015, 0o012
        .TXT /Num | Status/
        DW 0o015, 0o012, 0
SEP:    .TXT / | /
        DW 0
PRIM:   .TXT /prime    /
        DW 0
CMPS:   .TXT /composite/
        DW 0
CRLF:   DW 0o015, 0o012, 0

        ORG 0o700
MAPP:   DW 0, 0, 0
