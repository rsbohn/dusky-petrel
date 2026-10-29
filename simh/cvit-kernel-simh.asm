; cvit/Nova minimal resident kernel skeleton — SIMH DSK adaptation
; Adapted from sd/cvit-kernel.asm (dusky-petrel branch 1028) for SIMH Nova.
; Load with: abs adapted/cvit-kernel-simh.asm kernel.abs --format simh-load
;   then in SIMH: load kernel.abs  (auto start @ 0o1000)
; Storage: SIMH DSK device 0o20, one TC08 block per 256-word DSK sector,
;   sector = drive * 1024 + block. Only the first 128 words of a sector are
;   cvit payload; a block read overwrites 256 words at the destination and
;   a block write writes 256 words from the source (second half ignored).
; Console: DOAS for output, DIAC for input (see command file for input).
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
;   4 = read block, CB is the block control block (drive/block/address)
;   5 = write block, CB is the block control block (drive/block/address)

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
        DOAS AC0, TTO
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

; ---- SIMH DSK block I/O ----
; READBLK / WRITEBLK: AC2 points at:
;   +0 drive (0=TC0, 1=TC1)
;   +1 block
;   +2 memory address
; SIMH DSK (device 0o20): DOA = sector, DOB = memory address,
;   NIOS = read, NIOP = write, SKPDN polls DONE, DIA = error bits (0 = ok).
; Sector = drive * 1024 + block (disk 0 = TC0, disk 1 = TC1).
; Return AC0 = 1 on success, 5 on any DSK error, preserving the old
; TC08 convention (done bit + error bit) that callers test against 1.
; A transfer moves a full 256-word sector; only the first 128 words are
; cvit payload, so block buffers need 256 words of headroom.

READBLK:
        STA AC3, RDBRET
        LDA AC0, 1,AC2
        LDA AC1, 0,AC2
        MOV AC1, AC1, SNR
        JMP RDBSEC
        LDA AC1, DSKOFF
        ADD AC1, AC0
RDBSEC: DOA AC0, DSK
        LDA AC0, 2,AC2
        DOB AC0, DSK
        NIOS AC0, DSK
RDBWAIT:
        SKPDN DSK
        JMP RDBWAIT
        DIA AC0, DSK
        MOV AC0, AC0, SNR
        JMP RDBOK
        LDA AC0, FIVE
        JMP @RDBRET
RDBOK:  LDA AC0, ONE
        JMP @RDBRET

WRITEBLK:
        STA AC3, WRBRET
        LDA AC0, 1,AC2
        LDA AC1, 0,AC2
        MOV AC1, AC1, SNR
        JMP WRBSEC
        LDA AC1, DSKOFF
        ADD AC1, AC0
WRBSEC: DOA AC0, DSK
        LDA AC0, 2,AC2
        DOB AC0, DSK
        NIOP AC0, DSK
WRBWAIT:
        SKPDN DSK
        JMP WRBWAIT
        DIA AC0, DSK
        MOV AC0, AC0, SNR
        JMP WRBOK
        LDA AC0, FIVE
        JMP @WRBRET
WRBOK:  LDA AC0, ONE
        JMP @WRBRET

; ---- data ----

ZERO:    DW 0
ONE:     DW 1
NEG1:    DW 0o177777
NEG4:    DW 0o177774
NEG5:    DW 0o177773
DSKOFF:  DW 0o2000
FIVE:    DW 5

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
