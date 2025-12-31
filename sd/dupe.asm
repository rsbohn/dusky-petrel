        ORG 0o200

; Read from PTR and copy to TTO and PTP until EOT.

LOOP:   SKPDN PTR
        JMP LOOP
        DIA AC0, PTR
        STA AC0, CH
        LDA AC0, CH
        LDA AC1, EOT
        SUBZ AC1, AC0
        MOV AC0, AC0, SNR
        JMP DONE
        LDA AC0, CH
        DOA AC0, TTO
        DOA AC0, PTP
        JMP LOOP

DONE:   HALT

CH:     DW 0
EOT:    DW 0o004
