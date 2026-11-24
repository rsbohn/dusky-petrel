; Block-2 replace probe: fill the root directory block with dummy
; members so the chain grows, then run the two-save sequence on a
; member that lives in the second block.
        ORG 0o4000
        JMP START
KSYS:   DW 0o1002
DPCBP:  DW DPCB
DPCB:   DW 0, DENT
DENT:   DW 0, 0o040040, 0o040040, 0o040040, 0o040040
        DW 2, 0o100, 1, 0, 0, 0o20, 0
DNEXT:  DW 0o104061
DCNT:   DW 6
DLCBP:  DW DLCB
DLCB:   DW 0, D6NAME, OUT
D6NAME: DW 0o104066, 0o040040, 0o040040, 0o040040, 0o040040
PCBP:   DW PCB
PCB:    DW 0, ENTRY
ACBP:   DW ACB
ACB:    DW 0
        DW 1
AST:    DW 0
WCBP:   DW WCB
WCB:    DW 0
WBLOCK: DW 0
        DW SRCBUF
        DW 0o20
LCBP:   DW LCB
LCB:    DW 0, NAME, OUT
ENTRYP: DW ENTRY
OUTP:   DW OUT
ELEVEN: DW 0o13
TEN:    DW 0o12
EIGHT:  DW 0o10
NINE:   DW 0o11
TWELVE: DW 0o14
SEVEN:  DW 7
LEN2:   DW 0o40
RDUMP:  DW 0o6000
RD6P:   DW 0o6001
R0P:    DW 0o6002
R1P:    DW 0o6003
R2P:    DW 0o6004
R3P:    DW 0o6005
R4P:    DW 0o6006
R5P:    DW 0o6007
R6P:    DW 0o6010
R7P:    DW 0o6011
R8P:    DW 0o6012
R9P:    DW 0o6013
R10P:   DW 0o6014
R11P:   DW 0o6015
START:  LDA 0, DNEXT
        STA 0, DENT
DLOOP:  LDA 1, DPCBP
        LDA 0, TEN
        JSR @KSYS
        LDA 2, RDUMP
        STA 0, 0,2
        LDA 0, DENT
        INC 0,0
        STA 0, DENT
        DSZ DCNT
        JMP DLOOP
        LDA 1, DLCBP
        LDA 0, SEVEN
        JSR @KSYS
        LDA 2, RD6P
        STA 0, 0,2
        LDA 1, PCBP
        LDA 0, ELEVEN
        JSR @KSYS
        LDA 2, R0P
        STA 0, 0,2
        LDA 1, ACBP
        LDA 0, EIGHT
        JSR @KSYS
        LDA 2, R1P
        STA 0, 0,2
        LDA 0, AST
        STA 0, WBLOCK
        LDA 2, ENTRYP
        STA 0, 6,2
        LDA 1, WCBP
        LDA 0, NINE
        JSR @KSYS
        LDA 2, R2P
        STA 0, 0,2
        LDA 1, PCBP
        LDA 0, TEN
        JSR @KSYS
        LDA 2, R3P
        STA 0, 0,2
        LDA 1, PCBP
        LDA 0, ELEVEN
        JSR @KSYS
        LDA 2, R4P
        STA 0, 0,2
        LDA 1, ACBP
        LDA 0, EIGHT
        JSR @KSYS
        LDA 2, R5P
        STA 0, 0,2
        LDA 0, AST
        LDA 2, R9P
        STA 0, 0,2
        STA 0, WBLOCK
        LDA 2, ENTRYP
        STA 0, 6,2
        LDA 0, LEN2
        STA 0, 12,2
        LDA 1, WCBP
        LDA 0, NINE
        JSR @KSYS
        LDA 2, R6P
        STA 0, 0,2
        LDA 1, PCBP
        LDA 0, TWELVE
        JSR @KSYSP2
        LDA 2, R7P
        STA 0, 0,2
        LDA 1, LCBP
        LDA 0, SEVEN
        JSR @KSYSP2
        LDA 2, R8P
        STA 0, 0,2
        LDA 2, OUTP
        LDA 0, 6,2
        LDA 2, R10P
        STA 0, 0,2
        LDA 2, OUTP
        LDA 0, 12,2
        LDA 2, R11P
        STA 0, 0,2
        HALT
NAME:   DW 0o101071, 0o055102, 0o137103, 0o056124, 0o130124
ENTRY:  DW 0o101071, 0o055102, 0o137103, 0o056124, 0o130124
        DW 2, 0, 1, 0, 0, 0o20, 0
OUT:    DW 0,0,0,0,0,0,0,0,0,0,0,0
KSYSP2: DW 0o1002
        ORG 0o5000
SRCBUF: DW 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
        DW 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
        DW 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
        DW 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
        DW 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
        DW 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
        DW 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
        DW 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
        ORG 0o6000
        DW 0o177777, 0o177777, 0o177777, 0o177777, 0o177777, 0o177777, 0o177777
        DW 0o177777, 0o177777, 0o177777, 0o177777, 0o177777, 0o177777, 0o177777
