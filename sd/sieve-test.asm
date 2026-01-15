; Test bitmap storage for Sieve of Eratosthenes
; Stores only odd numbers: bit 0 = 3, bit 1 = 5, bit 2 = 7, etc.
; Test: Set all bits to 1, then clear multiples of 5

        ORG 0o200

START:  JSR @SETMAP         ; Set bitmap to all 1s (all prime initially)
        JSR @MARK5          ; Clear all multiples of 5
        JSR @SAMPLE         ; Test sample values
        HALT

; Set the bitmap - set all bits to 1 (assume prime)
SETMAP: LDA AC0, MAPSTART
        LDA AC1, MAPEND
        LDA AC2, ALLONE
SET1:   STA AC2, 0,AC0
        INC AC0, AC0
        SUBZ# AC1, AC0, SNR
        JMP SET1
        JMP @SETMAP

; Mark all odd multiples of 5 as composite (clear bits)
; Marks 15, 25, 35, 45, ... (5 is prime, so start at 15=5*3)
MARK5:  STA AC3, M5RET
        LDA AC0, V15        ; Start at 15
M5LP:   LDA AC1, V9999
        SUBZ# AC1, AC0, SZR
        JMP M5DN
        JSR @CLRBIT
        LDA AC1, V10
        ADD AC0, AC1
        JMP M5LP
M5DN:   JMP @M5RET
M5RET:  DW 0

; Clear bit for number in AC0 (mark as composite)
CLRBIT: STA AC0, CBNUM
        STA AC3, CBRET
        JSR @GETBIT
        LDA AC0, 0,AC1      ; Load word from address in AC1
        COM AC2, AC2        ; Invert mask
        AND AC0, AC2        ; Clear the bit
        STA AC0, 0,AC1      ; Store back
        LDA AC0, CBNUM
        JMP @CBRET
CBNUM:  DW 0
CBRET:  DW 0

; Test bit for number in AC0
; Output: AC2 = 0 if composite, AC2 != 0 if prime
TSTBIT: STA AC0, TBNUM
        STA AC3, TBRET
        JSR @GETBIT
        LDA AC0, 0,AC1      ; Load word
        AND AC2, AC0        ; Test bit
        LDA AC0, TBNUM
        JMP @TBRET
TBNUM:  DW 0
TBRET:  DW 0

; Convert number to bitmap word address and bit mask
; Input: AC0 = odd number (3, 5, 7, ...)
; Output: AC1 = word address, AC2 = bit mask
GETBIT: STA AC0, GBNUM
        STA AC3, GBRET
        
        ; bit_index = (num - 3) / 2
        LDA AC1, V3
        SUB AC0, AC1        ; AC0 = num - 3
        JSR @DIV2           ; AC0 = bit_index
        
        ; word_offset = bit_index / 16, bit_pos = bit_index % 16
        STA AC0, GBIDX
        JSR @DIV16
        ; AC0 = word_offset, AC1 = remainder
        
        ; word_addr = BITMAP + word_offset
        LDA AC2, MAPSTART
        ADD AC0, AC2
        MOV AC0, AC1        ; AC1 = word address
        
        ; Create bit mask from bit position
        LDA AC0, GBIDX
        LDA AC2, V15
        AND AC0, AC2        ; AC0 = bit_pos (mod 16)
        JSR @MKMASK
        
        LDA AC0, GBNUM
        JMP @GBRET
GBNUM:  DW 0
GBIDX:  DW 0
GBRET:  DW 0

; Divide AC0 by 2 (integer division)
DIV2:   STA AC3, D2RET
        LDA AC1, V1
        SUBZ# AC1, AC0, SZR ; Odd?
        SUB AC0, AC1        ; Make even if odd
        ; Now divide by 2 by repeated subtraction
        LDA AC1, V0         ; Result
        LDA AC2, V2
D2LP:   SUBZ# AC2, AC0, SNC
        JMP D2DN
        INC AC1, AC1
        JMP D2LP
D2DN:   MOV AC1, AC0
        JMP @D2RET
D2RET:  DW 0

; Divide AC0 by 16, return quotient in AC0, remainder in AC1
DIV16:  STA AC3, D16RET
        LDA AC1, V0         ; Quotient
        LDA AC2, V16
D16LP:  SUBZ# AC2, AC0, SNC
        JMP D16DN
        INC AC1, AC1
        JMP D16LP
D16DN:  ; AC0 = remainder, AC1 = quotient
        MOV AC0, AC2        ; Save remainder
        MOV AC1, AC0        ; AC0 = quotient
        MOV AC2, AC1        ; AC1 = remainder
        JMP @D16RET
D16RET: DW 0

; Create bit mask from bit position
; Input: AC0 = bit position (0-15)
; Output: AC2 = bit mask
MKMASK: STA AC3, MKRET
        LDA AC2, V1
        MOV AC0, AC0, SZR
        JMP MKDN
MKLP:   ADD AC2, AC2        ; Shift left
        LDA AC1, V1
        SUB AC0, AC1
        MOV AC0, AC0, SNR
        JMP MKLP
MKDN:   JMP @MKRET
MKRET:  DW 0

; Print test table
SAMPLE: STA AC3, SMPRET
        
        ; Print header
        LDA AC2, HDR
        JSR @PRTSTR
        
        ; Test specific values
        LDA AC0, V3
        JSR @PRTROW
        LDA AC0, V5
        JSR @PRTROW
        LDA AC0, V7
        JSR @PRTROW
        LDA AC0, V9
        JSR @PRTROW
        LDA AC0, V11
        JSR @PRTROW
        LDA AC0, V13
        JSR @PRTROW
        LDA AC0, V15
        JSR @PRTROW
        LDA AC0, V17
        JSR @PRTROW
        LDA AC0, V19
        JSR @PRTROW
        LDA AC0, V21
        JSR @PRTROW
        LDA AC0, V23
        JSR @PRTROW
        LDA AC0, V25
        JSR @PRTROW
        
        JMP @SMPRET
SMPRET: DW 0

; Print one row: number and status
PRTROW: STA AC0, PRNUM
        STA AC3, PRRET
        
        JSR @PRTOCT
        
        LDA AC2, SEP
        JSR @PRTSTR
        
        LDA AC0, PRNUM
        JSR @TSTBIT
        MOV AC2, AC2, SZR
        JMP PRCMP
        
        LDA AC2, PRSTR
        JSR @PRTSTR
        JMP PRDN
        
PRCMP:  LDA AC2, CPSTR
        JSR @PRTSTR
        
PRDN:   LDA AC2, CRLF
        JSR @PRTSTR
        JMP @PRRET
PRNUM:  DW 0
PRRET:  DW 0

; Print octal number in AC0 (5 digits with leading space)
PRTOCT: STA AC0, PONUM
        STA AC3, PORET
        
        LDA AC0, SPACE
        JSR @PUTCH
        
        ; Extract digits (simplified - just show 2 digits)
        LDA AC0, PONUM
        LDA AC1, V8
        JSR @DIVMOD
        ; AC0 = quotient, AC1 = remainder
        LDA AC2, ZERO
        ADD AC0, AC2
        JSR @PUTCH
        
        LDA AC0, AC1
        LDA AC2, ZERO
        ADD AC0, AC2
        JSR @PUTCH
        
        JMP @PORET
PONUM:  DW 0
PORET:  DW 0

; Divide AC0 by AC1, return quotient in AC0, remainder in AC1
DIVMOD: STA AC3, DMRET
        LDA AC2, V0         ; Quotient
DMLP:   SUBZ# AC1, AC0, SNC
        JMP DMDN
        INC AC2, AC2
        JMP DMLP
DMDN:   ADD AC0, AC1        ; Restore remainder
        MOV AC0, AC1        ; AC1 = remainder
        MOV AC2, AC0        ; AC0 = quotient
        JMP @DMRET
DMRET:  DW 0

; Print string pointed to by AC2 (zero-terminated)
PRTSTR: STA AC3, PSRET
PSLP:   LDA AC0, 0,AC2
        MOV AC0, AC0, SZR
        JMP PSDN
        JSR @PUTCH
        INC AC2, AC2
        JMP PSLP
PSDN:   JMP @PSRET
PSRET:  DW 0

; Output character in AC0
PUTCH:  STA AC0, PCCH
        STA AC3, PCRET
PCWT:   SKPDN TTO
        JMP PCWT
        LDA AC0, PCCH
        DOA AC0, TTO
        JMP @PCRET
PCCH:   DW 0
PCRET:  DW 0

; Constants
V0:     DW 0
V1:     DW 1
V2:     DW 2
V3:     DW 3
V5:     DW 5
V7:     DW 7
V8:     DW 8
V9:     DW 9
V10:    DW 10
V11:    DW 11
V13:    DW 13
V15:    DW 15
V16:    DW 16
V17:    DW 17
V19:    DW 19
V21:    DW 21
V23:    DW 23
V25:    DW 25
V9999:  DW 9999
ALLONE: DW -1

MAPSTART: DW BITMAP
MAPEND:   DW BITMAP+20      ; Just use 20 words for testing

SPACE:  DW 0o040
ZERO:   DW 0o060

; Strings
HDR:    DW 0o015, 0o012
        .TXT /Num | Status/
        DW 0o015, 0o012
        .TXT /----+-----------/
        DW 0o015, 0o012, 0
SEP:    .TXT / | /
        DW 0
PRSTR:  .TXT /prime    /
        DW 0
CPSTR:  .TXT /composite/
        DW 0
CRLF:   DW 0o015, 0o012, 0

; Bitmap storage - start small for testing
        ORG 0o2000
BITMAP: BSS 20
