; dep 20 <address>
; go 2000
; -- prints memory contents starting at <address>
; -- eight 16-bit words per line
; 2000: word word word word word word word word

        ORG 0o2000
START:  LDA AC0, CHAR
        JSR OPRINT
        JSR CRLF
        HALT
        JMP START
CHAR:   DW 0101

OPRINT: STA AC3, FLEET
        STA AC0, W
        JSR DIGIT
        STA AC0, NUM6+6

        LDA AC0, W
        MOVR AC0, AC0
        MOVR AC0, AC0
        MOVR AC0, AC0
        STA AC0, W
        JSR DIGIT
        STA AC0, NUM6+5

        LDA AC0, W
        MOVR AC0, AC0
        MOVR AC0, AC0
        MOVR AC0, AC0
        STA AC0, W
        JSR DIGIT
        STA AC0, NUM6+4

        LDA AC0, W
        MOVR AC0, AC0
        MOVR AC0, AC0
        MOVR AC0, AC0
        STA AC0, W
        JSR DIGIT
        STA AC0, NUM6+3

        LDA AC0, W
        MOVR AC0, AC0
        MOVR AC0, AC0
        MOVR AC0, AC0
        STA AC0, W
        JSR DIGIT
        STA AC0, NUM6+2

        LDA AC0, W
        MOVR AC0, AC0
        MOVR AC0, AC0
        MOVR AC0, AC0
        STA AC0, W
        JSR DIGIT
        STA AC0, NUM6+1

        LDA AC2, NUM6
        LDA AC0, 1,AC2
        JSR PUTCH
        LDA AC0, 2,AC2
        JSR PUTCH
        LDA AC0, 3,AC2
        JSR PUTCH
        LDA AC0, 4,AC2
        JSR PUTCH
        LDA AC0, 5,AC2
        JSR PUTCH
        LDA AC0, 6,AC2
        JSR PUTCH
        LDA AC0, W
        JMP @FLEET
FLEET:  DW 0    ; holds the return address
W:      DW 0    ; holds AC0
SEVEN:  DW 0007 ; mask
AZERO:  DW 0060 ; ascii zero
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
