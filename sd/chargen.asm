        ORG 00200

START:  LDA     AC0, CMIN
        STA     AC0, @PCHR
        DOAS    AC0, TTO        ; bootstrap

LOOP:   SKPDN   TTO             ; wait for TTO done
        JMP LOOP
        LDA     AC0, @PCHR
        DOAS    AC0, TTO
        INC     AC0, AC0
        LDA     AC1, CMAX
        SUBZ#   AC1, AC0, SNR
        LDA     AC0, CMIN
        STA     AC0, @PCHR
        JMP     LOOP

PCHR:   DW 077760
CMIN:   DW 0100 ; '@'
CMAX:   DW 0107 ; 'G'
