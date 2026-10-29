; cvit/Nova minimal resident kernel skeleton
; Load with: asm sd/cvit-kernel.asm 0o1000
;
; Early ABI:
;   AC0 = selector / return code
;   AC1 = syscall control block pointer
;   AC2 = direct-call control block pointer or string pointer
;   AC3 = JSR return link

        ORG 0o1000

; Stable jump table.  Keep these entry addresses fixed.
CV_COLD: JMP COLD
CV_WARM: JMP WARM
CV_SYS:  JMP SYSCALL
CV_QUIT: JMP QUIT
CV_RDB:  JMP READBLK
CV_WRB:  JMP WRITEBLK

; ---- starts ----

COLD:   LDA AC2, BANNERP
        JSR PUTS
        HALT

WARM:   LDA AC2, PROMPTP
        JSR PUTS
        HALT

QUIT:   HALT

; ---- syscall dispatcher ----
; selector in AC0, CB in AC1.  Very small for now:
;   1 = console putc, CB+0 character
;   4 = read block, CB is TC08 block control block
;   5 = write block, CB is TC08 block control block

SYSCALL: STA AC3, SYSRET
        STA AC0, SYSSEL
        LDA AC0, SYSSEL
        LDA AC2, NEG1
        ADD AC2, AC0
        MOV AC0, AC0, SNR
        JMP SYS_PUTC
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
        JSR PUTS
        LDA AC0, ONE
        JMP @SYSRET

SYS_PUTC:
        MOV AC1, AC2
        LDA AC0, 0,AC2
        JSR PUTC
        LDA AC0, ZERO
        JMP @SYSRET

SYS_RDB:
        MOV AC1, AC2
        JSR READBLK
        JMP @SYSRET

SYS_WRB:
        MOV AC1, AC2
        JSR WRITEBLK
        JMP @SYSRET

; ---- console ----
; PUTC: AC0 low byte is emitted to TTO.

PUTC:   STA AC3, PUTCRET
PWAIT:  SKPBZ TTO
        JMP PWAIT
        DOA AC0, TTO
        JMP @PUTCRET

; PUTS: AC2 points at zero-terminated word string.
; Clobbers AC0/AC2.

PUTS:   STA AC3, PUTSRET
PLOOP:  LDA AC0, 0,AC2
        MOV AC0, AC0, SNR
        JMP @PUTSRET
        JSR PUTC
        LDA AC0, ONE
        ADD AC0, AC2
        JMP PLOOP

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

; ---- data ----

ZERO:    DW 0
ONE:     DW 1
NEG1:    DW 0o177777
NEG4:    DW 0o177774
NEG5:    DW 0o177773
CTLREAD: DW 2
CTLWRITE: DW 4

SYSSEL:  DW 0
SYSRET:  DW 0
PUTCRET: DW 0
PUTSRET: DW 0
RDBRET:  DW 0
WRBRET:  DW 0

BANNERP: DW BANNER
PROMPTP: DW PROMPT
SVCERRP: DW SVCERR

BANNER:  DW 0o015, 0o012
         .TXT "cvit/Nova V0.1"
         DW 0o015, 0o012, 0
PROMPT:  DW 0o015, 0o012, 0o135, 0
SVCERR:  DW 0o077, 0o123, 0o126, 0o103, 0o015, 0o012, 0
