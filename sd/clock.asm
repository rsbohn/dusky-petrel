        ORG 0o200

; Read RTC and display Ho:Mo:So (octal) since midnight.
; RTC device = 0o21
; DIA = minutes since midnight
; DIB/DIC = epoch seconds (low/high)

START:  BR      READ_TIME

READ_TIME:
        DIC     0o21           ; epoch seconds high (sample 1)
        STA     AC0, HI1
        DIB     0o21           ; epoch seconds low
        STA     AC0, SEC_LO
        DIC     0o21           ; epoch seconds high (sample 2)
        STA     AC0, HI2
        LDA     AC0, HI1
        SUB     AC0, HI2
        BNZ     AC0, READ_TIME
        LDA     AC0, HI1
        STA     AC0, SEC_HI
        DIA     0o21           ; minutes since midnight
        STA     AC0, MINUTES_RAW
        STA     AC0, MINUTES

        LDAI    AC0, 0
        STA     AC0, MIN
        STA     AC0, HOUR

; Hours/minutes from minutes-since-midnight
MIN_DIV:
        LDAI    AC2, 0          ; clear LINK for subtract
        LDA     AC0, MINUTES
        SUB     AC0, SIXTY
        STA     AC0, MIN_TMP
        LDA     AC0, MIN_TMP
        AND     AC0, SIGN
        BNZ     AC0, MIN_DONE

        LDA     AC0, MIN_TMP
        STA     AC0, MINUTES
        LDAI    AC2, 0
        LDA     AC0, HOUR
        ADD     AC0, ONE
        STA     AC0, HOUR
        BR      MIN_DIV

MIN_DONE:
        LDA     AC0, MINUTES
        STA     AC0, MIN

DONE:
        LDA     AC0, HOUR
        JSR     3, PRINT2
        LDAI    AC0, 0o072      ; ':'
        DOA     TTO
        LDA     AC0, MIN
        JSR     3, PRINT2
        LDAI    AC0, 0o040      ; ' '
        DOA     TTO
        LDAI    AC0, 0o104      ; 'D'
        DOA     TTO
        LDAI    AC0, 0o111      ; 'I'
        DOA     TTO
        LDAI    AC0, 0o101      ; 'A'
        DOA     TTO
        LDAI    AC0, 0o075      ; '='
        DOA     TTO
        LDA     AC0, MINUTES_RAW
        SHR     AC0, 12
        JSR     3, PRINT2
        LDA     AC0, MINUTES_RAW
        SHR     AC0, 6
        AND     AC0, SIXTY_FOUR
        JSR     3, PRINT2
        LDA     AC0, MINUTES_RAW
        AND     AC0, SIXTY_FOUR
        JSR     3, PRINT2
        LDAI    AC0, 0o015      ; CR
        DOA     TTO
        LDAI    AC0, 0o012      ; LF
        DOA     TTO
        HALT

; PRINT2: print AC0 as two octal digits
PRINT2:
        STA     3, RETADR
        STA     AC0, TMPVAL
        LDA     AC1, TMPVAL
        SHR     AC1, 3
        STA     AC1, TMP1
        LDA     AC0, TMP1
        ADD     AC0, ASCII0
        DOA     TTO
        LDA     AC1, TMPVAL
        AND     AC1, SEVEN
        STA     AC1, TMP2
        LDA     AC0, TMP2
        ADD     AC0, ASCII0
        DOA     TTO
        BR      @RETADR

ZERO:     DW 0
ONE:      DW 1
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
