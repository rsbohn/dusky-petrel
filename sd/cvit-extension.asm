; CVIT resident extension, loaded at 0o65000 by the disk bootstrap.
; Initial entry is a probe: returns 0o12345 in AC0, preserving AC3.
        ORG 0o65000
EXT_PROBE: LDA 0, SIGNATURE
        JMP 0,3
SIGNATURE: DW 0o12345

; ENUMFIRST: syscall 6, preliminary chained-directory enumeration.
; AC1 points to [drive, directory block, index, output pointer]. Returns
; AC0: 0 success, 1 end, 2 disk error, 3 invalid link. Clobbers AC1-AC3.
; Initialize block and index to zero. CB words 4..67 hold the visited bitmap.
ENUMFIRST:
        STA 3, ERET
        STA 1, ECBPTR
        MOV 1,2
        LDA 0, 0,2
        STA 0, EDISK
        LDA 0, 1,2
        MOV 0,0,SNR
        JMP ESTART
        LDA 1, ENEG1
        SUB# 1,0,SNR
        JMP EENDRET
        LDA 1, ENEG2
        SUB# 1,0,SNR
        JMP EBADRET
        JMP ELOAD
ESTART: JSR @EVALIDP
        MOV 0,0,SZR
        JMP EFAIL
        JSR @EINITP
        LDA 0, EROOT
        JSR @EMARKP
        MOV 0,0,SZR
        JMP EFAIL
        LDA 0, EROOT
        LDA 2, ECBPTR
        STA 0, 1,2
ELOAD:  STA 0, EDISKBLK
        LDA 2, EDISKP
        JSR @EREAD
        LDA 1, EONE
        SUB# 1,0,SZR
        JMP EIOERR
ELOOP:  LDA 2, ECBPTR
        LDA 0, 2,2
        LDA 2, ENINE
        SUBZ# 2,0,SZC
        JMP ENEXT
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
; The tenth directory slot is a link; word 6 is the next block.
ENEXT:  LDA 2, ELINKP
        LDA 0, 0,2
        MOV 0,0,SNR
        JMP EEND
        LDA 1, ELIMIT
        SUBZ# 1,0,SZC
        JMP EBAD
        STA 0, ENEXTBLK
        JSR @EMARKP
        MOV 0,0,SZR
        JMP EFAIL
        LDA 0, ENEXTBLK
        LDA 2, ECBPTR
        STA 0, 1,2
        SUB 1,1
        STA 1, 2,2
        JMP ELOAD
EEND:   LDA 2, ECBPTR
        LDA 0, ENEG1
        STA 0, 1,2
EENDRET:LDA 0, EONE
        JMP @ERET
EBAD:   LDA 0, ETHREE
        JMP EFAIL
EIOERR: LDA 0, ETWO
EFAIL:  LDA 2, ECBPTR
        LDA 1, ENEG2
        STA 1, 1,2
        JMP @ERET
EBADRET:LDA 0, ETHREE
        JMP @ERET
ERET:    DW 0
ECBPTR:  DW 0
EENTRY:  DW 0
ECOUNT:  DW 0
EDISK:   DW 0
EDISKBLK: DW 1
          DW EBUFFER
EDISKP:  DW EDISK
EREAD:   DW 0o1004
EBUFP:   DW EBUFFER
EONE:    DW 1
ETWO:    DW 2
ETHREE:  DW 3
ELINKP:  DW EBUFFER+0o162
ELIMIT:  DW 0o1772
ENINE:   DW 0o11
EELEVEN: DW 0o13
ETWELVE: DW 0o14
ENEG1:   DW 0o177777
ENEG2:   DW 0o177776
EHIGH:   DW 0o100000
EVALIDP: DW EVALID
EINITP:  DW EINIT
EMARKP:  DW EMARK
EROOT:   DW 0
ENEXTBLK: DW 0

; Check header magic, version, and root directory block before enumeration.
EVALID: STA 3, EVRET
        SUB 0,0
        STA 0, EDISKBLK
        LDA 2, EDISKP
        JSR @EREAD
        LDA 1, EONE
        SUB# 1,0,SZR
        JMP EVIO
        LDA 2, EBUFP
        LDA 0, 0,2
        LDA 1, EVMAG1
        SUB# 1,0,SZR
        JMP EVBAD
        LDA 0, 1,2
        LDA 1, EVMAG2
        SUB# 1,0,SZR
        JMP EVBAD
        LDA 0, 2,2
        LDA 1, ETWO
        SUB# 1,0,SZR
        JMP EVBAD
        LDA 0, 3,2
        MOV 0,0,SNR
        JMP EVBAD
        LDA 1, ELIMIT
        SUBZ# 1,0,SZC
        JMP EVBAD
        STA 0, EROOT
        SUB 0,0
        JMP @EVRET
EVBAD:  LDA 0, ETHREE
        JMP @EVRET
EVIO:   LDA 0, ETWO
        JMP @EVRET
EVRET:  DW 0
EVMAG1: DW 0o41526
EVMAG2: DW 0o47126

; Clear the caller's 64-word visited bitmap at control-block offset 4.
EINIT:  LDA 2, ECBPTR
        LDA 0, EFOUR
        ADD 0,2
        LDA 1, ESIXTYFOUR
        SUB 0,0
EICLEAR:STA 0, 0,2
        INC 2,2
        LDA 0, ENEG1
        ADD 0,1,SZR
        JMP EIMORE
        JMP 0,3
EIMORE: SUB 0,0
        JMP EICLEAR

; Mark AC0's validated block in the caller's bitmap. AC0=3 on repeat,
; else 0. Shared scratch makes individual calls non-reentrant.
EMARK:  STA 3, EMRET
        STA 0, EMBLOCK
        MOVZR 0,0
        MOVZR 0,0
        MOVZR 0,0
        MOVZR 0,0
        LDA 2, ECBPTR
        LDA 1, EFOUR
        ADD 1,2
        ADD 0,2
        STA 2, EMPTR
        LDA 0, EMBLOCK
        LDA 1, EFIFTEEN
        AND 1,0
        STA 0, EMSHIFTS
        LDA 1, EONE
EMSHIFT:LDA 0, EMSHIFTS
        MOV 0,0,SNR
        JMP EMTEST
        MOVZL 1,1
        LDA 0, ENEG1
        LDA 2, EMSHIFTS
        ADD 0,2
        STA 2, EMSHIFTS
        JMP EMSHIFT
EMTEST: LDA 2, EMPTR
        LDA 0, 0,2
        AND# 1,0,SZR
        JMP EMDUP
        ADD 1,0             ; bit was clear, so addition sets it
        STA 0, 0,2
        SUB 0,0
        JMP @EMRET
EMDUP:  LDA 0, ETHREE
        JMP @EMRET
EMRET: DW 0
EMBLOCK: DW 0
EMPTR: DW 0
EMSHIFTS: DW 0
EFOUR: DW 4
ESIXTYFOUR: DW 0o100
EFIFTEEN: DW 0o17

; Full-sector DMA scratch buffer follows the extension code.
        ORG 0o65400
EBUFFER: DW 0

