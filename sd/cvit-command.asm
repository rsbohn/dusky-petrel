; cvit/Nova command interpreter
; Load with: asm sd/cvit-command.asm 0o3000
; (Normally loaded from the CVIT filesystem by the kernel cold start;
;  see docs/cvit-nova.md.)
;
; All console and disk I/O goes through the kernel jump table at 0o1000;
; this file holds no device drivers of its own.
;
; Commands:
;   CAT    read TC0 block 1 into 0o7600 and list flat directory names
;   STA    read TC0 block 0 and report volume status
;   TYPE   print file contents (TYPE <name>)
;   EOT    return to the kernel, which halts

; Keep mutable cells and constants on page zero so code at 0o3000 can reach them.
        ORG 0o0050

ZERO:    DW 0
ONE:     DW 1
NEG1:    DW 0o177777
FIVE:    DW 5
NENTS:   DW 0o12
ENTWORDS:DW 0o14

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

; Kernel vectors (stable jump table at 0o1000).
KQUITP:  DW 0o1003
KRDBLKP: DW 0o1004
KGETCP:  DW 0o1006
KPUTCP:  DW 0o1007
KPUTSP:  DW 0o1010

GETLINEP:DW GETLINE
PNAMEP:  DW PNAME
PNCHP:   DW PNCH
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

GLRET:   DW 0
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

; TYPE command workspace
TYPENAME:DW 0,0,0,0,0,0,0,0,0,0
CHY:     DW 0o131
CHP:     DW 0o120
CHE:     DW 0o105
TEN:     DW 0o12
TYPTR:   DW 0
TYDPTR:  DW 0
TYCNT:   DW 0
TYTMP:   DW 0
TYTYPE:  DW 0
TYSTART: DW 0
TYCOUNT: DW 0
TYLEN:   DW 0
TYPECBP: DW TYPECB
TYPECB:  DW 0
         DW 0
         DW 0o7600
TYPENAMEP: DW TYPENAME
NOTFOUNDP: DW NOTFOUND
TYRETP:  DW 0
PTYPP:   DW PTYP
TYCMPP:  DW TYCMP
TYOUTP:  DW TYOUT
LOA:     DW 0o141
HIZ:     DW 0o172
HIMASK:  DW 0o100000
BYTEMASK:DW 0o377
TOUPPER: DW 0o40
TWO:     DW 2
PROMPTP: DW PROMPT

        ORG 0o3000

; START: copy the page-zero image to 0o0050, then run.
; The disk image stores: word 0 = n1 (page-zero word count), then n1
; page-zero words, then the code words.  Uses only the code-local cells
; below (AC2/AC3 are the index registers; page zero is not live until
; CPYDONE).
START:  LDA AC2, P_LOAD
        LDA AC3, P_PZDST
        LDA AC0, 0,AC2
        STA AC0, P_CNT
        LDA AC0, P_ONE
        ADD AC0, AC2
CPYLP:  LDA AC0, P_CNT
        MOV AC0, AC0, SNR
        JMP CPYDONE
        LDA AC0, 0,AC2
        STA AC0, 0,AC3
        LDA AC0, P_ONE
        ADD AC0, AC2
        ADD AC0, AC3
        LDA AC0, P_CNT
        LDA AC1, P_NEG1
        ADD AC1, AC0
        STA AC0, P_CNT
        JMP CPYLP
CPYDONE:LDA AC2, HELLOP
        JSR @KPUTSP
        JMP PROMPT

; Code-local prologue cells (valid before page zero is live).
P_LOAD:  DW 0o3000
P_PZDST: DW 0o0050
P_CNT:   DW 0
P_ONE:   DW 1
P_NEG1:  DW 0o177777

PROMPT: LDA AC0, RBRACK
        JSR @KPUTCP
        LDA AC2, LINEP
        JSR @GETLINEP
        LDA AC0, EOTSEEN
        MOV AC0, AC0, SNR
        JMP CHECK
        JMP @KQUITP

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
        LDA AC2, LINEP
        LDA AC0, 0,AC2
        LDA AC3, CHT
        SUBZ AC3, AC0
        MOV AC0, AC0, SNR
        JMP CHK_TY
        JMP BAD
CHK_TY: LDA AC2, LINEP
        LDA AC0, 1,AC2
        LDA AC3, CHY
        SUBZ AC3, AC0
        MOV AC0, AC0, SNR
        JMP CHK_TYP
        JMP BAD
CHK_TYP:LDA AC2, LINEP
        LDA AC0, 2,AC2
        LDA AC3, CHP
        SUBZ AC3, AC0
        MOV AC0, AC0, SNR
        JMP CHK_TYPE
        JMP BAD
CHK_TYPE:LDA AC2, LINEP
        LDA AC0, 3,AC2
        LDA AC3, CHE
        SUBZ AC3, AC0
        MOV AC0, AC0, SNR
        JMP DO_TYPE
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
        JSR @KPUTSP
        JMP PROMPT

DO_CAT: LDA AC2, RDBCBP
        JSR @KRDBLKP
        LDA AC3, ONE
        SUBZ AC3, AC0
        MOV AC0, AC0, SNR
        JMP CAT_OK
        LDA AC2, DSKERRP
        JSR @KPUTSP
        JMP PROMPT

CAT_OK: LDA AC2, CATHEADP
        JSR @KPUTSP
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
        JSR @KPUTSP
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
        JSR @KRDBLKP
        LDA AC3, ONE
        SUBZ AC3, AC0
        MOV AC0, AC0, SNR
        JMP STA_IOK
        LDA AC2, DSKERRP
        JSR @KPUTSP
        JMP @PROMPTP
STA_IOK:LDA AC2, DIRP
        LDA AC0, 0,AC2
        LDA AC3, MAGIC0
        SUBZ AC3, AC0
        MOV AC0, AC0, SNR
        JMP STA_M1
        LDA AC2, VOLERRP
        JSR @KPUTSP
        JMP @PROMPTP
STA_M1: LDA AC2, DIRP
        LDA AC0, 1,AC2
        LDA AC3, MAGIC1
        SUBZ AC3, AC0
        MOV AC0, AC0, SNR
        JMP STA_OK
        LDA AC2, VOLERRP
        JSR @KPUTSP
        JMP @PROMPTP
STA_OK: LDA AC2, STAMSGP
        JSR @KPUTSP
        JMP @PROMPTP

; ---- TYPE command ----
; DO_TYPE: TYPE <name> - print file contents.
; Parses name from LINE+5, uppercases, space-pads to 10 chars in TYPENAME,
; finds matching directory entry, reads blocks and outputs as text.

DO_TYPE:
        JSR @PTYPP
        LDA AC2, RDBCBP
        JSR @KRDBLKP
        LDA AC3, ONE
        SUBZ AC3, AC0
        MOV AC0, AC0, SNR
        JMP TYFIND
        LDA AC2, DSKERRP
        JSR @KPUTSP
        JMP @PROMPTP

TYFIND: LDA AC3, DIRP
        STA AC3, ENTPTR
        LDA AC3, NENTS
        STA AC3, ENTCNT
TYFLP:  LDA AC2, ENTPTR
        LDA AC0, 0,AC2
        MOV AC0, AC0, SNR
        JMP TYNOTF
        JSR @TYCMPP
        MOV AC0, AC0, SNR
        JMP TYNEXT
        JMP TYFOUND
TYNEXT: LDA AC3, ENTPTR
        LDA AC0, ENTWORDS
        ADD AC0, AC3
        STA AC3, ENTPTR
        LDA AC3, ENTCNT
        LDA AC0, NEG1
        ADD AC0, AC3
        STA AC3, ENTCNT
        MOV AC3, AC3, SNR
        JMP TYNOTF
        JMP TYFLP

TYFOUND:LDA AC2, ENTPTR
        LDA AC0, 5,AC2
        STA AC0, TYTYPE
        LDA AC0, 6,AC2
        STA AC0, TYSTART
        LDA AC0, 7,AC2
        STA AC0, TYCOUNT
        LDA AC0, 10,AC2
        STA AC0, TYLEN
        LDA AC2, TYPECBP
        LDA AC0, ZERO
        STA AC0, 0,AC2
        LDA AC0, TYSTART
        STA AC0, 1,AC2
        LDA AC0, DIRP
        STA AC0, 2,AC2
TYBLP:  LDA AC0, TYCOUNT
        MOV AC0, AC0, SNR
        JMP TYDONE
        LDA AC2, TYPECBP
        JSR @KRDBLKP
        LDA AC3, ONE
        SUBZ AC3, AC0
        MOV AC0, AC0, SNR
        JMP TYBOK
        LDA AC2, DSKERRP
        JSR @KPUTSP
        JMP @PROMPTP
TYBOK:  JSR @TYOUTP
        LDA AC2, TYPECBP
        LDA AC0, 1,AC2
        LDA AC1, ONE
        ADD AC1, AC0
        STA AC0, 1,AC2
        LDA AC0, TYCOUNT
        LDA AC1, NEG1
        ADD AC1, AC0
        STA AC0, TYCOUNT
        JMP TYBLP
TYDONE: JMP @PROMPTP

TYNOTF: LDA AC2, NOTFOUNDP
        JSR @KPUTSP
        JMP @PROMPTP

; PTYP: Parse LINE+5 into TYPENAME (10 chars, upper, space-pad).
PTYP:   STA AC3, TYRETP
        LDA AC2, LINEP
        LDA AC0, FIVE
        ADD AC0, AC2
        STA AC2, TYPTR
        LDA AC2, TYPENAMEP
        STA AC2, TYDPTR
        LDA AC0, TEN
        STA AC0, TYCNT
PTPLP:  LDA AC2, TYPTR
        LDA AC0, 0,AC2
        MOV AC0, AC0, SNR
        JMP PTPPAD
        STA AC0, TYTMP
        ; Uppercase if 'a'..'z'
        LDA AC1, LOA
        SUB AC1, AC0
        MOV AC0, AC1
        LDA AC0, HIMASK
        AND AC0, AC1
        MOV AC1, AC1, SNR
        JMP PTPNO1
        LDA AC0, TYTMP
        LDA AC1, HIZ
        SUB AC0, AC1
        MOV AC1, AC1
        LDA AC0, HIMASK
        AND AC0, AC1
        MOV AC1, AC1, SNR
        JMP PTPNO1
        LDA AC0, TYTMP
        LDA AC1, TOUPPER
        SUB AC1, AC0
        STA AC0, TYTMP
PTPNO1: LDA AC2, TYDPTR
        LDA AC0, TYTMP
        STA AC0, 0,AC2
        LDA AC0, ONE
        ADD AC0, AC2
        STA AC2, TYDPTR
        LDA AC2, TYPTR
        LDA AC0, ONE
        ADD AC0, AC2
        STA AC2, TYPTR
        LDA AC0, TYCNT
        LDA AC1, NEG1
        ADD AC1, AC0
        STA AC0, TYCNT
        MOV AC0, AC0, SNR
        JMP @TYRETP
        JMP PTPLP
PTPPAD: LDA AC2, TYDPTR
        LDA AC0, SPACE
        STA AC0, 0,AC2
        LDA AC0, ONE
        ADD AC0, AC2
        STA AC2, TYDPTR
        LDA AC0, TYCNT
        LDA AC1, NEG1
        ADD AC1, AC0
        STA AC0, TYCNT
        MOV AC0, AC0, SNR
        JMP @TYRETP
        JMP PTPPAD

; TYCMP: Compare ENTPTR entry name with TYPENAME. AC0=0 if match.
TYCMP:  STA AC3, TYRETP
        LDA AC2, ENTPTR
        STA AC2, TYPTR
        LDA AC2, TYPENAMEP
        STA AC2, TYDPTR
        LDA AC0, FIVE
        STA AC0, TYCNT
TYCLP:  LDA AC2, TYPTR
        LDA AC0, 0,AC2
        MOVS AC0, AC0
        STA AC0, TYTMP
        LDA AC1, BYTEMASK
        AND AC1, AC0
        LDA AC2, TYDPTR
        LDA AC1, 0,AC2
        SUB AC1, AC0
        MOV AC0, AC0, SZR
        JMP TYCNOM
        LDA AC0, TYTMP
        MOVS AC0, AC0
        LDA AC1, BYTEMASK
        AND AC1, AC0
        LDA AC2, TYDPTR
        LDA AC1, 1,AC2
        SUB AC1, AC0
        MOV AC0, AC0, SZR
        JMP TYCNOM
        LDA AC2, TYPTR
        LDA AC0, ONE
        ADD AC0, AC2
        STA AC2, TYPTR
        LDA AC2, TYDPTR
        LDA AC0, TWO
        ADD AC0, AC2
        STA AC2, TYDPTR
        LDA AC0, TYCNT
        LDA AC1, NEG1
        ADD AC1, AC0
        STA AC0, TYCNT
        MOV AC0, AC0, SNR
        JMP TYCOK
        JMP TYCLP
TYCNOM: LDA AC0, ONE
        JMP @TYRETP
TYCOK:  LDA AC0, ZERO
        JMP @TYRETP

; TYOUT: Output block at 0o7600. TYLEN words remaining, TYTYPE is type.
TYOUT:  STA AC3, TYRETP
        LDA AC2, DIRP
        STA AC2, TYPTR
        LDA AC0, TYLEN
        STA AC0, TYCNT
        LDA AC0, TYTYPE
        LDA AC1, ONE
        SUB AC1, AC0
        MOV AC0, AC0, SZR
        JMP TYOTXT
        ; Binary: 2 chars per word
TYOBIN: LDA AC0, TYCNT
        MOV AC0, AC0, SNR
        JMP @TYRETP
        LDA AC2, TYPTR
        LDA AC0, 0,AC2
        STA AC0, TYTMP
        LDA AC1, BYTEMASK
        AND AC1, AC0
        JSR @KPUTCP
        LDA AC0, TYTMP
        MOVS AC0, AC0
        LDA AC1, BYTEMASK
        AND AC1, AC0
        JSR @KPUTCP
        LDA AC2, TYPTR
        LDA AC0, ONE
        ADD AC0, AC2
        STA AC2, TYPTR
        LDA AC0, TYCNT
        LDA AC1, NEG1
        ADD AC1, AC0
        STA AC0, TYCNT
        LDA AC0, TYLEN
        LDA AC1, NEG1
        ADD AC1, AC0
        STA AC0, TYLEN
        JMP TYOBIN
TYOTXT: LDA AC0, TYCNT
        MOV AC0, AC0, SNR
        JMP @TYRETP
        LDA AC2, TYPTR
        LDA AC0, 0,AC2
        LDA AC1, BYTEMASK
        AND AC1, AC0
        JSR @KPUTCP
        LDA AC2, TYPTR
        LDA AC0, ONE
        ADD AC0, AC2
        STA AC2, TYPTR
        LDA AC0, TYCNT
        LDA AC1, NEG1
        ADD AC1, AC0
        STA AC0, TYCNT
        LDA AC0, TYLEN
        LDA AC1, NEG1
        ADD AC1, AC0
        STA AC0, TYLEN
        JMP TYOTXT

; ---- console input ----
; GETLINE: AC2 destination, zero-terminates. Sets EOTSEEN. Echoes via kernel.

GETLINE:STA AC3, GLRET
        LDA AC0, ZERO
        STA AC0, EOTSEEN
GLLP:   JSR @KGETCP
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
        JSR @KPUTCP
        LDA AC0, ONE
        ADD AC0, AC2
        JMP GLLP
GL_EOT: LDA AC0, ONE
        STA AC0, EOTSEEN
GL_DONE:LDA AC0, ZERO
        STA AC0, 0,AC2
        LDA AC2, NLP
        JSR @KPUTSP
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
        JSR @KPUTCP
        JMP @PNCHRET

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
NOTFOUND:DW 0o077
         .TXT "NOFILE"
         DW 0o015, 0o012, 0
