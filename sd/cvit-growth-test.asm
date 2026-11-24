; Directory chain growth acceptance test, part 1: growth.
; Fresh image: the root chain is one block holding COMMAND, FOCAL,
; README.md, HELLO (4 live, 5 free). Results land at 0o6000 in order:
; preflight GA (0); publish GA..GE (0 x5, fills the block); preflight
; GF (0, growable); publish GF (0, grows the chain); publish GG (0);
; lookup GG (0); lookup GF (0); duplicate publish GF (1); enum count
; (11); volume fill via selector 8 (ends 4). Part 2 runs on the
; same disk image (cvit-growth-full-test.asm).
        ORG 0o4000
START:  JSR DOCHK
        JSR STORE
        LDA 0, FIVE
        STA 0, CNT
PUB1:   JSR DOPUB
        JSR STORE
        JSR NEXTNAME
        DSZ CNT
        JMP PUB1
        JSR DOCHK
        JSR STORE
        JSR DOPUB
        JSR STORE
        JSR NEXTNAME
        JSR DOPUB
        JSR STORE
        JSR DOLOOK
        JSR STORE
        JSR PREVNAME
        JSR DOLOOK
        JSR STORE
        JSR DOPUB
        JSR STORE
        JSR ENUMCOUNT
        JSR STORE
        JSR DOFILL
        JSR STORE
        HALT
CNT:    DW 0
RPTR:   DW 0o6000
STRET:  DW 0
NNRET:  DW 0
DRET:   DW 0
ECRET:  DW 0
FRET:   DW 0
ECCNT:  DW 0
ECSTAT: DW 0
CHUNK:  DW 0
FSTAT:  DW 0
FIVE:   DW 5
FOUR:   DW 4
ONE:    DW 1
NEGONE: DW 0o177777
CHUNK0: DW 0o1000
TEN:    DW 0o12
ELEVEN: DW 0o13
SEVEN:  DW 7
EIGHT:  DW 0o10
SIX:    DW 6
KSYS:   DW 0o1002
PUBCBP: DW PUBCB
LOOKCBP: DW LOOKCB
ALLOCCBP: DW ALLOCCB
ENUMCBP: DW ENUMCB
ENTRYP: DW ENTRY
STORE:  STA 3, STRET
        LDA 2, RPTR
        STA 0, 0,2
        INC 2,2
        STA 2, RPTR
        JMP @STRET
DOPUB:  STA 3, DRET
        LDA 1, PUBCBP
        LDA 0, TEN
        JSR @KSYS
        JMP @DRET
DOCHK:  STA 3, DRET
        LDA 1, PUBCBP
        LDA 0, ELEVEN
        JSR @KSYS
        JMP @DRET
DOLOOK: STA 3, DRET
        LDA 1, LOOKCBP
        LDA 0, SEVEN
        JSR @KSYS
        JMP @DRET
NEXTNAME: STA 3, NNRET
        LDA 2, ENTRYP
        LDA 0, 0,2
        INC 0,0
        STA 0, 0,2
        JMP @NNRET
PREVNAME: STA 3, NNRET
        LDA 2, ENTRYP
        LDA 0, 0,2
        LDA 1, NEGONE
        ADD 1,0
        STA 0, 0,2
        JMP @NNRET
ENUMCOUNT: STA 3, ECRET
        LDA 2, ENUMCBP
        SUB 0,0
        STA 0, 1,2
        STA 0, 2,2
        STA 0, ECCNT
ECLOOP: LDA 1, ENUMCBP
        LDA 0, SIX
        JSR @KSYS
        MOV 0,0,SZR
        JMP ECDONE
        ISZ ECCNT
        JMP ECLOOP
ECDONE: STA 0, ECSTAT
        LDA 1, ONE
        SUB# 1,0,SZR
        JMP ECERR
        LDA 0, ECCNT
        JMP @ECRET
ECERR:  LDA 0, ECSTAT
        JMP @ECRET
DOFILL: STA 3, FRET
        LDA 0, CHUNK0
        STA 0, CHUNK
FILL:   LDA 2, ALLOCCBP
        LDA 0, CHUNK
        STA 0, 1,2
        LDA 1, ALLOCCBP
        LDA 0, EIGHT
        JSR @KSYS
        MOV 0,0,SZR
        JMP FILL4
        JMP FILL
FILL4:  STA 0, FSTAT
        LDA 1, FOUR
        SUB# 1,0,SZR
        JMP FILLED
        LDA 0, CHUNK
        MOVZR 0,0
        STA 0, CHUNK
        MOV 0,0,SZR
        JMP FILL
FILLED: LDA 0, FSTAT
        JMP @FRET
PUBCB:  DW 0, ENTRY
LOOKCB: DW 0, ENTRY, LOOKOUT
ALLOCCB: DW 0, 1, 0
ENTRY:  DW 0o107101, 0o040040, 0o040040, 0o040040, 0o040040
        DW 1, 2, 1, 0, 0, 1, 0
        DW 0, 0
LOOKOUT: DW 0,0,0,0,0,0,0,0,0,0,0,0
ENUMCB: DW 0, 0, 0, ENOUT
        DW 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
        DW 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
        DW 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
        DW 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
ENOUT:  DW 0,0,0,0,0,0,0,0,0,0,0,0
        ORG 0o6000
RES:    DW 0o177777, 0o177777, 0o177777, 0o177777, 0o177777, 0o177777, 0o177777
        DW 0o177777, 0o177777, 0o177777, 0o177777, 0o177777, 0o177777, 0o177777
