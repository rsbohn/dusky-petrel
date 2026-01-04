        ORG 0o200

START:  NIOC AC0, WEB
        LDA AC2, URLPTR
        JSR SEND_WEB
        LDA AC0, WEBCTRL
        DOC AC0, WEB
        NIOS AC0, WEB

WAITW:  SKPDN WEB
        JMP WAITW

        LDA AC1, Q1PTR
        LDA AC2, L1PTR
        JSR QUERY_PRINT
        LDA AC1, Q2PTR
        LDA AC2, L2PTR
        JSR QUERY_PRINT
        LDA AC1, Q3PTR
        LDA AC2, L3PTR
        JSR QUERY_PRINT

        HALT

; AC1 = query pointer, AC2 = label pointer
QUERY_PRINT:
        STA AC3, QP_RET
        NIOC AC0, JSP
        STA AC2, LBLPTR
        MOV AC1, AC2
        JSR SEND_JSP
        LDA AC0, JSPCTRL
        DOC AC0, JSP
        NIOS AC0, JSP

QP_WAIT:
        SKPDN JSP
        JMP QP_WAIT

        LDA AC2, LBLPTR
        JSR PRINT_STR

        LDA AC0, TWO
        DOB AC0, JSP
        DIC AC0, JSP
        STA AC0, COUNT
        LDA AC1, COUNT

QP_READ:
        DIA AC0, JSP
        DOA AC0, UTTO
        LDA AC2, ONE
        SUBZ AC2, AC1
        MOV AC1, AC1, SNR
        JMP QP_DONE
        JMP QP_READ

QP_DONE:
        LDA AC0, CR
        JSR PUTCH
        LDA AC0, LF
        JSR PUTCH
        JMP @QP_RET
QP_RET: DW 0

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

; AC2 = pointer to zero-terminated string
SEND_JSP:
        STA AC3, SJ_RET
SJ_LOOP:
        LDA AC0, 0,AC2
        MOV AC0, AC0, SNR
        JMP @SJ_RET
        DOA AC0, JSP
        INC AC2, AC2
        JMP SJ_LOOP
SJ_RET: DW 0

; AC2 = pointer to zero-terminated string
PRINT_STR:
        STA AC3, PS_RET
PS_LOOP:
        LDA AC0, 0,AC2
        MOV AC0, AC0, SNR
        JMP @PS_RET
        JSR PUTCH
        INC AC2, AC2
        JMP PS_LOOP
PS_RET: DW 0

PUTCH:
        NIOC AC0, UTTO
        DOAS AC0, UTTO
PT_WAIT:
        SKPDN UTTO
        JMP PT_WAIT
        JMP 0,AC3

URLPTR: DW URL
Q1PTR:  DW Q1
Q2PTR:  DW Q2
Q3PTR:  DW Q3
L1PTR:  DW L1
L2PTR:  DW L2
L3PTR:  DW L3
ONE:    DW 1
TWO:    DW 2
COUNT:  DW 0
LBLPTR: DW 0
CR:     DW 0o015
LF:     DW 0o012
WEBCTRL: DW 0
JSPCTRL: DW 1

        ORG 0o1000

URL:    .TXT "https://fdo.rocketlaunch.live/json/launches/next/1"
        DW 0
Q1:     .TXT "/result/0/t0"
        DW 0
Q2:     .TXT "/result/0/name"
        DW 0
Q3:     .TXT "/result/0/launch_description"
        DW 0
L1:     .TXT "Time: "
        DW 0
L2:     .TXT "Name: "
        DW 0
L3:     .TXT "Desc: "
        DW 0
