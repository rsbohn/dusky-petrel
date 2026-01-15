; Simple bitmap test - set all bits, clear multiples of 5, print results
; Simplified to work within Nova assembler constraints

        ORG 0o200

START:  JSR @INIT
        JSR @MARK5
        JSR @TESTS
        HALT

; Initialize bitmap to all 1s
INIT:   LDA AC0, BMAP
        LDA AC1, BEND
        LDA AC2, ALL1
INI1:   STA AC2, @AC0
        INC AC0, AC0
        SUBZ# AC1, AC0, SNR
        JMP INI1
        JMP @INIT

; Clear bits for multiples of 5: 15, 25, 35
MARK5:  LDA AC0, N15
        JSR @CLRBIT
        LDA AC0, N25
        JSR @CLRBIT
        JMP @MARK5

; Clear bit for number in AC0
CLRBIT: STA AC0, CNUM
        STA AC3, CRET
        JSR @GETBIT
        ; AC1=word addr, AC2=mask
        LDA AC0, @AC1
        COM AC2, AC2
        AND AC0, AC2
        STA AC0, @AC1
        LDA AC0, CNUM
        JMP @CRET
CNUM:   DW 0
CRET:   DW 0

; Test bit for number in AC0
; Returns AC2=0 if clear, AC2!=0 if set
TSTBIT: STA AC0, TNUM
        STA AC3, TRET
        JSR @GETBIT
        LDA AC0, @AC1
        AND AC2, AC0
        LDA AC0, TNUM
        JMP @TRET
TNUM:   DW 0
TRET:   DW 0

; Get word address and bit mask for number in AC0
; Returns: AC1=word address, AC2=bit mask
GETBIT: STA AC0, GNUM
        STA AC3, GRET
        ; Simplified: just handle numbers 3-35
        ; bit_index = (num - 3) / 2
        SUB AC0, N3
        ; Divide by 2
        LDA AC1, N0
        LDA AC2, N2
GB1:    SUBZ# AC2, AC0, SNC
        JMP GB2
        INC AC1, AC1
        JMP GB1
GB2:    ; AC1 = bit_index
        ; word_addr = BMAP + (bit_index / 16)
        MOV AC1, AC0
        LDA AC1, N0
        LDA AC2, N16
GB3:    SUBZ# AC2, AC0, SNC
        JMP GB4
        INC AC1, AC1
        JMP GB3
GB4:    ; AC1 = word_offset, AC0 = bit_pos
        LDA AC2, BMAP
        ADD AC1, AC2
        ; Make bit mask
        MOV AC0, AC2
        LDA AC0, N1
GB5:    MOV AC2, AC2, SZR
        JMP GB6
        ADD AC0, AC0
        LDA AC1, N1
        SUB AC2, AC1
        JMP GB5
GB6:    MOV AC0, AC2
        LDA AC0, GNUM
        JMP @GRET
GNUM:   DW 0
GRET:   DW 0

; Test and print results
TESTS:  LDA AC2, HDR
        JSR @PRTS
        
        LDA AC0, N3
        JSR @TROW
        LDA AC0, N5
        JSR @TROW
        LDA AC0, N7
        JSR @TROW
        LDA AC0, N9
        JSR @TROW
        LDA AC0, N11
        JSR @TROW
        LDA AC0, N13
        JSR @TROW
        LDA AC0, N15
        JSR @TROW
        LDA AC0, N17
        JSR @TROW
        LDA AC0, N19
        JSR @TROW
        LDA AC0, N21
        JSR @TROW
        LDA AC0, N23
        JSR @TROW
        LDA AC0, N25
        JSR @TROW
        
        JMP @TESTS

; Print one test row
TROW:   STA AC0, RNUM
        STA AC3, RRET
        
        ; Print number (2 octal digits)
        LDA AC0, SPC
        JSR @PUTC
        LDA AC0, RNUM
        LDA AC1, N8
        JSR @DIV
        ; AC0=quot, AC1=rem
        LDA AC2, ZERO
        ADD AC0, AC2
        JSR @PUTC
        LDA AC0, AC1
        LDA AC2, ZERO
        ADD AC0, AC2
        JSR @PUTC
        
        ; Print separator
        LDA AC2, SEP
        JSR @PRTS
        
        ; Test bit
        LDA AC0, RNUM
        JSR @TSTBIT
        MOV AC2, AC2, SZR
        JMP RCMP
        
        LDA AC2, PSTR
        JSR @PRTS
        JMP RDN
        
RCMP:   LDA AC2, CSTR
        JSR @PRTS
        
RDN:    LDA AC2, NL
        JSR @PRTS
        JMP @RRET
RNUM:   DW 0
RRET:   DW 0

; Divide AC0 by AC1, return quot in AC0, rem in AC1
DIV:    STA AC3, DRET
        LDA AC2, N0
DIV1:   SUBZ# AC1, AC0, SNC
        JMP DIV2
        INC AC2, AC2
        JMP DIV1
DIV2:   ADD AC0, AC1
        MOV AC0, AC1
        MOV AC2, AC0
        JMP @DRET
DRET:   DW 0

; Print string at AC2
PRTS:   STA AC3, PRET
PRT1:   LDA AC0, @AC2
        MOV AC0, AC0, SZR
        JMP PRT2
        JSR @PUTC
        INC AC2, AC2
        JMP PRT1
PRT2:   JMP @PRET
PRET:   DW 0

; Print char in AC0
PUTC:   STA AC0, PCH
        STA AC3, PCRT
PC1:    SKPDN TTO
        JMP PC1
        LDA AC0, PCH
        DOA AC0, TTO
        JMP @PCRT
PCH:    DW 0
PCRT:   DW 0

; Constants
N0:     DW 0
N1:     DW 1
N2:     DW 2
N3:     DW 3
N5:     DW 5
N7:     DW 7
N8:     DW 0o10    ; 8 decimal
N9:     DW 0o11    ; 9 decimal
N11:    DW 0o13    ; 11 decimal
N13:    DW 0o15    ; 13 decimal
N15:    DW 0o17    ; 15 decimal
N16:    DW 0o20    ; 16 decimal
N17:    DW 0o21    ; 17 decimal
N19:    DW 0o23    ; 19 decimal
N21:    DW 0o25    ; 21 decimal
N23:    DW 0o27    ; 23 decimal
N25:    DW 0o31    ; 25 decimal
ALL1:   DW -1
SPC:    DW 0o040
ZERO:   DW 0o060

BMAP:   DW MAP
BEND:   DW MAP+3

; Strings
HDR:    DW 0o015, 0o012
        .TXT /Num | Status/
        DW 0o015, 0o012
        .TXT /----+-----------/
        DW 0o015, 0o012, 0
SEP:    .TXT / | /
        DW 0
PSTR:   .TXT /prime    /
        DW 0
CSTR:   .TXT /composite/
        DW 0
NL:     DW 0o015, 0o012, 0

; Bitmap - 3 words for testing (holds 48 bits = numbers 3..99)
MAP:    DW 0, 0, 0
