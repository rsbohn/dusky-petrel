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
          DW 0o77000
EDISKP:  DW EDISK
EREAD:   DW 0o1004
EBUFP:   DW 0o77000
EONE:    DW 1
ETWO:    DW 2
ETHREE:  DW 3
ELINKP:  DW 0o77162
ELIMIT:  DW 0o1767
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

; LOOKUP: syscall 7. AC1 = [drive, packed-name pointer, output pointer].
; Return 0 found, 1 not found, 2 I/O error, 3 invalid volume/directory.
; Uses a private enumeration cursor; not reentrant.
        ORG 0o65400
LOOKUP: STA 3, LRET
        MOV 1,2
        LDA 0, 0,2
        STA 0, LDRIVEVAL
        LDA 0, 1,2
        STA 0, LNAME
        LDA 0, 2,2
        STA 0, LOUTPUT
        LDA 2, LCURSORP
        LDA 0, LDRIVEVAL
        STA 0, 0,2
        SUB 0,0
        STA 0, 1,2
        STA 0, 2,2
        LDA 0, LENTRYP
        STA 0, 3,2
LNEXT:  LDA 1, LCURSORP
        JSR @LENUM
        MOV 0,0,SZR
        JMP @LRET
        LDA 2, LNAME
        LDA 3, LENTRYP
        LDA 0, LFIVE
        STA 0, LCOUNT
LCMP:   LDA 0, 0,2
        LDA 1, 0,3
        SUB# 1,0,SZR
        JMP LNEXT
        INC 2,2
        INC 3,3
        LDA 0, LCOUNT
        LDA 1, LNEG1
        ADD 1,0,SZR
        JMP LCMPMORE
        JMP LMATCH
LCMPMORE:
        STA 0, LCOUNT
        JMP LCMP
LMATCH: LDA 2, LENTRYP
        LDA 3, LOUTPUT
        LDA 0, LTWELVE
        STA 0, LCOUNT
LCOPY:  LDA 0, 0,2
        STA 0, 0,3
        INC 2,2
        INC 3,3
        LDA 0, LCOUNT
        LDA 1, LNEG1
        ADD 1,0,SZR
        JMP LCOPYMORE
        SUB 0,0
        JMP @LRET
LCOPYMORE:
        STA 0, LCOUNT
        JMP LCOPY
LRET: DW 0
LDRIVEVAL: DW 0
LNAME: DW 0
LOUTPUT: DW 0
LCOUNT: DW 0
LFIVE: DW 5
LTWELVE: DW 0o14
LNEG1: DW 0o177777
LENUM: DW 0o65003
; The private cursor and entry use the kernel's reserved DIRBUF area.
; Cursor: 0o2040..0o2143; entry: 0o2144..0o2157.
LCURSORP: DW 0o2040
LENTRYP: DW 0o2144

; WRITEEXT: syscall 9, write a previously reserved contiguous extent.
; AC1 = [drive, start block, source address, word length]. The caller owns
; the reservation and must not pass a live extent. Status: 0 success,
; 2 I/O error, 3 invalid arguments / out of range. Shared scratch is not
; reentrant. The final filesystem block and each sector's second half are
; zero-padded. Zero length writes one all-zero block.
        ORG 0o65600
WRITEEXT:
        STA 3, WRET
        MOV 1,2
        LDA 0, 0,2
        LDA 1, WTWO
        SUBZ# 1,0,SZC
        JMP WBAD
        STA 0, WDISK
        LDA 0, 1,2
        LDA 1, WTWO
        SUBZ# 1,0,SNC
        JMP WBAD
        LDA 1, WDISKLIMIT
        SUBZ# 1,0,SZC
        JMP WBAD
        STA 0, WBLOCK
        LDA 0, 2,2
        LDA 1, WMEMLIMIT
        SUBZ# 1,0,SZC
        JMP WBAD
        STA 0, WSOURCE
        LDA 0, 3,2
        LDA 1, WMEMPLUS
        SUBZ# 1,0,SZC
        JMP WBAD
        STA 0, WREMAIN
        LDA 1, WSOURCE
        ADD 1,0
        LDA 1, WMEMPLUS
        SUBZ# 1,0,SZC
        JMP WBAD
        ; Calculate max(1, ceil(length / 128)) before writing anything.
        LDA 0, WREMAIN
        LDA 1, WROUND
        ADD 1,0
        MOVZR 0,0
        MOVZR 0,0
        MOVZR 0,0
        MOVZR 0,0
        MOVZR 0,0
        MOVZR 0,0
        MOVZR 0,0
        MOV 0,0,SNR
        INC 0,0
        LDA 1, WBLOCK
        ADD 1,0
        LDA 1, WDISKPLUS
        SUBZ# 1,0,SZC
        JMP WBAD
WNEXT:  LDA 2, WBUFFERP
        LDA 0, W256
        STA 0, WCOUNT
        SUB 0,0
WCLEAR: STA 0, 0,2
        INC 2,2
        DSZ WCOUNT
        JMP WCLEAR
        LDA 2, WBUFFERP
        LDA 3, WSOURCE
        LDA 0, W128
        STA 0, WCOUNT
WCOPY:  LDA 0, WREMAIN
        MOV 0,0,SNR
        JMP WFLUSH
        LDA 0, 0,3
        STA 0, 0,2
        INC 2,2
        INC 3,3
        LDA 0, WREMAIN
        LDA 1, WNEG1
        ADD 1,0
        STA 0, WREMAIN
        DSZ WCOUNT
        JMP WCOPY
WFLUSH: STA 3, WSOURCE
        LDA 2, WDISKP
        JSR @WKWRITE
        LDA 1, WONE
        SUB# 1,0,SZR
        JMP WIO
        LDA 0, WREMAIN
        MOV 0,0,SNR
        JMP WOK
        ISZ WBLOCK
        JMP WNEXT
        JMP WNEXT
WOK:    SUB 0,0
        JMP @WRET
WBAD:   LDA 0, WTHREE
        JMP @WRET
WIO:    LDA 0, WTWO
        JMP @WRET
WRET: DW 0
WSOURCE: DW 0
WREMAIN: DW 0
WCOUNT: DW 0
WDISK: DW 0
WBLOCK: DW 0
        DW 0o77000
WDISKP: DW WDISK
WKWRITE: DW 0o1005
WBUFFERP: DW 0o77000
WONE: DW 1
WTWO: DW 2
WTHREE: DW 3
W128: DW 0o200
W256: DW 0o400
WROUND: DW 0o177
WNEG1: DW 0o177777
WMEMLIMIT: DW 0o65000
WMEMPLUS: DW 0o65001
WDISKLIMIT: DW 0o1767
WDISKPLUS: DW 0o1770

; Full-sector DMA scratch buffer.
; The 256-word I/O buffer is at 0o77000, outside the loaded extension.

; PUBLISH: syscall 10. AC1 -> [drive, pointer to 12-word entry].
; Status: 0 published, 1 duplicate, 2 I/O error, 3 invalid input/volume,
; 4 directory full. Selector 11 uses the same CB and validation but only
; checks whether publication is possible, without writing or reserving.
; Only existing linked directory blocks are used; no directory growth.
        ORG 0o67000
PUBLISH: JMP PRPUB
PUBCHECK:JMP PRCHECK
PRPUB:  SUB 0,0
        JMP PRSTART
PRCHECK:LDA 0, PRONE
        JMP PRSTART
PRREADP: DW PRREAD
PRONE: DW 1
PRTHREE: DW 3
PRENTRY: DW 0
PRINDEX: DW 0
PRSLOTP: DW 0
PRCOUNT: DW 0
PRLOOKP: DW LOOKUP
PRLOOKCBP:DW PRLOOKCB
PRLOOKCB:DW 0,0,PRFOUND
PRFOUND: DW 0,0,0,0,0,0,0,0,0,0,0,0
PRROOT: DW EROOT
PRSCAN: DW 0
PRRET:  DW 0
PRSTART:STA 3, PRRET
        STA 0, PRSCAN
        MOV 1,2
        LDA 0, 0,2
        LDA 1, PRTWO
        SUBZ# 1,0,SZC
        JMP PRBAD
        STA 0, PRDRIVE
        STA 0, PRLOOKCB
        LDA 0, 1,2
        MOV 0,0,SNR
        JMP PRBAD
        STA 0, PRENTRY
        STA 0, PRLOOKCB+1
        ; Validate type is TXT, BIN, or SYS and the entry is live.
        MOV 0,2
        LDA 0, 5,2
        MOV 0,0,SNR
        JMP PRBAD
        LDA 1, PRFOUR
        SUBZ# 1,0,SZC
        JMP PRBAD
        LDA 0, 0,2
        MOV 0,0,SNR
        JMP PRBAD
        LDA 0, 13,2
        LDA 1, PRHIGH
        AND 1,0,SZR
        JMP PRBAD
        ; Reject a duplicate even if an earlier slot is free. An absent
        ; name means LOOKUP validated the complete chain, including EROOT.
        LDA 1, PRLOOKCBP
        JSR @PRLOOKP
        MOV 0,0,SNR
        JMP PRDUP
        LDA 1, PRONE
        SUB# 1,0,SZR
        JMP @PRRET          ; propagate I/O or malformed directory
        LDA 0, @PRROOT
        STA 0, PRBLOCK
PRBLOCKLP:
        JSR @PRREADP
        LDA 1, PRONE
        SUB# 1,0,SZR
        JMP PRIO
        LDA 0, PRZERO
        STA 0, PRINDEX
PRSLOT:
        LDA 0, PRINDEX
        LDA 1, PRNINE
        SUBZ# 1,0,SZC
        JMP PRLINK
        ; Slot offset = index * 12.
        MOV 0,2
        MOVZL 0,0
        ADD 2,0
        MOVZL 0,0
        MOVZL 0,0
        LDA 2, PRBUFP
        ADD 0,2
        STA 2, PRSLOTP
        LDA 0, 0,2
        MOV 0,0,SNR
        JMP PRSTORE
        ; Entry occupies twelve words. A marked tombstone (word 11 high bit)
        ; is also available for reuse.
        LDA 2, PRSLOTP
        LDA 1, PRELEVEN
        ADD 1,2
        LDA 0, 0,2
        LDA 1, PRHIGH
        AND 1,0,SZR
        JMP PRSTORE
        ISZ PRINDEX
        JMP PRSLOT
PRLINK: LDA 2, PRLINKP
        LDA 0, 0,2
        MOV 0,0,SNR
        JMP PRFULL
        STA 0, PRBLOCK
        LDA 1, PRMAXBLOCK
        SUBZ# 1,0,SZC
        JMP PRBAD
        JMP PRBLOCKLP
PRSTORE:LDA 0, PRSCAN
        MOV 0,0,SZR
        JMP PROK
        LDA 2, PRENTRY
        LDA 3, PRSLOTP
        LDA 1, PRTWELVE
        STA 1, PRCOUNT
PRCOPY: LDA 0, 0,2
        STA 0, 0,3
        INC 2,2
        INC 3,3
        ISZ PRCOUNT
        JMP PRCOPY
        ; Write the entire directory sector back, preserving other words.
        LDA 2, PRDISKP
        JSR @PRWRITE
        LDA 1, PRONE
        SUB# 1,0,SZR
        JMP PRIO
PROK:   SUB 0,0
        JMP @PRRET
PRDUP:  LDA 0, PRONE
        JMP @PRRET
PRBAD:  LDA 0, PRTHREE
        JMP @PRRET
PRFULL: LDA 0, PRFOUR
        JMP @PRRET
PRIO:   LDA 0, PRTWO
        JMP @PRRET

; Read one filesystem payload block into the extension sector buffer.
PRREAD: LDA 2, PRDISKP
        JMP @PRRDV
PRRDV:  DW 0o1004
PRWRITE:DW 0o1005
PRDISKP:DW PRDRIVE
PRDRIVE:DW 0
PRBLOCK:DW 0
        DW 0o77000
PRBUFP: DW 0o77000
PRTWO:  DW 2
PRFOUR: DW 4
PRNINE: DW 0o11
PRTWELVE: DW 0o177764 ; -12 words for the ISZ copy loop
PRELEVEN: DW 0o13
PRHIGH: DW 0o100000
PRZERO: DW 0
PRMAXBLOCK: DW 0o1767
PRLINKP: DW 0o77162

