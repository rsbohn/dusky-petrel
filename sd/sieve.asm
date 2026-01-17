; Sieve of Eratosthenes - bitmap for odd numbers 3..9999
; Stores only odd numbers: bit 0 = 3, bit 1 = 5, bit 2 = 7, etc.
; 5000 odd numbers / 16 bits = 313 words (rounded up)
; Bit = 1 means prime, bit = 0 means composite (for easy clearing)

        ORG 0o200

START:  JSR SETMAP          ; Set bitmap to all 1s (all prime initially)
        JSR SIEVE           ; Clear composites for all primes
        JSR SAMPLE          ; Test sample values
        HALT

; Set the bitmap - set all bits to 1 (assume prime)
SETMAP: STA AC3, SM_RET
        LDA AC2, BMPTR      ; Start address
        LDA AC1, MAPCOUNT   ; Word count
        STA AC1, SM_CNT
SET1:   LDA AC0, ALLONE     ; -1 = all bits set
        STA AC0, 0, AC2     ; Store all 1s
        INC AC2, AC2        ; Next word
        DSZ SM_CNT
        JMP SET1
        JMP @SM_RET

; Sieve of Eratosthenes for odd numbers up to 9999
; Uses bitmap for odd numbers: bit 0 = 3, bit 1 = 5, ...
SIEVE:  STA AC3, SV_RET
        LDA AC0, THREE
        STA AC0, SV_P

SV_PLP: LDA AC0, SV_P
        LDA AC1, V100
        SUBZ AC1, AC0, SNC  ; if p >= 100, done (sqrt(9999) < 100)
        JMP SV_DN

        LDA AC0, SV_P
        JSR TSTBIT
        MOV AC1, AC1, SNR   ; bit set => prime
        JMP SV_NP

        ; step = 2*p
        LDA AC0, SV_P
        ADDZ AC0, AC0
        STA AC0, SV_STEP

        ; m = p*p
        LDA AC0, SV_P
        LDA AC1, SV_P
        JSR MUL
        STA AC0, SV_M

SV_MLP: LDA AC0, SV_M
        LDA AC1, V10000
        SUBZ AC1, AC0, SNC  ; if m >= 10000, exit loop
        JMP SV_MDN
        LDA AC0, SV_M
        JSR CLRBIT
        LDA AC0, SV_M
        LDA AC1, SV_STEP
        ADDZ AC1, AC0
        STA AC0, SV_M
        JMP SV_MLP

SV_MDN: ; next p
SV_NP:  LDA AC0, SV_P
        LDA AC1, TWO
        ADDZ AC1, AC0
        STA AC0, SV_P
        JMP SV_PLP

SV_DN:  JMP @SV_RET

; Multiply AC0 by AC1, return product in AC0
MUL:    STA AC3, M_RET
        STA AC0, M_A
        STA AC1, M_B
        LDA AC2, ZW         ; Result = 0
        LDA AC1, M_B
        MOV AC1, AC1, SNR   ; Multiplier zero?
        JMP M_DN
        STA AC1, M_CNT
M_LP:   LDA AC0, M_A
        ADDZ AC0, AC2
        DSZ M_CNT
        JMP M_LP
M_DN:   MOV AC2, AC0
        JMP @M_RET

; Clear bit for number in AC0 (mark as composite)
; Input: AC0 = odd number
CLRBIT: STA AC0, CB_NUM     ; Save number
        STA AC3, CB_RET     ; Save return
        JSR GETBIT          ; Get word/bit position
        ; AC2 = word address, AC1 = bit mask
        LDA AC0, 0, AC2     ; Load word
        COM AC1, AC1        ; Invert mask
        AND AC1, AC0        ; Clear the bit
        STA AC0, 0, AC2     ; Store back
        LDA AC0, CB_NUM     ; Restore number
        JMP @CB_RET

; Test bit for number in AC0
; Input: AC0 = odd number
; Output: AC1 = 0 if composite (bit clear), AC1 != 0 if prime (bit set)
TSTBIT: STA AC0, TB_NUM     ; Save number
        STA AC3, TB_RET     ; Save return
        JSR GETBIT          ; Get word/bit position
        ; AC2 = word address, AC1 = bit mask
        LDA AC0, 0, AC2     ; Load word
        AND AC0, AC1        ; Test the bit (result in AC1)
        LDA AC0, TB_NUM     ; Restore number
        JMP @TB_RET

; Convert number in AC0 to bitmap word address and bit mask
; Input: AC0 = odd number (3, 5, 7, ...)
; Output: AC2 = word address, AC1 = bit mask
; Formula: bit_index = (num - 3) / 2
;          word_addr = BITMAP + (bit_index / 16)
;          bit_pos = bit_index % 16
GETBIT: STA AC0, GB_NUM     ; Save original number
        STA AC3, GB_RET     ; Save return address
        
        ; Calculate bit index = (num - 3) / 2
        LDA AC1, THREE
        SUBZ AC1, AC0       ; AC0 = num - 3
        LDA AC1, TWO
        JSR DIV             ; AC0 = bit_index
        
        ; Divide bit_index by 16 to get word offset/bit position
        LDA AC1, SIXTEEN
        JSR DIV             ; AC0 = word_offset, AC1 = bit_pos
        STA AC1, GB_BIT
        
        ; Calculate word address
        LDA AC2, BMPTR
        ADDZ AC2, AC0        ; AC0 = BITMAP + word_offset
        MOV AC0, AC2        ; AC2 = word address
        STA AC2, GB_WORD
        
        ; Create bit mask from bit position
        LDA AC0, GB_BIT
        JSR MKMASK          ; AC1 = bit mask
        LDA AC2, GB_WORD
        
        LDA AC0, GB_NUM     ; Restore number
        JMP @GB_RET

; Create bit mask from bit position
; Input: AC0 = bit position (0-15)
; Output: AC1 = bit mask (1 << bit_pos)
MKMASK: STA AC3, MK_RET
        LDA AC2, MASKPTR
        ADDZ AC0, AC2       ; AC2 = MASKTAB + bit_pos
        LDA AC1, 0, AC2
        JMP @MK_RET

; Sample test - check specific values and print table
SAMPLE: STA AC3, SMP_RET
        
        ; Print header
        LDA AC2, HDR1P
        JSR PRTSTR
        LDA AC2, HDR2P
        JSR PRTSTR
        
        ; Test values: 3, 5, 7, 9, 11, 13, 15, 17, 19, 21, 23, 25
        LDA AC0, N3
        JSR PRTROW
        LDA AC0, N5
        JSR PRTROW
        LDA AC0, N7
        JSR PRTROW
        LDA AC0, N9
        JSR PRTROW
        LDA AC0, N11
        JSR PRTROW
        LDA AC0, N13
        JSR PRTROW
        LDA AC0, N15
        JSR PRTROW
        LDA AC0, N17
        JSR PRTROW
        LDA AC0, N19
        JSR PRTROW
        LDA AC0, N21
        JSR PRTROW
        LDA AC0, N23
        JSR PRTROW
        LDA AC0, N25
        JSR PRTROW
        
        JMP @SMP_RET

; Print one row: number and prime status
; Input: AC0 = number
PRTROW: STA AC0, PR_NUM
        STA AC3, PR_RET
        
        ; Print number
        JSR PRTDEC
        
        ; Print separator
        LDA AC2, SEPP
        JSR PRTSTR
        
        ; Test if prime
        LDA AC0, PR_NUM
        JSR TSTBIT
        MOV AC1, AC1, SNR   ; Bit clear = composite
        JMP PR_CMP
        
        ; Prime
        LDA AC2, PRSTRP
        JSR PRTSTR
        JMP PR_DN
        
PR_CMP: ; Composite
        LDA AC2, CPSTRP
        JSR PRTSTR
        
PR_DN:  LDA AC2, CRLFP
        JSR PRTSTR
        JMP @PR_RET

; Print number in AC0 (decimal)
PRTDEC: STA AC0, PD_NUM
        STA AC3, PD_RET

        ; Print leading space, then 5 decimal digits (00000-09999)
        LDA AC0, SPACE
        JSR PUTCH
        LDA AC0, PD_NUM
        LDA AC1, TEN
        JSR DIV
        STA AC1, PD_D0
        LDA AC1, TEN
        JSR DIV
        STA AC1, PD_D1
        LDA AC1, TEN
        JSR DIV
        STA AC1, PD_D2
        LDA AC1, TEN
        JSR DIV
        STA AC1, PD_D3
        STA AC0, PD_D4

        LDA AC0, PD_D4
        LDA AC2, ZERO
        ADDZ AC2, AC0
        JSR PUTCH
        LDA AC0, PD_D3
        LDA AC2, ZERO
        ADDZ AC2, AC0
        JSR PUTCH
        LDA AC0, PD_D2
        LDA AC2, ZERO
        ADDZ AC2, AC0
        JSR PUTCH
        LDA AC0, PD_D1
        LDA AC2, ZERO
        ADDZ AC2, AC0
        JSR PUTCH
        LDA AC0, PD_D0
        LDA AC2, ZERO
        ADDZ AC2, AC0
        JSR PUTCH

        JMP @PD_RET

; Divide AC0 by AC1, return quotient in AC0, remainder in AC1
DIV:    STA AC3, D_RET
        STA AC0, DDIV
        MOV AC1, AC1, SNR   ; Divisor zero?
        JMP DZDIV
        LDA AC2, ZW         ; Quotient
DIV_LP: SUBZ AC1, AC0, SZC  ; Can subtract?
        JMP DIV_DN
        INC AC2, AC2
        JMP DIV_LP
DIV_DN: ADDZ AC1, AC0        ; Restore remainder
        MOV AC0, AC1        ; AC1 = remainder
        MOV AC2, AC0        ; AC0 = quotient
        JMP @D_RET
DZDIV:  LDA AC0, ZW
        LDA AC1, DDIV
        JMP @D_RET

; Print string pointed to by AC2 (zero-terminated)
PRTSTR: STA AC3, PS_RET
PS_LP:  LDA AC0, 0, AC2
        MOV AC0, AC0, SNR   ; Zero?
        JMP PS_DN
        JSR PUTCH
        INC AC2, AC2
        JMP PS_LP
PS_DN:  JMP @PS_RET

; Output character in AC0
PUTCH:  STA AC0, PC_CH
        STA AC3, PC_RET
PC_WT:  SKPDN TTO
        JMP PC_WT
        LDA AC0, PC_CH
        DOA AC0, TTO
        JMP @PC_RET

; Write bitmap to tape unit 0
; Format: 313 words of bitmap data
WRITETC:STA AC3, WTC_RET    ; Save return address
        
        ; Initialize tape write (device 16, 0o20)
        NIOC AC0, 16        ; Reset tape controller
        LDA AC0, TCWRITE    ; Write command
        DOC AC0, 16         ; Issue command
        
        ; Write bitmap words
        LDA AC2, BMPTR      ; Start address
        LDA AC1, MAPCOUNT
        STA AC1, WTC_CNT
        
WTC1:   LDA AC0, 0, AC2     ; Load bitmap word
        DOAS AC0, 16        ; Write to tape
WTCW:   SKPDN 16            ; Wait for ready
        JMP WTCW
        INC AC2, AC2        ; Next word
        DSZ WTC_CNT
        JMP WTC1
        
        ; Finish tape operation
        NIOC AC0, 16        ; Stop tape
        JMP @WTC_RET

; Strings
        ORG 0o1200
HDR1:    .TXT /Number Status/
         DW 0o015, 0o012, 0
HDR2:    .TXT /-------------------------/
         DW 0o015, 0o012, 0
SEP:     .TXT / | /
         DW 0
PRSTR:   .TXT /prime     /
         DW 0
CPSTR:   .TXT /composite/
         DW 0
CRLF:    DW 0o015, 0o012, 0

        ORG 0o40
SM_CNT: DW 0
SM_RET: DW 0
CB_NUM: DW 0
CB_RET: DW 0
TB_NUM: DW 0
TB_RET: DW 0
GB_NUM: DW 0
GB_BIT: DW 0
GB_WORD: DW 0
GB_RET: DW 0
MK_RET: DW 0
SMP_RET: DW 0
PR_NUM: DW 0
PR_RET: DW 0
PD_NUM: DW 0
PD_RET: DW 0
PD_D0:  DW 0
PD_D1:  DW 0
PD_D2:  DW 0
PD_D3:  DW 0
PD_D4:  DW 0
D_RET:  DW 0
DDIV:   DW 0
PS_RET: DW 0
PC_CH:  DW 0
PC_RET: DW 0
WTC_CNT: DW 0
WTC_RET: DW 0
SV_P:   DW 0
SV_STEP: DW 0
SV_M:   DW 0
SV_RET: DW 0
M_RET:  DW 0
M_A:    DW 0
M_B:    DW 0
M_CNT:  DW 0

ALLONE:  DW -1              ; All bits set (177777 octal)
MAPCOUNT: DW 0o471          ; 313
BMPTR:   DW BITMAP
SPACE:   DW 0o040           ; Space character
ZERO:    DW 0o060           ; '0' character
TEN:     DW 0o12            ; 10
ZW:      DW 0
ONE:     DW 1
TWO:     DW 2
THREE:   DW 3
SIXTEEN: DW 0o20            ; 16
V100:    DW 0o144           ; 100
V10000:  DW 0o23420         ; 10000
TCWRITE: DW 0o4             ; 4

; Bit mask table for positions 0-15
MASKPTR: DW MASKTAB
MASKTAB: DW 1
        DW 2
        DW 4
        DW 0o10
        DW 0o20
        DW 0o40
        DW 0o100
        DW 0o200
        DW 0o400
        DW 0o1000
        DW 0o2000
        DW 0o4000
        DW 0o10000
        DW 0o20000
        DW 0o40000
        DW 0o100000

; Sample values
N3:      DW 3
N5:      DW 5
N7:      DW 7
N9:      DW 0o11            ; 9
N11:     DW 0o13            ; 11
N13:     DW 0o15            ; 13
N15:     DW 0o17            ; 15
N17:     DW 0o21            ; 17
N19:     DW 0o23            ; 19
N21:     DW 0o25            ; 21
N23:     DW 0o27            ; 23
N25:     DW 0o31            ; 25

HDR1P:  DW HDR1
HDR2P:  DW HDR2
SEPP:   DW SEP
PRSTRP: DW PRSTR
CPSTRP: DW CPSTR
CRLFP:  DW CRLF

; Bitmap storage - 313 words for odd numbers 3..9999
; Bit mapping: (number - 3) / 2 = bit index
; Example: 3->bit 0, 5->bit 1, 7->bit 2, 9->bit 3, etc.
        ORG 0o2000
BITMAP: DW 0
