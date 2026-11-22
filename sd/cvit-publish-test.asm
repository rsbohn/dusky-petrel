; Directory publication acceptance test.
; Selector 10: AC1 -> [drive, pointer to 12-word entry].
; Expected statuses: 0 published, 1 duplicate live name, 2 I/O error,
; 3 invalid volume/entry, 4 directory full.
        ORG 0o4000
START:  LDA 1, PUBCBP
        LDA 0, ELEVEN
        JSR @KSYS
        LDA 2, CHECKSTATUSP
        STA 0, 0,2
        LDA 1, LOOKCBP
        LDA 0, SEVEN
        JSR @KSYS
        LDA 2, BEFORESTATUSP
        STA 0, 0,2

        LDA 1, PUBCBP
        LDA 0, TEN
        JSR @KSYS
        LDA 2, PUBSTATUSP
        STA 0, 0,2

        ; The publisher itself must reject a duplicate, not just preflight.
        LDA 2, ENTRYP
        LDA 0, TWO
        STA 0, 12,2
        LDA 1, PUBCBP
        LDA 0, TEN
        JSR @KSYS
        LDA 2, DUPSTATUSP
        STA 0, 0,2

        ; Verify that the published member is visible through selector 7.
        LDA 1, LOOKCBP
        LDA 0, SEVEN
        JSR @KSYS
        LDA 2, LOOKSTATUSP
        STA 0, 0,2
        LDA 2, LOOKOUTP
        LDA 0, 5,2
        LDA 2, LOOKTYPEP
        STA 0, 0,2
        LDA 2, LOOKOUTP
        LDA 0, 6,2
        LDA 2, LOOKSTARTP
        STA 0, 0,2
        LDA 2, LOOKOUTP
        LDA 0, 7,2
        LDA 2, LOOKBLOCKSP
        STA 0, 0,2
        LDA 2, LOOKOUTP
        LDA 0, 12,2
        LDA 2, LOOKLENGTHP
        STA 0, 0,2
        HALT

KSYS:   DW 0o1002
PUBCBP: DW PUBCB
PUBCB:  DW 0, ENTRY
LOOKCBP: DW LOOKCB
LOOKCB: DW 0, NAME, LOOKOUT
NAME:   DW 0o124105, 0o123124, 0o040040, 0o040040, 0o040040 ; TEST
ENTRY:  DW 0o124105, 0o123124, 0o040040, 0o040040, 0o040040 ; TEST
        DW 1, 2, 1, 0, 0, 1, 0
TEN:    DW 0o12
ELEVEN: DW 0o13
SEVEN:  DW 7
TWO:    DW 2
ENTRYP: DW ENTRY
PUBSTATUSP: DW 0o4210
LOOKSTATUSP: DW 0o4211
LOOKTYPEP: DW 0o4212
LOOKSTARTP: DW 0o4213
LOOKBLOCKSP: DW 0o4214
LOOKLENGTHP: DW 0o4215
CHECKSTATUSP: DW 0o4216
BEFORESTATUSP: DW 0o4217
DUPSTATUSP: DW 0o4220
LOOKOUTP: DW LOOKOUT
        ORG 0o4210
PUBSTATUS: DW 0o177777
LOOKSTATUS: DW 0o177777
LOOKTYPE: DW 0o177777
LOOKSTART: DW 0o177777
LOOKBLOCKS: DW 0o177777
LOOKLENGTH: DW 0o177777
CHECKSTATUS: DW 0o177777
BEFORESTATUS: DW 0o177777
DUPSTATUS: DW 0o177777
LOOKOUT: DW 0,0,0,0,0,0,0,0,0,0,0,0
