        ORG 0o200

LOOP:   SKPDN TTI
        BR LOOP
        DIA TTI
        STA AC0, CH
        LDA AC0, CH
        SUB AC0, EOT
        BZ AC0, DONE
        LDA AC0, CH
        DOA TTO
        BR LOOP

DONE:   HALT

CH:     DW 0
EOT:    DW 0o004
