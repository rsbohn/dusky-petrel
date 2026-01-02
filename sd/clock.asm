        ORG 0o200

; Read RTC and display Ho:Mo:So (octal) since midnight.
; RTC device = 0o21
; DIA = minutes since midnight
; DIB/DIC = epoch seconds (low/high)

START:  LDA     AC2, DATA_BASE
        JMP     READ_TIME

READ_TIME:
        DIC     AC0, 0o21      ; epoch seconds high (sample 1)
        STA     AC0, HI1-DATA_BASE,AC2
        DIB     AC0, 0o21      ; epoch seconds low
        STA     AC0, SEC_LO-DATA_BASE,AC2
        DIC     AC0, 0o21      ; epoch seconds high (sample 2)
        STA     AC0, HI2-DATA_BASE,AC2
        LDA     AC0, HI1-DATA_BASE,AC2
        LDA     AC1, HI2-DATA_BASE,AC2
        SUBZ    AC1, AC0
        MOV     AC0, AC0, SZR
        JMP     READ_TIME
        LDA     AC0, HI1-DATA_BASE,AC2
        STA     AC0, SEC_HI-DATA_BASE,AC2
        DIA     AC0, 0o21      ; minutes since midnight
        STA     AC0, MINUTES_RAW-DATA_BASE,AC2
        STA     AC0, MINUTES-DATA_BASE,AC2

        LDA     AC0, ZERO-DATA_BASE,AC2
        STA     AC0, MIN-DATA_BASE,AC2
        STA     AC0, HOUR-DATA_BASE,AC2

; Hours/minutes from minutes-since-midnight
MIN_DIV:
        LDA     AC0, MINUTES-DATA_BASE,AC2
        LDA     AC1, SIXTY-DATA_BASE,AC2
        SUBZ    AC1, AC0
        STA     AC0, MIN_TMP-DATA_BASE,AC2
        LDA     AC0, MIN_TMP-DATA_BASE,AC2
        LDA     AC1, SIGN-DATA_BASE,AC2
        AND     AC1, AC0
        MOV     AC0, AC0, SZR
        JMP     MIN_DONE

        LDA     AC0, MIN_TMP-DATA_BASE,AC2
        STA     AC0, MINUTES-DATA_BASE,AC2
        LDA     AC0, HOUR-DATA_BASE,AC2
        LDA     AC1, ONE-DATA_BASE,AC2
        ADDZ    AC1, AC0
        STA     AC0, HOUR-DATA_BASE,AC2
        JMP     MIN_DIV

MIN_DONE:
        LDA     AC0, MINUTES-DATA_BASE,AC2
        STA     AC0, MIN-DATA_BASE,AC2

DONE:
        LDA     AC0, HOUR-DATA_BASE,AC2
        JSR     PRINT2
        LDA     AC0, COLON-DATA_BASE,AC2      ; ':'
        DOA     AC0, TTO
        LDA     AC0, MIN-DATA_BASE,AC2
        JSR     PRINT2
        LDA     AC0, SPACE-DATA_BASE,AC2      ; ' '
        DOA     AC0, TTO
        LDA     AC0, CHAR_D-DATA_BASE,AC2     ; 'D'
        DOA     AC0, TTO
        LDA     AC0, CHAR_I-DATA_BASE,AC2     ; 'I'
        DOA     AC0, TTO
        LDA     AC0, CHAR_A-DATA_BASE,AC2     ; 'A'
        DOA     AC0, TTO
        LDA     AC0, CHAR_EQ-DATA_BASE,AC2    ; '='
        DOA     AC0, TTO
        LDA     AC0, MINUTES_RAW-DATA_BASE,AC2
        MOVZR   AC0, AC0
        MOVZR   AC0, AC0
        MOVZR   AC0, AC0
        MOVZR   AC0, AC0
        MOVZR   AC0, AC0
        MOVZR   AC0, AC0
        MOVZR   AC0, AC0
        MOVZR   AC0, AC0
        MOVZR   AC0, AC0
        MOVZR   AC0, AC0
        MOVZR   AC0, AC0
        MOVZR   AC0, AC0
        JSR     PRINT2
        LDA     AC0, MINUTES_RAW-DATA_BASE,AC2
        MOVZR   AC0, AC0
        MOVZR   AC0, AC0
        MOVZR   AC0, AC0
        MOVZR   AC0, AC0
        MOVZR   AC0, AC0
        MOVZR   AC0, AC0
        LDA     AC1, SIXTY_FOUR-DATA_BASE,AC2
        AND     AC1, AC0
        JSR     PRINT2
        LDA     AC0, MINUTES_RAW-DATA_BASE,AC2
        LDA     AC1, SIXTY_FOUR-DATA_BASE,AC2
        AND     AC1, AC0
        JSR     PRINT2
        LDA     AC0, CR-DATA_BASE,AC2
        DOA     AC0, TTO
        LDA     AC0, LF-DATA_BASE,AC2
        DOA     AC0, TTO
        HALT

; PRINT2: print AC0 as two octal digits
PRINT2:
        STA     AC3, RETADR-DATA_BASE,AC2
        STA     AC0, TMPVAL-DATA_BASE,AC2
        LDA     AC1, TMPVAL-DATA_BASE,AC2
        MOVZR   AC1, AC1
        MOVZR   AC1, AC1
        MOVZR   AC1, AC1
        STA     AC1, TMP1-DATA_BASE,AC2
        LDA     AC0, TMP1-DATA_BASE,AC2
        LDA     AC1, ASCII0-DATA_BASE,AC2
        ADDZ    AC1, AC0
        DOA     AC0, TTO
        LDA     AC1, TMPVAL-DATA_BASE,AC2
        LDA     AC0, SEVEN-DATA_BASE,AC2
        AND     AC0, AC1
        STA     AC0, TMP2-DATA_BASE,AC2
        LDA     AC0, TMP2-DATA_BASE,AC2
        LDA     AC1, ASCII0-DATA_BASE,AC2
        ADDZ    AC1, AC0
        DOA     AC0, TTO
        JMP     @RETADR-DATA_BASE,AC2

DATA_BASE: DW DATA_BASE
ZERO:     DW 0
ONE:      DW 1
COLON:    DW 0o072
SPACE:    DW 0o040
CHAR_D:   DW 0o104
CHAR_I:   DW 0o111
CHAR_A:   DW 0o101
CHAR_EQ:  DW 0o075
CR:       DW 0o015
LF:       DW 0o012
SEVEN:    DW 0o7
SIXTY:    DW 0o74
SIGN:     DW 0o100000
SIXTY_FOUR: DW 0o77
ASCII0:   DW 0o60

SEC_LO:   DW 0
SEC_HI:   DW 0
MINUTES:  DW 0
MINUTES_RAW: DW 0
MIN_TMP:  DW 0
MIN:      DW 0
HOUR:     DW 0

TMPVAL:   DW 0
TMP1:     DW 0
TMP2:     DW 0
RETADR:   DW 0
HI1:      DW 0
HI2:      DW 0
