; cvit/Nova minimal command interpreter
; Load with: asm sd/cvit-command.asm 0o3000
;
; Commands:
;   CAT    read TC0 block 1 into 0o7600 and list flat directory names
;   STA    read TC0 block 0 and report volume status
;   EOT    halt

; Keep mutable cells and constants on page zero so code at 0o3000 can reach them.
        ORG 0o0050

ZERO:    DW 0
ONE:     DW 1
NEG1:    DW 0o177777
FIVE:    DW 5
NENTS:   DW 0o12
ENTWORDS:DW 0o14
CTLREAD: DW 2

RBRACK:  DW 0o135
CHC:     DW 0o103
CHS:     DW 0o123
CHA:     DW 0o101
CHT:     DW 0o124
CR:      DW 0o015
LF:      DW 0o012
EOT:     DW 0o004
SPACE:   DW 0o040
MAGIC0:  DW 0o41526    ; "CV"
MAGIC1:  DW 0o47126    ; "NV"

PUTCP:   DW PUTC
PUTSP:   DW PUTS
GETLINEP:DW GETLINE
PNAMEP:  DW PNAME
PNCHP:   DW PNCH
READBLKP:DW READBLK
LINEP:   DW LINE
DIRP:    DW 0o7600
RDBCBP:  DW RDBCB
STACBP:  DW STACB
HELLOP:  DW HELLO
BADP:    DW BADMSG
DSKERRP: DW DSKERR
VOLERRP: DW VOLERR
CATHEADP:DW CATHEAD
STAMSGP: DW STAMSG
NLP:     DW NL

PUTCRET: DW 0
PUTSRET: DW 0
GLRET:   DW 0
RDBRET:  DW 0
PNRET:   DW 0
PNCHRET: DW 0
CH:      DW 0
EOTSEEN: DW 0
ENTPTR:  DW 0
ENTCNT:  DW 0
PNPTR:   DW 0
PNCNT:   DW 0
PNCHAR:  DW 0

RDBCB:   DW 0          ; TC0
         DW 1          ; directory block
         DW 0o7600     ; buffer
STACB:   DW 0          ; TC0
         DW 0          ; volume header block
         DW 0o7600     ; buffer

LINE:    DW 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0

        ORG 0o3000

START:  LDA AC2, HELLOP
        JSR @PUTSP

PROMPT: LDA AC0, RBRACK
        JSR @PUTCP
        LDA AC2, LINEP
        JSR @GETLINEP
        LDA AC0, EOTSEEN
        MOV AC0, AC0, SNR
        JMP CHECK
        HALT

CHECK:  LDA AC2, LINEP
        LDA AC0, 0,AC2
        MOV AC0, AC0, SNR
        JMP PROMPT
        LDA AC3, CHC
        SUBZ AC3, AC0
        MOV AC0, AC0, SNR
        JMP CHK_CA
        LDA AC2, LINEP
        LDA AC0, 0,AC2
        LDA AC3, CHS
        SUBZ AC3, AC0
        MOV AC0, AC0, SNR
        JMP CHK_ST
        JMP BAD
CHK_CA: LDA AC2, LINEP
        LDA AC0, 1,AC2
        LDA AC3, CHA
        SUBZ AC3, AC0
        MOV AC0, AC0, SNR
        JMP CHK_CAT
        JMP BAD
CHK_CAT:LDA AC2, LINEP
        LDA AC0, 2,AC2
        LDA AC3, CHT
        SUBZ AC3, AC0
        MOV AC0, AC0, SNR
        JMP DO_CAT
        JMP BAD
CHK_ST: LDA AC2, LINEP
        LDA AC0, 1,AC2
        LDA AC3, CHT
        SUBZ AC3, AC0
        MOV AC0, AC0, SNR
        JMP CHK_STA
        JMP BAD
CHK_STA:LDA AC2, LINEP
        LDA AC0, 2,AC2
        LDA AC3, CHA
        SUBZ AC3, AC0
        MOV AC0, AC0, SNR
        JMP DO_STA
        JMP BAD

BAD:    LDA AC2, BADP
        JSR @PUTSP
        JMP PROMPT

DO_CAT: LDA AC2, RDBCBP
        JSR @READBLKP
        LDA AC3, ONE
        SUBZ AC3, AC0
        MOV AC0, AC0, SNR
        JMP CAT_OK
        LDA AC2, DSKERRP
        JSR @PUTSP
        JMP PROMPT

CAT_OK: LDA AC2, CATHEADP
        JSR @PUTSP
        LDA AC3, DIRP
        STA AC3, ENTPTR
        LDA AC3, NENTS
        STA AC3, ENTCNT
CATLP:  LDA AC2, ENTPTR
        LDA AC0, 0,AC2
        MOV AC0, AC0, SNR
        JMP CATDONE
        JSR @PNAMEP
        LDA AC2, NLP
        JSR @PUTSP
        LDA AC3, ENTPTR
        LDA AC0, ENTWORDS
        ADD AC0, AC3
        STA AC3, ENTPTR
        LDA AC3, ENTCNT
        LDA AC0, NEG1
        ADD AC0, AC3
        STA AC3, ENTCNT
        MOV AC3, AC3, SNR
        JMP CATDONE
        JMP CATLP
CATDONE:JMP PROMPT

DO_STA: LDA AC2, STACBP
        JSR @READBLKP
        LDA AC3, ONE
        SUBZ AC3, AC0
        MOV AC0, AC0, SNR
        JMP STA_IOK
        LDA AC2, DSKERRP
        JSR @PUTSP
        JMP PROMPT
STA_IOK:LDA AC2, DIRP
        LDA AC0, 0,AC2
        LDA AC3, MAGIC0
        SUBZ AC3, AC0
        MOV AC0, AC0, SNR
        JMP STA_M1
        LDA AC2, VOLERRP
        JSR @PUTSP
        JMP PROMPT
STA_M1: LDA AC2, DIRP
        LDA AC0, 1,AC2
        LDA AC3, MAGIC1
        SUBZ AC3, AC0
        MOV AC0, AC0, SNR
        JMP STA_OK
        LDA AC2, VOLERRP
        JSR @PUTSP
        JMP PROMPT
STA_OK: LDA AC2, STAMSGP
        JSR @PUTSP
        JMP PROMPT

; ---- console ----

PUTC:   STA AC3, PUTCRET
PWAIT:  SKPBZ TTO
        JMP PWAIT
        DOA AC0, TTO
        JMP @PUTCRET

; PUTS: AC2 points to zero-terminated one-char-per-word string.
PUTS:   STA AC3, PUTSRET
PSLP:   LDA AC0, 0,AC2
        MOV AC0, AC0, SNR
        JMP @PUTSRET
        JSR @PUTCP
        LDA AC0, ONE
        ADD AC0, AC2
        JMP PSLP

; GETLINE: AC2 destination, zero-terminates. Sets EOTSEEN.
GETLINE:STA AC3, GLRET
        LDA AC0, ZERO
        STA AC0, EOTSEEN
GLLP:   SKPDN TTI
        JMP GLLP
        DIA AC0, TTI
        STA AC0, CH
        LDA AC3, EOT
        SUBZ AC3, AC0
        MOV AC0, AC0, SNR
        JMP GL_EOT
        LDA AC0, CH
        LDA AC3, CR
        SUBZ AC3, AC0
        MOV AC0, AC0, SNR
        JMP GL_DONE
        LDA AC0, CH
        LDA AC3, LF
        SUBZ AC3, AC0
        MOV AC0, AC0, SNR
        JMP GL_DONE
        LDA AC0, CH
        STA AC0, 0,AC2
        JSR @PUTCP
        LDA AC0, ONE
        ADD AC0, AC2
        JMP GLLP
GL_EOT: LDA AC0, ONE
        STA AC0, EOTSEEN
GL_DONE:LDA AC0, ZERO
        STA AC0, 0,AC2
        LDA AC2, NLP
        JSR @PUTSP
        JMP @GLRET

; PNAME: AC2 points to directory entry. Prints five packed name words.
PNAME:  STA AC3, PNRET
        STA AC2, PNPTR
        LDA AC3, FIVE
        STA AC3, PNCNT
PNLP:   LDA AC0, @PNPTR
        MOVS AC0, AC0
        JSR @PNCHP
        LDA AC0, @PNPTR
        JSR @PNCHP
        LDA AC3, PNPTR
        LDA AC0, ONE
        ADD AC0, AC3
        STA AC3, PNPTR
        LDA AC3, PNCNT
        LDA AC0, NEG1
        ADD AC0, AC3
        STA AC3, PNCNT
        MOV AC3, AC3, SNR
        JMP @PNRET
        JMP PNLP
PNCH:   STA AC3, PNCHRET
        STA AC0, PNCHAR
        LDA AC3, SPACE
        SUBZ AC3, AC0
        MOV AC0, AC0, SNR
        JMP @PNCHRET
        LDA AC0, PNCHAR
        JSR @PUTCP
        JMP @PNCHRET

; ---- TC08 block I/O ----
; READBLK: AC2 -> drive, block, memory address. Return AC0=status.
READBLK:STA AC3, RDBRET
        LDA AC0, 2,AC2
        DOA AC0, DSK
        LDA AC0, 1,AC2
        DOB AC0, DSK
        LDA AC0, 0,AC2
        LDA AC3, CTLREAD
        ADD AC3, AC0
        DOC AC0, DSK
        NIOP AC0, DSK
RDBWAIT:SKPDN DSK
        JMP RDBWAIT
        DIC AC0, DSK
        JMP @RDBRET

HELLO:   DW 0o015, 0o012
         .TXT "cvit/Nova COMMAND V0.1"
         DW 0o015, 0o012, 0
BADMSG:  DW 0o077
         .TXT "WHAT"
         DW 0o015, 0o012, 0
DSKERR:  DW 0o077
         .TXT "DSK"
         DW 0o015, 0o012, 0
VOLERR:  DW 0o077
         .TXT "VOL"
         DW 0o015, 0o012, 0
CATHEAD: .TXT "TC0:"
         DW 0o015, 0o012, 0
STAMSG:  .TXT "TC0: CVNV READY"
         DW 0o015, 0o012, 0
NL:      DW 0o015, 0o012, 0
