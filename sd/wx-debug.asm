        ORG 0o0

URLPTR:   DW URL
Q1PTR:    DW Q1
Q2PTR:    DW Q2
Q3PTR:    DW Q3
LBL1PTR:  DW LBL1
LBL2PTR:  DW LBL2
LBL3PTR:  DW LBL3
LBL_WEB_STATUS_PTR: DW LBL_WEB_STATUS
LBL_WEB_LENLO_PTR:  DW LBL_WEB_LENLO
LBL_WEB_LENHI_PTR:  DW LBL_WEB_LENHI
LBL_WEB_TYPE_PTR:   DW LBL_WEB_TYPE
LBL_WEB_ERR_PTR:    DW LBL_WEB_ERR
LBL_JSP_TYPE_PTR:   DW LBL_JSP_TYPE
LBL_JSP_ERR_PTR:    DW LBL_JSP_ERR
LBL_JSP_LENLO_PTR:  DW LBL_JSP_LENLO
LBL_JSP_LENHI_PTR:  DW LBL_JSP_LENHI
NONEPTR:  DW NONE_STR
ZERO:     DW 0
ONE:      DW 1
TWO:      DW 2
COUNT:    DW 0
CR:       DW 0o015
LF:       DW 0o012
WEBCTRL:  DW 0
JSPCTRL:  DW 1
LBLPTR:   DW 0
ASCII0:   DW 0o60
SEVEN:    DW 0o7

        ORG 0o200

START:  NIOC AC0, WEB
        LDA AC2, URLPTR
        JSR SEND_WEB
        LDA AC0, WEBCTRL
        DOC AC0, WEB
        NIOS AC0, WEB

WAITW:  SKPDN WEB
        JMP WAITW

        JSR PRINT_WEB_META

        LDA AC1, Q1PTR
        LDA AC2, LBL1PTR
        JSR QUERY_PRINT
        LDA AC1, Q2PTR
        LDA AC2, LBL2PTR
        JSR QUERY_PRINT
        LDA AC1, Q3PTR
        LDA AC2, LBL3PTR
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

        JSR PRINT_JSP_META

        LDA AC2, LBLPTR
        JSR PRINT_STR

        LDA AC0, TWO
        DOB AC0, JSP
        DIC AC0, JSP
        STA AC0, COUNT
        LDA AC1, COUNT
        MOV AC1, AC1, SZR
        JMP QP_VALUE

        LDA AC2, NONEPTR
        JSR PRINT_STR
        JMP QP_DONE

QP_VALUE:
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

PRINT_WEB_META:
        STA AC3, PWM_RET
        LDA AC0, ZERO
        DOB AC0, WEB
        DIC AC0, WEB
        LDA AC2, LBL_WEB_STATUS_PTR
        JSR PRINT_LABEL_VALUE
        DIC AC0, WEB
        LDA AC2, LBL_WEB_LENLO_PTR
        JSR PRINT_LABEL_VALUE
        DIC AC0, WEB
        LDA AC2, LBL_WEB_LENHI_PTR
        JSR PRINT_LABEL_VALUE
        DIC AC0, WEB
        LDA AC2, LBL_WEB_TYPE_PTR
        JSR PRINT_LABEL_VALUE
        DIC AC0, WEB
        LDA AC2, LBL_WEB_ERR_PTR
        JSR PRINT_LABEL_VALUE
        JMP @PWM_RET
PWM_RET: DW 0

PRINT_JSP_META:
        STA AC3, PJM_RET
        LDA AC0, ZERO
        DOB AC0, JSP
        DIC AC0, JSP
        LDA AC2, LBL_JSP_TYPE_PTR
        JSR PRINT_LABEL_VALUE
        DIC AC0, JSP
        LDA AC2, LBL_JSP_ERR_PTR
        JSR PRINT_LABEL_VALUE
        DIC AC0, JSP
        LDA AC2, LBL_JSP_LENLO_PTR
        JSR PRINT_LABEL_VALUE
        DIC AC0, JSP
        LDA AC2, LBL_JSP_LENHI_PTR
        JSR PRINT_LABEL_VALUE
        JMP @PJM_RET
PJM_RET: DW 0

; AC0 = value, AC2 = label pointer
PRINT_LABEL_VALUE:
        STA AC3, PLV_RET
        STA AC0, PLV_TMP
        JSR PRINT_STR
        LDA AC0, PLV_TMP
        JSR PRINT3
        LDA AC0, CR
        JSR PUTCH
        LDA AC0, LF
        JSR PUTCH
        JMP @PLV_RET
PLV_RET: DW 0
PLV_TMP: DW 0

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

; PRINT3: print AC0 as three octal digits
PRINT3:
        STA AC3, P3_RET
        STA AC0, P3_TMP
        LDA AC1, P3_TMP
        MOVZR AC1, AC1
        MOVZR AC1, AC1
        MOVZR AC1, AC1
        MOVZR AC1, AC1
        MOVZR AC1, AC1
        MOVZR AC1, AC1
        LDA AC0, SEVEN
        AND AC0, AC1
        LDA AC0, ASCII0
        ADDZ AC0, AC1
        DOA AC1, TTO

        LDA AC1, P3_TMP
        MOVZR AC1, AC1
        MOVZR AC1, AC1
        MOVZR AC1, AC1
        LDA AC0, SEVEN
        AND AC0, AC1
        LDA AC0, ASCII0
        ADDZ AC0, AC1
        DOA AC1, TTO

        LDA AC1, P3_TMP
        LDA AC0, SEVEN
        AND AC0, AC1
        LDA AC0, ASCII0
        ADDZ AC0, AC1
        DOA AC1, TTO
        JMP @P3_RET
P3_RET: DW 0
P3_TMP: DW 0

        ORG 0o1000

URL:    .TXT "https://aviationweather.gov/api/data/metar?ids=KPVU&format=json&hours=2"
        DW 0
Q1:     .TXT "/0/rawOb"
        DW 0
Q2:     .TXT "/0/fltCat"
        DW 0
Q3:     .TXT "/0/temp"
        DW 0
LBL1:   .TXT "METAR: "
        DW 0
LBL2:   .TXT "Flight: "
        DW 0
LBL3:   .TXT "Temp C: "
        DW 0
LBL_WEB_STATUS: .TXT "WEB status: "
        DW 0
LBL_WEB_LENLO:  .TXT "WEB lenLo: "
        DW 0
LBL_WEB_LENHI:  .TXT "WEB lenHi: "
        DW 0
LBL_WEB_TYPE:   .TXT "WEB type: "
        DW 0
LBL_WEB_ERR:    .TXT "WEB err: "
        DW 0
LBL_JSP_TYPE:   .TXT "JSP type: "
        DW 0
LBL_JSP_ERR:    .TXT "JSP err: "
        DW 0
LBL_JSP_LENLO:  .TXT "JSP lenLo: "
        DW 0
LBL_JSP_LENHI:  .TXT "JSP lenHi: "
        DW 0
NONE_STR: .TXT "(none)"
        DW 0
