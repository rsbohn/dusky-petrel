        ORG 0o0

URLPTR:           DW URL
SPOT_LABELS_PTR:  DW SPOT_LABELS
FIELD_LABELS_PTR: DW FIELD_LABELS
QUERY_PTRS_PTR:   DW QUERY_PTRS
ONE:              DW 1
THREE:            DW 3
SEVEN:            DW 7
SPOT_PTR:         DW 0
FIELD_PTR:        DW 0
QUERY_PTR:        DW 0
SPOT_COUNT:       DW 0
FIELD_COUNT:      DW 0
CR:               DW 0o015
LF:               DW 0o012
WEBCTRL:          DW 0
JSPCTRL:          DW 1

SPOT_LABELS:  DW SPOT1LBL, SPOT2LBL, SPOT3LBL
FIELD_LABELS: DW LBL_TIME, LBL_ACT, LBL_FREQ, LBL_MODE, LBL_REF, LBL_NAME, LBL_LOC
QUERY_PTRS:   DW Q0_TIME, Q0_ACT, Q0_FREQ, Q0_MODE, Q0_REF, Q0_NAME, Q0_LOC
              DW Q1_TIME, Q1_ACT, Q1_FREQ, Q1_MODE, Q1_REF, Q1_NAME, Q1_LOC
              DW Q2_TIME, Q2_ACT, Q2_FREQ, Q2_MODE, Q2_REF, Q2_NAME, Q2_LOC

        ORG 0o200

START:  NIOC AC0, WEB
        LDA AC2, URLPTR
        JSR SEND_WEB
        LDA AC0, WEBCTRL
        DOC AC0, WEB
        NIOS AC0, WEB

WAITW:  SKPDN WEB
        JMP WAITW

        LDA AC0, SPOT_LABELS_PTR
        STA AC0, SPOT_PTR
        LDA AC0, QUERY_PTRS_PTR
        STA AC0, QUERY_PTR
        LDA AC0, THREE
        STA AC0, SPOT_COUNT

SPOT_LOOP:
        LDA AC2, SPOT_PTR
        LDA AC2, 0,AC2
        JSR PRINT_STR

        LDA AC0, FIELD_LABELS_PTR
        STA AC0, FIELD_PTR
        LDA AC0, SEVEN
        STA AC0, FIELD_COUNT

FIELD_LOOP:
        LDA AC2, FIELD_PTR
        LDA AC2, 0,AC2
        JSR PRINT_STR

        LDA AC2, QUERY_PTR
        LDA AC1, 0,AC2
        JSR QUERY_VALUE

        LDA AC2, FIELD_PTR
        LDA AC0, ONE
        ADDZ AC0, AC2
        STA AC2, FIELD_PTR

        LDA AC2, QUERY_PTR
        LDA AC0, ONE
        ADDZ AC0, AC2
        STA AC2, QUERY_PTR

        LDA AC1, FIELD_COUNT
        LDA AC0, ONE
        SUBZ AC0, AC1
        STA AC1, FIELD_COUNT
        MOV AC1, AC1, SNR
        JMP FIELD_DONE
        JMP FIELD_LOOP

FIELD_DONE:
        JSR PRINT_NEWLINE
        LDA AC2, SPOT_PTR
        LDA AC0, ONE
        ADDZ AC0, AC2
        STA AC2, SPOT_PTR

        LDA AC1, SPOT_COUNT
        LDA AC0, ONE
        SUBZ AC0, AC1
        STA AC1, SPOT_COUNT
        MOV AC1, AC1, SNR
        JMP DONE
        JMP SPOT_LOOP

DONE:   HALT

; AC1 = query pointer
QUERY_VALUE:
        STA AC3, QV_RET
        NIOC AC0, JSP
        MOV AC1, AC2
        JSR SEND_JSP
        LDA AC0, JSPCTRL
        DOC AC0, JSP
        NIOS AC0, JSP

QV_WAIT:
        SKPDN JSP
        JMP QV_WAIT

        LDA AC0, TWO
        DOB AC0, JSP
        DIC AC0, JSP
        STA AC0, COUNT
        LDA AC1, COUNT

QV_READ:
        DIA AC0, JSP
        DOA AC0, UTTO
        LDA AC2, ONE
        SUBZ AC2, AC1
        MOV AC1, AC1, SNR
        JMP QV_DONE
        JMP QV_READ

QV_DONE:
        JMP @QV_RET
QV_RET: DW 0

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

PRINT_NEWLINE:
        STA AC3, PN_RET
        LDA AC0, CR
        JSR PUTCH
        LDA AC0, LF
        JSR PUTCH
        JMP @PN_RET
PN_RET: DW 0

PUTCH:
        NIOC AC0, UTTO
        DOAS AC0, UTTO
PT_WAIT:
        SKPDN UTTO
        JMP PT_WAIT
        JMP 0,AC3

TWO:   DW 2
COUNT: DW 0

        ORG 0o1000

URL:     .TXT "https://api.pota.app/spot?count=3"
        DW 0

SPOT1LBL: .TXT "Spot 1:"
        DW 0
SPOT2LBL: .TXT "Spot 2:"
        DW 0
SPOT3LBL: .TXT "Spot 3:"
        DW 0

LBL_TIME: .TXT " Time: "
        DW 0
LBL_ACT:  .TXT " Act: "
        DW 0
LBL_FREQ: .TXT " Freq: "
        DW 0
LBL_MODE: .TXT " Mode: "
        DW 0
LBL_REF:  .TXT " Ref: "
        DW 0
LBL_NAME: .TXT " Name: "
        DW 0
LBL_LOC:  .TXT " Loc: "
        DW 0

Q0_TIME: .TXT "/0/spotTime"
        DW 0
Q0_ACT:  .TXT "/0/activator"
        DW 0
Q0_FREQ: .TXT "/0/frequency"
        DW 0
Q0_MODE: .TXT "/0/mode"
        DW 0
Q0_REF:  .TXT "/0/reference"
        DW 0
Q0_NAME: .TXT "/0/name"
        DW 0
Q0_LOC:  .TXT "/0/locationDesc"
        DW 0

Q1_TIME: .TXT "/1/spotTime"
        DW 0
Q1_ACT:  .TXT "/1/activator"
        DW 0
Q1_FREQ: .TXT "/1/frequency"
        DW 0
Q1_MODE: .TXT "/1/mode"
        DW 0
Q1_REF:  .TXT "/1/reference"
        DW 0
Q1_NAME: .TXT "/1/name"
        DW 0
Q1_LOC:  .TXT "/1/locationDesc"
        DW 0

Q2_TIME: .TXT "/2/spotTime"
        DW 0
Q2_ACT:  .TXT "/2/activator"
        DW 0
Q2_FREQ: .TXT "/2/frequency"
        DW 0
Q2_MODE: .TXT "/2/mode"
        DW 0
Q2_REF:  .TXT "/2/reference"
        DW 0
Q2_NAME: .TXT "/2/name"
        DW 0
Q2_LOC:  .TXT "/2/locationDesc"
        DW 0
