    ORG 01000
start:
    LDA 1, 0000    ; Z:0000
    LDA 0, 0001    ; Z:0001
    JMP loop        ; label in normal space, not page zero
    NOP
loop:
    JMP start
