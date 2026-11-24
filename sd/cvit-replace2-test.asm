; Directory replace acceptance test, part 2: runs on part 1's disk.
; After a replace the chain must still hold exactly one RA (the volume
; count stays 5) and publish must still reject RA as a duplicate.
        ORG 0o4000
START:  LDA 1, PUBCBP
        LDA 0, TEN
        JSR @KSYS
        LDA 2, R0P
        STA 0, 0,2
        LDA 2, ENTRYP
        LDA 0, START2
        STA 0, 6,2
        LDA 0, LEN2
        STA 0, 12,2
        LDA 1, PUBCBP
        LDA 0, TWELVE
        JSR @KSYS
        LDA 2, R1P
        STA 0, 0,2
        JSR ENUMCOUNT
        LDA 2, R2P
        STA 0, 0,2
        LDA 1, PUBCBP
        LDA 0, TEN
        JSR @KSYS
        LDA 2, R3P
        STA 0, 0,2
        HALT
R0P:    DW 0o6020
R1P:    DW 0o6021
R2P:    DW 0o6022
R3P:    DW 0o6023
TEN:    DW 0o12
TWELVE: DW 0o14
SIX:    DW 6
ONE:    DW 1
START2: DW 300
LEN2:   DW 500
ENTRYP: DW ENTRY
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
ECRET:  DW 0
ECCNT:  DW 0
ECSTAT: DW 0
KSYS:   DW 0o1002
PUBCBP: DW PUBCB
PUBCB:  DW 0, ENTRY
ENUMCBP: DW ENUMCB
ENUMCB: DW 0, 0, 0, ENOUT
        DW 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
        DW 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
        DW 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
        DW 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
ENOUT:  DW 0,0,0,0,0,0,0,0,0,0,0,0
ENTRY:  DW 0o122101, 0o040040, 0o040040, 0o040040, 0o040040
        DW 2, 100, 2, 0, 0, 200, 0
        ORG 0o6020
        DW 0o177777, 0o177777, 0o177777, 0o177777
