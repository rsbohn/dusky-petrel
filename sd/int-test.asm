        ORG 0o200

; Requires: in the monitor, enable the watchdog device with `wdt host on`.

START:  LDA     AC0, ISR_ADDR
        STA     AC0, 1
        NIOC    AC0, 0o70
        LDA     AC0, WDT_TIMEOUT
        DOA     AC0, 0o70
        LDA     AC0, WDT_CTRL
        DOB     AC0, 0o70
        NIOS    AC0, 0o70
        INTEN

LOOP:   LDA     AC0, CHAR
        LDA     AC1, MASK
        AND     AC1, AC0
        STA     AC0, CHAR
        LDA     AC1, AT_CHAR
        SUBZ#   AC1, AC0, SZC
        LDA     AC0, DOT_CHAR
        DOA     AC0, TTO
        LDA     AC0, @SLOWLY
        JMP     LOOP

ISR_ADDR:   	DW ISR
WDT_TIMEOUT: 	DW 0500
WDT_CTRL:   	DW 067          ; 0110111
                                ; pet + clear + interrupt + repeat + enable
DOT_CHAR:       DW 0056
AT_CHAR:    	DW 0100
CHAR:           DW 0100
MASK:           DW 0177
SLOWLY:		DW 077760       ; slow_memory[0]

ISRW0:  DW 0
ISRW1:  DW 0
ISR:    STA 0, ISRW0
        STA 1, ISRW1
        INTA 1
        NIOC    AC0, 0o70     ; clear watchdog fired/active state
        NIOS    AC0, 0o70     ; re-arm watchdog for next interrupt
        ISZ CHAR
        JMP CONTINUE
        LDA 0, AT_CHAR
        STA 0, CHAR
CONTINUE:
        LDA 1, ISRW1
        LDA 0, ISRW0
        INTEN
        JMP @0
