; lobby.asm: list five FujiNet lobby servers from Dusky Petrel, using WEB and JSP.
; Run from the monitor with: asm lobby.asm, then go START
        ORG 0o0

URLPTR:   DW URL
ONE:      DW 1
TWO:      DW 2
COUNT:    DW 0
DIGIT:    DW 0o060
SLASH:    DW 0o057
SPACE:    DW 0o040
CR:       DW 0o015
LF:       DW 0o012
FG:       DW 0o147
FS:       DW 0o163
FP:       DW 0o160
FM:       DW 0o155
WEBCTRL:  DW 0
JSPCTRL:  DW 1

        ORG 0o200

START:  NIOC AC0, WEB
        LDA AC2, URLPTR
        JSR SEND_WEB
        LDA AC0, WEBCTRL
        DOC AC0, WEB
        NIOS AC0, WEB

WAITW:  SKPDN WEB
        JMP WAITW

; A missing record returns an empty value, which ends the list.
NEXT:   LDA AC1, FG
        JSR QUERY
        LDA AC1, COUNT
        MOV AC1, AC1, SZR
        JMP RECORD
        HALT

RECORD: JSR SHOW
        LDA AC0, SPACE
        JSR PUTCH
        LDA AC1, FS
        JSR QUERY
        JSR SHOW
        LDA AC0, SPACE
        JSR PUTCH
        LDA AC1, FP
        JSR QUERY
        JSR SHOW
        LDA AC0, SLASH
        JSR PUTCH
        LDA AC1, FM
        JSR QUERY
        JSR SHOW
        LDA AC0, CR
        JSR PUTCH
        LDA AC0, LF
        JSR PUTCH
        LDA AC0, DIGIT
        INC AC0, AC0
        STA AC0, DIGIT
        JMP NEXT

; AC1 = field letter. Queries /<DIGIT>/<field> and leaves the length in COUNT.
QUERY:  STA AC3, Q_RET
        NIOC AC0, JSP
        LDA AC0, SLASH
        DOA AC0, JSP
        LDA AC0, DIGIT
        DOA AC0, JSP
        LDA AC0, SLASH
        DOA AC0, JSP
        DOA AC1, JSP
        LDA AC0, JSPCTRL
        DOC AC0, JSP
        NIOS AC0, JSP
Q_WAIT: SKPDN JSP
        JMP Q_WAIT
        LDA AC0, TWO
        DOB AC0, JSP
        DIC AC0, JSP
        STA AC0, COUNT
        JMP @Q_RET
Q_RET:  DW 0

; Prints COUNT words of the current JSP value.
SHOW:   STA AC3, S_RET
        LDA AC1, COUNT
        MOV AC1, AC1, SNR
        JMP @S_RET
S_READ: DIA AC0, JSP
        DOA AC0, UTTO
        LDA AC2, ONE
        SUBZ AC2, AC1
        MOV AC1, AC1, SNR
        JMP @S_RET
        JMP S_READ
S_RET:  DW 0

; AC2 = pointer to zero-terminated string
SEND_WEB:
        STA AC3, SW_RET
SW_LOOP:
        LDA AC0, 0,AC2
        MOV AC0, AC0, SNR
        JMP @SW_RET
        DOA AC0, WEB
        INC AC2, AC2
        JMP SW_LOOP
SW_RET: DW 0

PUTCH:
        NIOC AC0, UTTO
        DOAS AC0, UTTO
PT_WAIT:
        SKPDN UTTO
        JMP PT_WAIT
        JMP 0,AC3

        ORG 0o1000

URL:    .TXT "http://fujinet.online:8080/view?platform=atari&pagesize=5"
        DW 0

