; Directory chain growth acceptance test, part 2: full volume.
; Runs on the disk left by cvit-growth-test.asm: the root chain has
; two blocks (9 + 2 live, 7 free in the grown block) and the volume
; is completely full. Results at 0o6000: publish GH..GN (0 x7, fills
; the grown block); preflight GO (4); publish GO (4); lookup GO (1,
; absent); enum count (18).
        ORG 0o4000
START:  LDA 0, SEVENN
        STA 0, CNT
PUB3:   JSR DOPUB
        JSR STORE
        JSR NEXTNAME
        DSZ CNT
        JMP PUB3
        JSR DOCHK
        JSR STORE
        JSR DOPUB
        JSR STORE
        JSR DOLOOK
        JSR STORE
        JSR ENUMCOUNT
        JSR STORE
        HALT
CNT:    DW 0
RPTR:   DW 0o6000
STRET:  DW 0
NNRET:  DW 0
DRET:   DW 0
ECRET:  DW 0
ECCNT:  DW 0
ECSTAT: DW 0
SEVENN: DW 7
ONE:    DW 1
TEN:    DW 0o12
ELEVEN: DW 0o13
SEVEN:  DW 7
SIX:    DW 6
KSYS:   DW 0o1002
PUBCBP: DW PUBCB
LOOKCBP: DW LOOKCB
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
PUBCB:  DW 0, ENTRY
LOOKCB: DW 0, ENTRY, LOOKOUT
ENTRY:  DW 0o107110, 0o040040, 0o040040, 0o040040, 0o040040
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
RES:    DW 0o177777, 0o177777, 0o177777, 0o177777, 0o177777, 0o177777
        DW 0o177777, 0o177777, 0o177777, 0o177777, 0o177777
