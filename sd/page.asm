; dep 20 <address>
; go 2000
; -- prints memory contents starting at <address>
; -- eight 16-bit words per line
; 2000: word word word word word word word word

        ORG 0o2000
START:  LDA AC0, LPERP
        STA AC0, LCOUNT
 ML:    LDA AC0, @ADDR
        JSR OPRINT
        LDA AC0, COLON
        JSR PUTCH
        LDA AC0, SPACE
        JSR PUTCH
        JSR PLINE
        JSR CRLF
        DSZ LCOUNT
        JMP ML
        HALT
        JMP START
ADDR:   DW 00020
COLON:  DW 0072         ; ':'
SPACE:  DW 0040         ; ' '
WPERLI: DW 010          ; words per line
LPERP:  DW 010          ; lines per 'page'
LCOUNT: DW 0

; Print Line -- uses AC0 AC1 ZP:0021
PLINE:  STA AC3, PLINE_RET
        LDA AC0, WPERLI
        STA AC0, WCOUNT
        LDA AC0, @ADDR
        STA AC0, LPP
PLOOP:  LDA AC0, @LPP
        JSR OPRINT
        LDA AC0, SPACE
        JSR PUTCH
        LDA AC0, LPP
        INC AC0, AC0
        STA AC0, LPP
        DSZ WCOUNT
        JMP PLOOP
        LDA AC0, @ADDR
        LDA AC1, WPERLI
        ADD AC1, AC0
        STA AC0, @ADDR
        JMP @PLINE_RET
PLINE_RET: DW 0
LPP:    DW 0
WCOUNT: DW 0
        

; Uses AC0 AC1 AC2
OPRINT: STA AC3, FLEET
        STA AC0, W
        LDA AC2, NUMZ
        LDA AC1, SIX
        STA AC1, COUNT

OPR_LOOP:
        LDA AC0, W
        JSR DIGIT
        STA AC0, 0,AC2
        LDA AC0, W
        MOVZR AC0, AC0
        MOVZR AC0, AC0
        MOVZR AC0, AC0
        STA AC0, W
        LDA AC1, ONE
        SUBZ AC1, AC2
        DSZ COUNT
        JMP OPR_LOOP

        LDA AC2, NUM6
        LDA AC1, SIX
        STA AC1, COUNT
        LDA AC1, ONE
OPR_PUT_LOOP:
        LDA AC0, 1,AC2
        JSR PUTCH
        ADD AC1, AC2
        DSZ COUNT
        JMP OPR_PUT_LOOP
        LDA AC0, W
        JMP @FLEET
FLEET:  DW 0    ; holds the return address
W:      DW 0    ; holds AC0
SEVEN:  DW 0007 ; mask
AZERO:  DW 0060 ; ascii zero
ONE:    DW 0001
SIX:    DW 0006
COUNT:  DW 0
NUMZ:   DW NUM6+6
NUM6:   DW NUM6
        .TXT /------/

DIGIT:  LDA AC1, SEVEN  ; mask 0007 add '0'
        AND AC1, AC0
        LDA AC1, AZERO
        ADD AC1, AC0
        JMP 0,AC3

CRLF:   STA AC3,CRLF_RET
        LDA AC0, CR
        JSR PUTCH
        LDA AC0, LF
        JSR PUTCH
        JMP @CRLF_RET
CRLF_RET: DW 0
CR:     DW 15
LF:     DW 12

; PUTCH  -- print AC0 as an ASCII character
;        -- print to TTO
PUTCH:
PUTC:
        NIOC AC0, TTO
        DOAS AC0, TTO
PUTC_WAIT:
        SKPDN TTO
        JMP PUTC_WAIT
        JMP 0,AC3

; that's all!
