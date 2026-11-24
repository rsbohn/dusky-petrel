; Directory replace acceptance test, part 1: the switch itself.
; Selector 12: AC1 -> [drive, pointer to 12-word entry]. It switches a
; live entry to the extent the supplied entry describes: the
; copy-on-write commit point. Expected statuses: 0 switched, 1 no live
; entry with that name, 2 I/O error, 3 invalid volume/entry.
        ORG 0o4000
START:  LDA 1, PUBCBP
        LDA 0, TEN
        JSR @KSYS
        LDA 2, R0P
        STA 0, 0,2
        JSR DOLOOK
        LDA 2, R1P
        STA 0, 0,2
        LDA 2, LOOKOUTP
        LDA 0, 6,2
        LDA 2, R2P
        STA 0, 0,2
        LDA 2, LOOKOUTP
        LDA 0, 12,2
        LDA 2, R3P
        STA 0, 0,2
        LDA 2, ENTRYP
        LDA 0, START2
        STA 0, 6,2
        LDA 0, THREE
        STA 0, 7,2
        LDA 0, LEN2
        STA 0, 12,2
        LDA 1, PUBCBP
        LDA 0, TWELVE
        JSR @KSYS
        LDA 2, R4P
        STA 0, 0,2
        JSR DOLOOK
        LDA 2, R5P
        STA 0, 0,2
        LDA 2, LOOKOUTP
        LDA 0, 6,2
        LDA 2, R6P
        STA 0, 0,2
        LDA 2, LOOKOUTP
        LDA 0, 12,2
        LDA 2, R7P
        STA 0, 0,2
        LDA 2, LOOKOUTP
        LDA 0, 5,2
        LDA 2, R8P
        STA 0, 0,2
        LDA 2, PUBCBP
        LDA 0, RBENTP
        STA 0, 1,2
        LDA 1, PUBCBP
        LDA 0, TWELVE
        JSR @KSYS
        LDA 2, R9P
        STA 0, 0,2
        LDA 2, PUBCBP
        LDA 0, ENTRYP
        STA 0, 1,2
        LDA 2, ENTRYP
        LDA 0, NINE
        STA 0, 5,2
        LDA 1, PUBCBP
        LDA 0, TWELVE
        JSR @KSYS
        LDA 2, R10P
        STA 0, 0,2
        LDA 2, ENTRYP
        LDA 0, TWO
        STA 0, 5,2
        HALT
DOLOOK: STA 3, LKRET
        LDA 1, LOOKCBP
        LDA 0, SEVEN
        JSR @KSYS
        JMP @LKRET
LKRET:  DW 0
R0P:    DW 0o6000
R1P:    DW 0o6001
R2P:    DW 0o6002
R3P:    DW 0o6003
R4P:    DW 0o6004
R5P:    DW 0o6005
R6P:    DW 0o6006
R7P:    DW 0o6007
R8P:    DW 0o6010
R9P:    DW 0o6011
R10P:   DW 0o6012
TEN:    DW 0o12
TWELVE: DW 0o14
SEVEN:  DW 7
TWO:    DW 2
THREE:  DW 3
NINE:   DW 0o11
START2: DW 300
LEN2:   DW 500
ENTRYP: DW ENTRY
RBENTP: DW RBENTRY
LOOKOUTP: DW LOOKOUT
KSYS:   DW 0o1002
PUBCBP: DW PUBCB
PUBCB:  DW 0, ENTRY
LOOKCBP: DW LOOKCB
LOOKCB: DW 0, RANAME, LOOKOUT
LOOKOUT: DW 0,0,0,0,0,0,0,0,0,0,0,0
RANAME: DW 0o122101, 0o040040, 0o040040, 0o040040, 0o040040
ENTRY:  DW 0o122101, 0o040040, 0o040040, 0o040040, 0o040040
        DW 2, 100, 2, 0, 0, 200, 0
RBENTRY: DW 0o122102, 0o040040, 0o040040, 0o040040, 0o040040
        DW 2, 100, 2, 0, 0, 200, 0
        ORG 0o6000
        DW 0o177777, 0o177777, 0o177777, 0o177777, 0o177777, 0o177777
        DW 0o177777, 0o177777, 0o177777, 0o177777, 0o177777
