; cvit/Nova minimal resident kernel
; Load with: asm sd/cvit-kernel.asm 0o1000
;
; Early ABI:
;   AC0 = selector / return code
;   AC1 = syscall control block pointer
;   AC2 = direct-call control block pointer or string pointer
;   AC3 = JSR return link
;
; Jump table vectors are stable: 0o1000-0o1005 predate the GETC/PUTC/PUTS
; vectors and keep their addresses.  Each vector jumps indirect through a
; pointer cell, so the routines themselves may live anywhere in memory.
; The dusky assembler requires direct references to span < 0o200 words;
; every routine keeps its data local and calls other routines through
; pointer cells.

        ORG 0o1000

; Stable jump table.  Keep these entry addresses fixed.
CV_COLD: JMP @V_COLD
CV_WARM: JMP @V_WARM
CV_SYS:  JMP @V_SYS
CV_QUIT: JMP @V_QUIT
CV_RDB:  JMP @V_RDB
CV_WRB:  JMP @V_WRB
CV_GETC: JMP @V_GETC
CV_PUTC: JMP @V_PUTC
CV_PUTS: JMP @V_PUTS

V_COLD:  DW COLD
V_WARM:  DW WARM
V_SYS:   DW SYSCALL
V_QUIT:  DW QUIT
V_RDB:   DW READBLK
V_WRB:   DW WRITEBLK
V_GETC:  DW GETC
V_PUTC:  DW PUTC
V_PUTS:  DW PUTS

; ---- starts ----

COLD:   LDA AC2, BANNERP
        JSR @P_PUTS
        JSR @P_LOADCMD
        ; LOADCMD returns only on failure, after printing an error.
        HALT

BANNERP: DW BANNER
P_PUTS:  DW PUTS
P_LOADCMD: DW LOADCMD

BANNER:  DW 0o015, 0o012
         .TXT "cvit/Nova V0.1"
         DW 0o015, 0o012, 0

WARM:   LDA AC2, PROMPTP
        JSR @P_PUTS2
        HALT

PROMPTP: DW PROMPT
P_PUTS2: DW PUTS

PROMPT:  DW 0o015, 0o012, 0o135, 0

QUIT:   HALT

; ---- syscall dispatcher ----
; selector in AC0, CB in AC1.  Very small for now:
;   1 = console putc, CB+0 character
;   2 = console getc, returns character in AC0
;   3 = console puts, CB points at zero-terminated string
;   4 = read block, CB is TC08 block control block
;   5 = write block, CB is TC08 block control block

SYSCALL:STA AC3, SYSRET
        STA AC0, SYSSEL
        LDA AC0, SYSSEL
        LDA AC2, NEG1
        ADD AC2, AC0
        MOV AC0, AC0, SNR
        JMP SYS_PUTC
        LDA AC0, SYSSEL
        LDA AC2, NEG2
        ADD AC2, AC0
        MOV AC0, AC0, SNR
        JMP SYS_GETC
        LDA AC0, SYSSEL
        LDA AC2, NEG3
        ADD AC2, AC0
        MOV AC0, AC0, SNR
        JMP SYS_PUTS
        LDA AC0, SYSSEL
        LDA AC2, NEG4
        ADD AC2, AC0
        MOV AC0, AC0, SNR
        JMP SYS_RDB
        LDA AC0, SYSSEL
        LDA AC2, NEG5
        ADD AC2, AC0
        MOV AC0, AC0, SNR
        JMP SYS_WRB
        LDA AC2, SVCERRP
        JSR @P_PUTS3
        LDA AC0, ONE
        JMP @SYSRET

SYS_PUTC:
        MOV AC1, AC2
        LDA AC0, 0,AC2
        JSR @P_PUTC
        LDA AC0, ZERO
        JMP @SYSRET

SYS_GETC:
        JSR @P_GETC
        JMP @SYSRET

SYS_PUTS:
        MOV AC1, AC2
        JSR @P_PUTS4
        LDA AC0, ZERO
        JMP @SYSRET

SYS_RDB:
        MOV AC1, AC2
        JSR @P_RDBLK
        JMP @SYSRET

SYS_WRB:
        MOV AC1, AC2
        JSR @P_WRBLK
        JMP @SYSRET

SYSSEL:  DW 0
SYSRET:  DW 0
NEG1:    DW 0o177777
NEG2:    DW 0o177776
NEG3:    DW 0o177775
NEG4:    DW 0o177774
NEG5:    DW 0o177773
ZERO:    DW 0
ONE:     DW 1
P_PUTC:  DW PUTC
P_GETC:  DW GETC
P_PUTS3: DW PUTS
P_PUTS4: DW PUTS
P_RDBLK: DW READBLK
P_WRBLK: DW WRITEBLK
SVCERRP: DW SVCERR

SVCERR:  DW 0o077, 0o123, 0o126, 0o103, 0o015, 0o012, 0

; ---- console ----
; GETC: wait for one console input byte, return it in AC0.
; DIAC (DIA + clear pulse) works on both emulators: dusky ignores the
; pulse and dequeues one byte; SIMH needs the clear to drop TTI DONE.

GETC:   STA AC3, GETCRET
GWAIT:  SKPDN TTI
        JMP GWAIT
        DIAC AC0, TTI
        JMP @GETCRET

GETCRET: DW 0

; PUTC: AC0 low byte is emitted to TTO.
; DOAS (DOA + start pulse) works on both emulators: dusky ignores the
; pulse and writes once; SIMH schedules the output on the pulse.

PUTC:   STA AC3, PUTCRET
PWAIT:  SKPBZ TTO
        JMP PWAIT
        DOAS AC0, TTO
        JMP @PUTCRET

PUTCRET: DW 0

; PUTS: AC2 points at zero-terminated word string.
; Clobbers AC0/AC2.

PUTS:   STA AC3, PUTSRET
PLOOP:  LDA AC0, 0,AC2
        MOV AC0, AC0, SNR
        JMP @PUTSRET
        JSR @P_PUTC2
        LDA AC0, ONE2
        ADD AC0, AC2
        JMP PLOOP

PUTSRET: DW 0
P_PUTC2: DW PUTC
ONE2:    DW 1

; ---- TC08 block I/O ----
; READBLK / WRITEBLK: AC2 points at:
;   +0 drive (0=TC0, 1=TC1)
;   +1 block
;   +2 memory address
; Return AC0 = TC08 status word (bit 2 means error in the emulator).

READBLK:
        STA AC3, RDBRET
        LDA AC0, 2,AC2
        DOA AC0, DSK
        LDA AC0, 1,AC2
        DOB AC0, DSK
        LDA AC0, 0,AC2
        LDA AC1, CTLREAD
        ADD AC1, AC0
        DOC AC0, DSK
        NIOP AC0, DSK
RDBWAIT:
        SKPDN DSK
        JMP RDBWAIT
        DIC AC0, DSK
        JMP @RDBRET

RDBRET:  DW 0
CTLREAD: DW 2

WRITEBLK:
        STA AC3, WRBRET
        LDA AC0, 2,AC2
        DOA AC0, DSK
        LDA AC0, 1,AC2
        DOB AC0, DSK
        LDA AC0, 0,AC2
        LDA AC1, CTLWRITE
        ADD AC1, AC0
        DOC AC0, DSK
        NIOP AC0, DSK
WRBWAIT:
        SKPDN DSK
        JMP WRBWAIT
        DIC AC0, DSK
        JMP @WRBRET

WRBRET:  DW 0
CTLWRITE: DW 4

; ---- LCMP ----
; LCMP: AC2 points at the directory entry.  AC0=1 if its 5 name words
; match CMDNAME, else 0.  Clobbers AC0/AC2/AC3.

LCMP:   STA AC3, LCMPRET
        STA AC2, LCMPTR
        LDA AC2, CMDNAMP
        STA AC2, LCMNPTR
        LDA AC0, FIVE2
        STA AC0, LCMCNT
LCMPLP: LDA AC2, LCMPTR
        LDA AC0, 0,AC2
        LDA AC2, LCMNPTR
        LDA AC3, 0,AC2
        SUBZ AC3, AC0
        JMP LCM_BAD
        LDA AC3, LCMPTR
        LDA AC0, ONE3
        ADD AC0, AC3
        STA AC3, LCMPTR
        LDA AC3, LCMNPTR
        LDA AC0, ONE3
        ADD AC0, AC3
        STA AC3, LCMNPTR
        LDA AC3, LCMCNT
        LDA AC0, NEG12
        ADD AC0, AC3
        STA AC3, LCMCNT
        MOV AC3, AC3, SNR
        JMP LCM_GOOD
        JMP LCMPLP
LCM_BAD:LDA AC0, ZERO2
        JMP @LCMPRET
LCM_GOOD:LDA AC0, ONE3
        JMP @LCMPRET

LCMPRET: DW 0
LCMPTR:  DW 0
LCMNPTR: DW 0
LCMCNT:  DW 0
CMDNAME: DW 0o41517, 0o46515, 0o40516, 0o42040, 0o20040
CMDNAMP: DW CMDNAME
CMD0:    DW 0o41517
CMD1:    DW 0o46515
CMD2:    DW 0o40516
CMD3:    DW 0o42040
CMD4:    DW 0o20040
FIVE2:   DW 5
ZERO2:   DW 0
ONE3:    DW 1
NEG12:   DW 0o177777

; ---- cold-start loader ----
; LOADCMD reads the TC0 directory (block 1) into DIRBUF, finds the
; COMMAND member, loads its blocks at the directory load address, and
; jumps to the directory entry address.  Returns (to COLD, which halts)
; only on failure, after printing an error.

LOADCMD:STA AC3, LCRET
        LDA AC2, DSKCBP
        JSR @P_RDBLK2
        LDA AC3, ONE4
        SUBZ AC3, AC0
        MOV AC0, AC0, SNR
        JMP LD_DIROK
        LDA AC2, DSKERRP
        JSR @P_PUTS5
        JMP @LCRET
LD_DIROK:
        LDA AC2, DSKCBP
        LDA AC0, 2,AC2
        STA AC0, LENTPTR
        LDA AC0, NENTS
        STA AC0, LENTCNT
LD_SCAN:LDA AC2, LENTPTR
        LDA AC0, 0,AC2
        MOV AC0, AC0, SNR
        JMP LD_NEXT
        LDA AC3, CMD0
        SUBZ AC3, AC0
        MOV AC0, AC0, SNR
        JMP CHK1
        JMP LD_NEXT
CHK1:   LDA AC0, 1,AC2
        LDA AC3, CMD1
        SUBZ AC3, AC0
        MOV AC0, AC0, SNR
        JMP CHK2
        JMP LD_NEXT
CHK2:   LDA AC0, 2,AC2
        LDA AC3, CMD2
        SUBZ AC3, AC0
        MOV AC0, AC0, SNR
        JMP CHK3
        JMP LD_NEXT
CHK3:   LDA AC0, 3,AC2
        LDA AC3, CMD3
        SUBZ AC3, AC0
        MOV AC0, AC0, SNR
        JMP CHK4
        JMP LD_NEXT
CHK4:   LDA AC0, 4,AC2
        LDA AC3, CMD4
        SUBZ AC3, AC0
        MOV AC0, AC0, SNR
        JMP LD_FOUND
        JMP LD_NEXT
LD_NEXT:LDA AC3, LENTPTR
        LDA AC0, ENTWORDS
        ADD AC0, AC3
        STA AC3, LENTPTR
        LDA AC3, LENTCNT
        LDA AC0, NEG13
        ADD AC0, AC3
        STA AC3, LENTCNT
        MOV AC3, AC3, SNR
        JMP LD_MISS
        JMP LD_SCAN
LD_MISS:LDA AC2, NOCMDP
        JSR @P_PUTS5
        JMP @LCRET
LD_FOUND:
        LDA AC2, LENTPTR
        LDA AC0, 6,AC2
        STA AC0, LSTART
        LDA AC0, 7,AC2
        STA AC0, LCOUNT
        ; The assembler only allows single-digit indexed displacements,
        ; so reach entry+8/+9 by bumping the pointer by 2 first.
        LDA AC3, LENTPTR
        LDA AC0, ONE4
        ADD AC0, AC3
        ADD AC0, AC3
        STA AC3, LTMP
        LDA AC2, LTMP
        LDA AC0, 6,AC2
        STA AC0, LLOAD
        LDA AC0, 7,AC2
        STA AC0, LENTRY
        LDA AC0, LSTART
        STA AC0, LBLK
LD_BLP:  LDA AC3, LCOUNT
        MOV AC3, AC3, SNR
        JMP LD_GO
        LDA AC2, DSKCB
        LDA AC0, LBLK
        STA AC0, 1,AC2
        LDA AC0, LLOAD
        STA AC0, 2,AC2
        JSR @P_RDBLK2
        LDA AC3, ONE4
        SUBZ AC3, AC0
        MOV AC0, AC0, SNR
        JMP LD_BOK
        LDA AC2, DSKERRP
        JSR @P_PUTS5
        JMP @LCRET
LD_BOK:  LDA AC3, LBLK
        LDA AC0, ONE4
        ADD AC0, AC3
        STA AC3, LBLK
        LDA AC3, LLOAD
        LDA AC0, BLKWD
        ADD AC0, AC3
        STA AC3, LLOAD
        LDA AC3, LCOUNT
        LDA AC0, NEG13
        ADD AC0, AC3
        STA AC3, LCOUNT
        JMP LD_BLP
LD_GO:  JMP @LENTRY

LCRET:   DW 0
LENTPTR: DW 0
LENTCNT: DW 0
LSTART:  DW 0
LCOUNT:  DW 0
LLOAD:   DW 0
LENTRY:  DW 0
LBLK:    DW 0
LTMP:    DW 0
DSKCB:   DW 0
         DW 1
         DW DIRBUF
DSKCBP:  DW DSKCB
NENTS:   DW 0o12
ENTWORDS:DW 0o14
ONE4:    DW 1
NEG13:   DW 0o177777
FIVE3:   DW 5
BLKWD:   DW 0o200
P_RDBLK2: DW READBLK
P_PUTS5: DW PUTS
P_LCMP:  DW LCMP
DSKERRP: DW DSKERR
NOCMDP:  DW NOCMD

DSKERR:  DW 0o077
         .TXT "DSK"
         DW 0o015, 0o012, 0
NOCMD:   DW 0o077
         .TXT "NOCMD"
         DW 0o015, 0o012, 0

; Directory scratch buffer.  Kept clear of the kernel, COMMAND (0o3000+),
; and the 0o7600 block buffer.
        ORG 0o2000
DIRBUF:
         DW 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
         DW 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
         DW 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
         DW 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
         DW 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
         DW 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
         DW 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
         DW 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
