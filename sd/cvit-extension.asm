; CVIT resident extension, loaded at 0o65000 by the disk bootstrap.
; Initial entry is a probe: returns 0o12345 in AC0, preserving AC3.
        ORG 0o65000
EXT_PROBE: LDA 0, SIGNATURE
        JMP 0,3
SIGNATURE: DW 0o12345

; ENUMFIRST: first-directory-only enumeration, syscall 6 vertical slice.
; AC1 points to [drive, reserved, index, output pointer]. Returns AC0:
; 0 success, 1 end, 2 disk error. Clobbers AC1-AC3.
; Index must initially be zero; incremented on each entry inspected.
ENUMFIRST:
        STA 3, ERET
        STA 1, ECBPTR
        MOV 1,2
        LDA 0, 0,2
        STA 0, EDISK
        LDA 2, EDISKP
        JSR @EREAD
        LDA 1, EONE
        SUB# 1,0,SZR
        JMP EIOERR
ELOOP:  LDA 2, ECBPTR
        LDA 0, 2,2
        LDA 2, ENINE
        SUBZ# 2,0,SZC
        JMP EEND
        ; entry address = buffer + index * 12
        MOV 0,2
        MOVZL 0,0
        ADD 2,0
        MOVZL 0,0
        MOVZL 0,0
        LDA 2, EBUFP
        ADD 0,2
        STA 2, EENTRY
        LDA 2, ECBPTR
        LDA 0, 2,2
        INC 0,0
        STA 0, 2,2
        LDA 2, EENTRY
        LDA 0, 0,2
        MOV 0,0,SNR
        JMP ELOOP
        ; reserved word 11, bit 15 marks a tombstone
        LDA 0, EENTRY
        LDA 1, EELEVEN
        ADD 1,0
        MOV 0,2
        LDA 0, 0,2
        LDA 1, EHIGH
        AND 1,0,SZR
        JMP ELOOP
        LDA 2, ECBPTR
        LDA 3, 3,2
        LDA 2, EENTRY
        LDA 0, ETWELVE
        STA 0, ECOUNT
ECOPY:  LDA 0, 0,2
        STA 0, 0,3
        INC 2,2
        INC 3,3
        LDA 0, ECOUNT
        LDA 1, ENEG1
        ADD 1,0,SZR
        JMP ECOPYMORE
        JMP ECOPYDONE
ECOPYMORE:
        STA 0, ECOUNT
        JMP ECOPY
ECOPYDONE:
        SUB 0,0
        JMP @ERET
EEND:   LDA 0, EONE
        JMP @ERET
EIOERR: LDA 0, ETWO
        JMP @ERET
ERET:    DW 0
ECBPTR:  DW 0
EENTRY:  DW 0
ECOUNT:  DW 0
EDISK:   DW 0, 1, EBUFFER
EDISKP:  DW EDISK
EREAD:   DW 0o1004
EBUFP:   DW EBUFFER
EONE:    DW 1
ETWO:    DW 2
ENINE:   DW 0o11
EELEVEN: DW 0o13
ETWELVE: DW 0o14
ENEG1:   DW 0o177777
EHIGH:   DW 0o100000

; Full-sector DMA scratch buffer follows the extension code.
        ORG 0o65400
EBUFFER: DW 0

