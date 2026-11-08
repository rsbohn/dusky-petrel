; FOCAL/Nova - a FOCAL interpreter for cvit/Nova
;
; Runs as a CVIT RUN member: RUN FOCAL.  Built with
;   Snova abs sd/focal.asm focal.abs --format simh-load
;   scripts/abs2flat.py --pz focal.abs focal.sys 0o6000
; and stored on the disk as FOCAL=focal.sys@0o6000,0o6000.
;
; All console I/O goes through the cvit/Nova kernel jump table
; (GETC 0o1006, PUTC 0o1007).  QUIT at the * prompt, or EOT (Ctrl-D)
; anywhere, returns to COMMAND through the kernel warm start (0o1001).
;
; Commands: ASK COMMENT DO ERASE FOR GOTO IF QUIT RETURN SET TYPE WRITE
; Functions: FABS FSGN FITR FSQT
; Numbers: 32-bit DG-style floating point (sign, excess-64 hex exponent,
; 24-bit hex-normalized fraction), done in software.
;
; Memory map:
;   0o0020          SP, software stack pointer (auto-increment cell)
;   0o0040-0o0377   page-zero constants, globals, routine pointers
;                   (copied from PZIMG at startup)
;   0o6000-         interpreter code
;   0o30000-0o55777 program text (one char per word)
;   0o56000-0o57777 software stack
;   0o60000-0o63777 variable table (4 words per variable)
;   0o64000         input line buffer, 0o64200 ASK buffer
;
; Conventions: routines clobber AC0-AC3 unless noted; JMP @XRET keeps
; AC0-AC2.  Leaf routines keep
; their return address in a local cell.  Recursive routines (RUNSEG,
; DOCMD, DO, FOR, EXPR, TERM, UNARY, PRIM, GETVAR) push AC3 with
; STA 3,@SP and return with JMP @XRET.

        ORG 0o20
SP:
        ORG 0o40

; ---------------- page zero: constants ----------------
K0:      DW 0
K1:      DW 1
K2:      DW 2
K3:      DW 3
K4:      DW 4
K6:      DW 6
K7:      DW 7
K8:      DW 0o10
K10:     DW 0o12
K100:    DW 0o144
K64:     DW 0o100
K200:    DW 0o200
KM1:     DW 0o177777
KM16:    DW 0o177760
KM32:    DW 0o177740
K177:    DW 0o177
KFF:     DW 0o377
KFF00:   DW 0o177400
K7FFF:   DW 0o77777
K8000:   DW 0o100000
KF000:   DW 0o170000
K1000H:  DW 0o10000
KMAXL:   DW 0o110

; ---------------- page zero: characters ----------------
CEOT:    DW 0o004
CBS:     DW 0o010
CLF:     DW 0o012
CCR:     DW 0o015
CSP:     DW 0o040
CBANG:   DW 0o041
CQUOT:   DW 0o042
CHASH:   DW 0o043
CDOL:    DW 0o044
CPCT:    DW 0o045
CLPAR:   DW 0o050
CRPAR:   DW 0o051
CSTAR:   DW 0o052
CPLUS:   DW 0o053
CCOMMA:  DW 0o054
CMINUS:  DW 0o055
CDOT:    DW 0o056
CSLASH:  DW 0o057
CZERO:   DW 0o060
CNINE:   DW 0o071
CCOLON:  DW 0o072
CSEMI:   DW 0o073
CLT:     DW 0o074
CEQ:     DW 0o075
CGT:     DW 0o076
CQUES:   DW 0o077
CA:      DW 0o101
CE:      DW 0o105
CF:      DW 0o106
CZ:      DW 0o132
CLBRK:   DW 0o133
CRBRK:   DW 0o135
CUP:     DW 0o136
CLA:     DW 0o141
CLZ:     DW 0o172
CDEL:    DW 0o177

; ---------------- page zero: float constants ----------------
FONE:    DW 0o40420, 0          ; 1.0     0x4110 0000
FTEN:    DW 0o40640, 0          ; 10.0    0x41A0 0000
FHALF:   DW 0o40200, 0          ; 0.5     0x4080 0000
FHUND:   DW 0o41144, 0          ; 100.0   0x4264 0000
FMIL:    DW 0o42764, 0o22000    ; 1.0E6   0x45F4 2400

; ---------------- page zero: globals ----------------
TXP:     DW 0          ; text pointer (current char)
CLP:     DW 0          ; current line pointer, 0 = direct mode
QUITF:   DW 0
RETF:    DW 0
LASTCR:  DW 0
COL:     DW 0
FMTW:    DW 0o10       ; output field width (0 = E format)
FMTD:    DW 4          ; output decimals
VCNT:    DW 0
PEND:    DW 0          ; address of program end marker (line no 0)
SMODE:   DW 0          ; RUNSEG mode: 0 all, 1 line, 2 group
SGLO:    DW 0          ; RUNSEG group low line number
FA0:     DW 0          ; FAC, packed float accumulator
FA1:     DW 0
FB0:     DW 0          ; FOP, packed float operand
FB1:     DW 0
UAS:     DW 0          ; unpacked A: sign, exponent, mantissa hi, lo
UAE:     DW 0
UAH:     DW 0
UAL:     DW 0
UBS:     DW 0          ; unpacked B
UBE:     DW 0
UBH:     DW 0
UBL:     DW 0
FXS:     DW 0          ; FIX32 result: sign, hi, lo
FXH:     DW 0
FXL:     DW 0
UPD:     DW 0          ; UNPK destination
LKMODE:  DW 0          ; LNLOOK result: 1 line, 2 group
LKGLO:   DW 0          ; LNLOOK group low line number

; ---------------- page zero: addresses ----------------
PUA:     DW UAS
PUB:     DW UBS
PFA:     DW FA0
PFB:     DW FB0
PFONE:   DW FONE
PFTEN:   DW FTEN
PFHALF:  DW FHALF
PFHUND:  DW FHUND
PFMIL:   DW FMIL
PPBASE:  DW 0o30000
PPLIM:   DW 0o55600
PSTK:    DW 0o56000
PSTKL:   DW 0o57600
PVTAB:   DW 0o60000
VMAX:    DW 0o1000
PLINB:   DW 0o64000
PASKB:   DW 0o64200
KGETC:   DW 0o1006
KPUTC:   DW 0o1007
PWARM:   DW 0o1001

; ---------------- page zero: routine pointers ----------------
XMAIN:   DW MAIN
XERR:    DW ERR
XRET:    DW RET
XOUTC:   DW OUTC
XCRLF:   DW CRLF
XNLIF:   DW NLIF
XPUTS:   DW PUTS
XGETLN:  DW GETLN
XSKSP:   DW SKSP
XADVC:   DW ADVC
XISDIG:  DW ISDIG
XISLET:  DW ISLET
XISALN:  DW ISALN
XEOL:    DW EOL
XFINDLN: DW FINDLN
XNEXTLN: DW NEXTLN
XDELLN:  DW DELLN
XLNENT:  DW LNENT
XLNLOOK: DW LNLOOK
XLNEXP:  DW LNEXP
XLNCNV:  DW LNCNV
XRUNSEG: DW RUNSEG
XDOCMD:  DW DOCMD
XEXPR:   DW EXPR
XTERM:   DW TERM
XUNARY:  DW UNARY
XPRIM:   DW PRIM
XGETVAR: DW GETVAR
XVLOOK:  DW VLOOK
XRDNUM:  DW RDNUM
XRDINT:  DW RDINT
XPRNUM:  DW PRNUM
XPR16:   DW PR16
XPR2D:   DW PR2D
XPRLNO:  DW PRLNO
XPRLINE: DW PRLINE
XTSTR:   DW TSTR
XTDUMP:  DW TDUMP
XDIV10:  DW DIV10
XDIV16:  DW DIV16
XUNPK:   DW UNPK
XUNPAB:  DW UNPAB
XNORM:   DW NORMA
XPACK:   DW PACKA
XSWAB:   DW SWAB
XUMUL:   DW UMUL
XFADD:   DW FADD
XFSUB:   DW FSUB
XFMUL:   DW FMUL
XFDIV:   DW FDIV
XFNEG:   DW FNEG
XFLT16:  DW FLT16
XFIX32:  DW FIX32
XFIX16:  DW FIX16
XFXR16:  DW FIXR16
XFIXR:   DW FIXR
XFINT:   DW FINT
XLDFB:   DW LDFB
XLDFA:   DW LDFA
XFGE:    DW FGE
XFSGN:   DW FSGN
XIPOW:   DW IPOW
XFSQT:   DW FSQRT
XMUL10:  DW MUL10
XPOW10:  DW POW10

; =====================================================================
        ORG 0o6000

; ---- startup: copy the page-zero image, then initialise ----
START:  LDA 2, SPZP
        LDA 3, 0,2          ; page-zero start address
        LDA 1, 1,2          ; word count
        NEG 1,1
        STA 1, SCNT
        INC 2,2
        INC 2,2
SCP:    LDA 0, 0,2
        STA 0, 0,3
        INC 2,2
        INC 3,3
        ISZ SCNT
        JMP SCP
        LDA 2, PPBASE       ; empty program
        STA 2, PEND
        SUB 0,0
        STA 0, 0,2
        STA 0, VCNT
        LDA 2, BANP
        JSR @XPUTS
        JMP @XMAIN

SPZP:   DW PZIMG
SCNT:   DW 0
BANP:   DW BANNER

; ---- RET: pop return address from the software stack and jump ----
; Clobbers AC3 only, so AC0-AC2 can carry results back.
RET:    LDA 3, SP
        LDA 3, 0,3
        DSZ SP
        JMP 0,3
        JMP 0,3

; ---- MAIN: command loop ----
MAIN:   LDA 0, PSTK
        STA 0, SP
        SUB 0,0
        STA 0, QUITF
        STA 0, RETF
        STA 0, CLP
        JSR @XNLIF
        LDA 0, CSTAR
        JSR @XOUTC
        LDA 2, PLINB
        JSR @XGETLN
        LDA 2, PLINB
        STA 2, TXP
        JSR @XSKSP
        MOV 0,0,SNR
        JMP MAIN
        JSR @XISDIG
        JMP MDIRECT
        JSR @XLNENT
        JMP MAIN
MDIRECT:SUB 0,0
        SUB 1,1
        JSR @XRUNSEG
        JMP MAIN

; ---- ERR: JSR @XERR followed by DW message ----
ERR:    LDA 2, 0,3
        STA 2, ERMSG
        JSR @XNLIF
        LDA 0, CQUES
        JSR @XOUTC
        LDA 2, ERMSG
        JSR @XPUTS
        LDA 2, CLP
        MOV 2,2,SNR
        JMP ERDN
        LDA 2, ERATP
        JSR @XPUTS
        LDA 2, CLP
        LDA 0, 0,2
        JSR @XPRLNO
ERDN:   JSR @XCRLF
        JMP @XMAIN

ERMSG:  DW 0
ERATP:  DW ERAT

; ---- console output ----
; OUTC: AC0 = char.  Preserves AC0, AC1, AC2.  Tracks COL.
OUTC:   STA 3, OCRT
        STA 1, OCS1
        STA 2, OCS2
        STA 0, OCCH
        JSR @KPUTC
        LDA 0, OCCH
        LDA 1, CCR
        SUB# 0,1,SNR
        JMP OCC0
        LDA 1, CSP
        SUBZ# 1,0,SNC       ; skip if char >= space
        JMP OCDN
        ISZ COL
        NOP
        JMP OCDN
OCC0:   SUB 1,1
        STA 1, COL
OCDN:   LDA 0, OCCH
        LDA 1, OCS1
        LDA 2, OCS2
        JMP @OCRT

OCRT:   DW 0
OCS1:   DW 0
OCS2:   DW 0
OCCH:   DW 0

; CRLF: print CR LF.
CRLF:   STA 3, CRRT
        LDA 0, CCR
        JSR @XOUTC
        LDA 0, CLF
        JSR @XOUTC
        JMP @CRRT
CRRT:   DW 0

; NLIF: newline unless already at column 0.
NLIF:   LDA 0, COL
        MOV 0,0,SNR
        JMP 0,3
        JMP @XCRLF

; PUTS: AC2 = NUL-terminated string (one char per word).
PUTS:   STA 3, PSRT
PSLP:   LDA 0, 0,2
        MOV 0,0,SNR
        JMP @PSRT
        JSR @XOUTC
        INC 2,2
        JMP PSLP
PSRT:   DW 0

; ---- GETLN: read an edited line into the buffer at AC2 ----
; Echoes, handles rubout/backspace, upper-cases outside quotes, and
; stores a NUL terminator.  EOT leaves FOCAL.
GETLN:  STA 3, GLRT
        STA 2, GLP
        SUB 0,0
        STA 0, GLN
        STA 0, GLQ
GLLP:   JSR @KGETC
        LDA 1, K177
        AND 1,0
        LDA 1, CEOT
        SUB# 0,1,SNR
        JMP @PWARM
        LDA 1, CLF
        SUB# 0,1,SZR
        JMP GLNLF
        LDA 1, LASTCR       ; LF right after CR: ignore
        SUB 2,2
        STA 2, LASTCR
        MOV 1,1,SZR
        JMP GLLP
        JMP GLEND
GLNLF:  SUB 2,2
        STA 2, LASTCR
        LDA 1, CCR
        SUB# 0,1,SNR
        JMP GLCR
        LDA 1, CDEL
        SUB# 0,1,SNR
        JMP GLRUB
        LDA 1, CBS
        SUB# 0,1,SNR
        JMP GLRUB
        LDA 1, CSP
        SUBZ# 1,0,SZC       ; skip if control char
        JMP GLCH
        JMP GLLP
GLCH:   LDA 1, GLN
        LDA 2, KMAXL
        SUBZ# 2,1,SZC       ; skip if room left
        JMP GLLP
        LDA 1, CQUOT
        SUB# 0,1,SZR
        JMP GLNQ
        LDA 1, GLQ
        COM 1,1
        STA 1, GLQ
        JMP GLST
GLNQ:   LDA 1, GLQ
        MOV 1,1,SZR
        JMP GLST
        LDA 1, CLA
        SUBZ# 1,0,SZC       ; skip if below 'a'
        JMP GLU1
        JMP GLST
GLU1:   LDA 1, CLZ
        ADCZ# 1,0,SZC       ; skip if <= 'z'
        JMP GLST
        LDA 1, CSP
        SUB 1,0
GLST:   JSR @XOUTC
        LDA 2, GLP
        STA 0, 0,2
        INC 2,2
        STA 2, GLP
        ISZ GLN
        JMP GLLP
        JMP GLLP
GLRUB:  LDA 1, GLN
        MOV 1,1,SNR
        JMP GLLP
        NEG 1,1
        COM 1,1
        STA 1, GLN
        LDA 2, GLP
        NEG 2,2
        COM 2,2
        STA 2, GLP
        LDA 0, 0,2
        LDA 1, CQUOT
        SUB# 0,1,SZR
        JMP GLRB2
        LDA 1, GLQ
        COM 1,1
        STA 1, GLQ
GLRB2:  LDA 0, CBS
        JSR @XOUTC
        LDA 0, CSP
        JSR @XOUTC
        LDA 0, CBS
        JSR @XOUTC
        JMP GLLP
GLCR:   LDA 1, K1
        STA 1, LASTCR
GLEND:  LDA 2, GLP
        SUB 0,0
        STA 0, 0,2
        JSR @XCRLF
        JMP @GLRT

GLRT:   DW 0
GLP:    DW 0
GLN:    DW 0
GLQ:    DW 0

; ---- text scanning ----
; SKSP: skip spaces at TXP; AC0 = char.  Uses AC0-AC2.
SKSP:   LDA 2, TXP
SKL:    LDA 0, 0,2
        LDA 1, CSP
        SUB# 0,1,SZR        ; skip if space
        JMP SKDN
        INC 2,2
        JMP SKL
SKDN:   STA 2, TXP
        JMP 0,3

; ADVC: TXP++, AC0 = char.  Uses AC0, AC2.
ADVC:   ISZ TXP
        LDA 2, TXP
        LDA 0, 0,2
        JMP 0,3

; ISDIG: AC0 = char.  Skip return with AC1 = value if a digit.
; Preserves AC0, AC2.
ISDIG:  LDA 1, CZERO
        SUBZ# 1,0,SZC       ; skip if below '0'
        JMP ISD1
        JMP 0,3
ISD1:   LDA 1, CNINE
        ADCZ# 1,0,SZC       ; skip if <= '9'
        JMP 0,3
        LDA 1, CZERO
        SUB 0,1
        NEG 1,1
        JMP 1,3

; ISLET: AC0 = char.  Skip return if A-Z.  Preserves AC0, AC2.
ISLET:  LDA 1, CA
        SUBZ# 1,0,SZC       ; skip if below 'A'
        JMP ISL1
        JMP 0,3
ISL1:   LDA 1, CZ
        ADCZ# 1,0,SZC       ; skip if <= 'Z'
        JMP 0,3
        JMP 1,3

; ISALN: skip return if A-Z or 0-9.  Preserves AC0, AC2.
ISALN:  STA 3, IART
        JSR @XISLET
        JMP IA1
        JMP IAYES
IA1:    JSR @XISDIG
        JMP @IART
IAYES:  ISZ IART
        JMP @IART
IART:   DW 0

; EOL: AC0 = char.  Skip return if NUL or ';' (end of command).
; Preserves AC0, AC2.
EOL:    MOV 0,0,SNR
        JMP 1,3
        LDA 1, CSEMI
        SUB# 0,1,SNR
        JMP 1,3
        JMP 0,3

; =====================================================================
; Program text: lines are [line number][chars...][0], in ascending
; order, ending with a 0 line number at PEND.  Line numbers are
; group*100 + step (1.10 is 110).

; FINDLN: AC0 = line number.  AC2 = matching line (skip return) or the
; insertion point (normal return).
FINDLN: STA 3, FLRT
        STA 0, FLN
        LDA 2, PPBASE
FLLP:   LDA 1, 0,2
        MOV 1,1,SNR
        JMP @FLRT
        LDA 0, FLN
        SUB# 0,1,SNR
        JMP FLFND
        SUBZ# 0,1,SZC       ; skip if line < wanted
        JMP @FLRT
        JSR @XNEXTLN
        JMP FLLP
FLFND:  ISZ FLRT
        JMP @FLRT
FLRT:   DW 0
FLN:    DW 0

; NEXTLN: AC2 = line pointer -> AC2 = next line.  Uses AC1 only.
NEXTLN: INC 2,2
NLLP:   LDA 1, 0,2
        INC 2,2
        MOV 1,1,SZR
        JMP NLLP
        JMP 0,3

; DELLN: delete the line at AC2.
DELLN:  STA 3, DLRT
        STA 2, DLDST
        JSR @XNEXTLN
        LDA 3, DLDST
        LDA 1, PEND
DLLP:   LDA 0, 0,2          ; copy [next..PEND] down
        STA 0, 0,3
        SUB# 2,1,SNR
        JMP DLDN
        INC 2,2
        INC 3,3
        JMP DLLP
DLDN:   STA 3, PEND
        JMP @DLRT
DLRT:   DW 0
DLDST:  DW 0

; LNENT: store (or delete) the program line typed at TXP.
LNENT:  STA 3, LERT
        JSR @XRDNUM
        JSR @XLNCNV
        STA 0, LENUM
        LDA 1, K100         ; step must be nonzero
        JSR @XDIV16
        MOV 1,1,SNR
        JMP LEBAD
        LDA 0, LENUM
        LDA 1, K100
        SUBZ# 1,0,SZC       ; group must be >= 1
        JMP LE1
LEBAD:  JSR @XERR
        DW EMLIN
LE1:    JSR @XSKSP
        STA 0, LECH
        LDA 0, LENUM
        JSR @XFINDLN
        JMP LENEW
        JSR @XDELLN
LENEW:  LDA 0, LECH
        MOV 0,0,SNR
        JMP @LERT
        LDA 2, TXP          ; length = chars + 2
        SUB 1,1
LECNT:  LDA 0, 0,2
        INC 1,1
        INC 2,2
        MOV 0,0,SZR
        JMP LECNT
        INC 1,1
        STA 1, LELEN
        LDA 0, PEND         ; room?
        ADD 1,0
        LDA 2, PPLIM
        SUBZ# 2,0,SNC       ; skip if PEND+len >= limit
        JMP LE2
        JSR @XERR
        DW EMMEM
LE2:    LDA 0, LENUM
        JSR @XFINDLN
        NOP
        STA 2, LEPOS
        LDA 3, PEND         ; move [pos..PEND] up by len, top down
        MOV 3,2
        LDA 1, LELEN
        ADD 1,3
        STA 3, PEND
LEMV:   LDA 0, 0,2
        STA 0, 0,3
        LDA 1, LEPOS
        SUB# 2,1,SNR
        JMP LEWR
        NEG 2,2
        COM 2,2
        NEG 3,3
        COM 3,3
        JMP LEMV
LEWR:   LDA 3, LEPOS
        LDA 0, LENUM
        STA 0, 0,3
        LDA 2, TXP
LEWLP:  INC 3,3
        LDA 0, 0,2
        STA 0, 0,3
        INC 2,2
        MOV 0,0,SZR
        JMP LEWLP
        JMP @LERT

LERT:   DW 0
LENUM:  DW 0
LECH:   DW 0
LELEN:  DW 0
LEPOS:  DW 0

; LNCNV: FAC -> AC0 = line number (round(x*100)), checked 1..9999.
LNCNV:  STA 3, LCRT
        LDA 2, PFHUND
        JSR @XLDFB
        JSR @XFMUL
        JSR @XFXR16
        MOVL# 0,0,SZC       ; skip if not negative
        JMP LCBAD
        MOV 0,0,SNR
        JMP LCBAD
        LDA 1, K9999
        ADCZ# 1,0,SZC       ; skip if <= 9999
        JMP LCBAD
        JMP @LCRT
LCBAD:  JSR @XERR
        DW EMLIN
LCRT:   DW 0
K9999:  DW 0o23417

; LNEXP: evaluate an expression at TXP as a line number -> AC0.
LNEXP:  STA 3, LXRT
        JSR @XEXPR
        JSR @XLNCNV
        JMP @LXRT
LXRT:   DW 0

; LNLOOK: AC0 = line number.  A group number (step 0) finds the first
; line of the group.  Returns AC2 = line, LKMODE = 1 (line) or 2
; (group), LKGLO = group low line number.  Errors if not found.
LNLOOK: STA 3, LKRT
        STA 0, LKN
        LDA 1, K100
        JSR @XDIV16         ; AC1 = step
        LDA 0, LKN
        MOV 1,1,SNR
        JMP LKGRP
        JSR @XFINDLN
        JMP LKBAD
        LDA 1, K1
        STA 1, LKMODE
        JMP @LKRT
LKGRP:  STA 0, LKGLO
        JSR @XFINDLN
        NOP
        LDA 0, 0,2          ; first line at or after g*100
        MOV 0,0,SNR
        JMP LKBAD
        LDA 1, LKGLO
        LDA 3, K100
        ADD 3,1
        SUBZ# 1,0,SZC       ; skip if line < next group
        JMP LKBAD
        LDA 1, K2
        STA 1, LKMODE
        JMP @LKRT
LKBAD:  JSR @XERR
        DW EMLIN
LKRT:   DW 0
LKN:    DW 0

; =====================================================================
; RUNSEG: execute commands from TXP/CLP.  AC0 = mode (0 run to end of
; program, 1 end of current line, 2 end of group), AC1 = group low line
; number for mode 2.  Recursive.
RUNSEG: STA 3, @SP
        STA 0, RSM
        STA 1, RSG
        LDA 2, SP
        LDA 3, PSTKL
        SUBZ# 3,2,SNC       ; skip if SP >= limit
        JMP RS1
        JSR @XERR
        DW EMSTK
RS1:    LDA 0, SMODE
        STA 0, @SP
        LDA 0, SGLO
        STA 0, @SP
        LDA 0, RSM
        STA 0, SMODE
        LDA 0, RSG
        STA 0, SGLO
RSLP:   LDA 0, QUITF
        MOV 0,0,SZR
        JMP RSEX
        LDA 0, RETF
        MOV 0,0,SZR
        JMP RSEX
        JSR @XSKSP
        MOV 0,0,SZR
        JMP RSCMD
        LDA 0, SMODE        ; end of line
        LDA 1, K1
        SUB# 0,1,SNR
        JMP RSEX
        LDA 2, CLP
        MOV 2,2,SNR
        JMP RSEX
        JSR @XNEXTLN
        LDA 0, 0,2
        MOV 0,0,SNR
        JMP RSEX
        LDA 1, SMODE
        MOV 1,1,SNR
        JMP RSGO
        LDA 1, SGLO
        SUBZ# 1,0,SZC       ; skip if line < group low
        JMP RSG2
        JMP RSEX
RSG2:   LDA 3, K100
        ADD 3,1
        SUBZ# 1,0,SZC       ; skip if line < next group
        JMP RSEX
RSGO:   STA 2, CLP
        INC 2,2
        STA 2, TXP
        JMP RSLP
RSCMD:  LDA 1, CSEMI
        SUB# 0,1,SNR
        JMP RSSEMI
        JSR @XDOCMD
        JMP RSLP
RSSEMI: ISZ TXP
        JMP RSLP
RSEX:   LDA 2, SP
        LDA 0, 0,2
        STA 0, SGLO
        LDA 0, -1,2
        STA 0, SMODE
        DSZ SP
        DSZ SP
        JMP @XRET
RSM:    DW 0
RSG:    DW 0

; DOCMD: AC0 = first letter of a command word at TXP.  Recursive.
DOCMD:  STA 3, @SP
        STA 0, DCCH
DCSK:   JSR @XADVC          ; skip the rest of the command word
        JSR @XISLET
        JMP DCD
        JMP DCSK
DCD:    LDA 0, DCCH
        LDA 2, DCTABP
DCLP:   LDA 1, 0,2
        MOV 1,1,SNR
        JMP DCBAD
        SUB# 0,1,SNR
        JMP DCGO
        INC 2,2
        INC 2,2
        JMP DCLP
DCGO:   LDA 2, 1,2
        JSR 0,2
        JMP @XRET
DCBAD:  JSR @XERR
        DW EMCMD
DCCH:   DW 0
DCTABP: DW DCTAB
DCTAB:  DW 0o101, CASK      ; A
        DW 0o103, CCOMM     ; C
        DW 0o104, CDO       ; D
        DW 0o105, CERASE    ; E
        DW 0o106, CFOR      ; F
        DW 0o107, CGOTO     ; G
        DW 0o111, CIF       ; I
        DW 0o121, CQUIT     ; Q
        DW 0o122, CRETN     ; R
        DW 0o123, CSET      ; S
        DW 0o124, CTYPE     ; T
        DW 0o127, CWRITE    ; W
        DW 0

; =====================================================================
; Commands.  Each is entered by JSR from DOCMD with TXP just past the
; command word, and returns with TXP at the end of the command.

; COMMENT: skip to end of line.
CCOMM:  LDA 2, TXP
CCLP:   LDA 0, 0,2
        MOV 0,0,SNR
        JMP CCDN
        INC 2,2
        JMP CCLP
CCDN:   STA 2, TXP
        JMP 0,3

; QUIT: at the * prompt leave FOCAL; in a program stop it.
CQUIT:  LDA 0, CLP
        MOV 0,0,SNR
        JMP @PWARM
        LDA 0, K1
        STA 0, QUITF
        JMP 0,3

; RETURN: end the current DO (or the program).
CRETN:  LDA 0, K1
        STA 0, RETF
        JMP 0,3

; SET var = expr
CSET:   STA 3, CSRT
        JSR @XGETVAR
        STA 2, CSVA
        JSR @XSKSP
        LDA 1, CEQ
        SUB# 0,1,SZR
        JMP CSBAD
        ISZ TXP
        JSR @XEXPR
        LDA 2, CSVA
        LDA 0, FA0
        STA 0, 0,2
        LDA 0, FA1
        STA 0, 1,2
        JMP @CSRT
CSBAD:  JSR @XERR
        DW EMSYN
CSRT:   DW 0
CSVA:   DW 0

; GOTO [line]
CGOTO:  STA 3, CGRT
        JSR @XSKSP
        JSR @XEOL
        JMP CG1
        LDA 2, PPBASE       ; no argument: first line
        LDA 0, 0,2
        MOV 0,0,SNR
        JMP @CGRT
        JMP CG2
CG1:    JSR @XLNEXP
        JSR @XLNLOOK
CG2:    STA 2, CLP
        INC 2,2
        STA 2, TXP
        JMP @CGRT
CGRT:   DW 0

; DO line|group (no argument: whole program)
CDO:    STA 3, @SP
        JSR @XSKSP
        JSR @XEOL
        JMP CD1
        LDA 2, PPBASE
        LDA 0, 0,2
        MOV 0,0,SNR
        JMP @XRET
        SUB 0,0
        STA 0, CDMODE
        JMP CD2
CD1:    JSR @XLNEXP
        JSR @XLNLOOK
        LDA 0, LKMODE
        STA 0, CDMODE
        LDA 0, LKGLO
        STA 0, CDGLO
CD2:    LDA 0, CLP          ; save caller position
        STA 0, @SP
        LDA 0, TXP
        STA 0, @SP
        STA 2, CLP
        INC 2,2
        STA 2, TXP
        LDA 0, CDMODE
        LDA 1, CDGLO
        JSR @XRUNSEG
        LDA 2, SP
        LDA 0, 0,2
        STA 0, TXP
        LDA 0, -1,2
        STA 0, CLP
        DSZ SP
        DSZ SP
        SUB 0,0
        STA 0, RETF
        JMP @XRET
CDMODE: DW 0
CDGLO:  DW 0

; IF (expr) neg,zero,pos
CIF:    STA 3, CIRT
        JSR @XEXPR
        LDA 0, FA0          ; selector: 0 negative, 1 zero, 2 positive
        LDA 1, FA1
        MOV 0,0,SZR
        JMP CI1
        MOV 1,1,SZR
        JMP CI1
        LDA 0, K1
        JMP CI2
CI1:    MOVL# 0,0,SZC       ; skip if positive
        JMP CINEG
        LDA 0, K2
        JMP CI2
CINEG:  SUB 0,0
CI2:    STA 0, CISEL
        SUB 0,0
        STA 0, CICNT
CILP:   JSR @XSKSP
        JSR @XEOL
        JMP CI3
        JMP @CIRT
CI3:    LDA 1, CCOMMA       ; empty target: IF (X) ,,3.4
        SUB# 0,1,SZR
        JMP CI4
        ISZ CICNT
        ISZ TXP
        JMP CILP
CI4:    JSR @XLNEXP
        LDA 1, CICNT
        LDA 2, CISEL
        SUB# 1,2,SZR
        JMP CINX
        JSR @XLNLOOK
        STA 2, CLP
        INC 2,2
        STA 2, TXP
        JMP @CIRT
CINX:   ISZ CICNT
        JSR @XSKSP
        LDA 1, CCOMMA
        SUB# 0,1,SZR
        JMP @CIRT
        ISZ TXP
        JMP CILP
CIRT:   DW 0
CISEL:  DW 0
CICNT:  DW 0

; ERASE                  clear variables
; ERASE ALL              clear variables and program
; ERASE line|group       delete program lines
CERASE: STA 3, CERT
        JSR @XSKSP
        JSR @XEOL
        JMP CE1
        SUB 0,0
        STA 0, VCNT
        JMP @CERT
CE1:    LDA 1, CA
        SUB# 0,1,SZR
        JMP CE3
CE2:    JSR @XADVC          ; ERASE ALL
        JSR @XISLET
        JMP CE2D
        JMP CE2
CE2D:   SUB 0,0
        STA 0, VCNT
        LDA 2, PPBASE
        STA 2, PEND
        STA 0, 0,2
        JMP CESTOP
CE3:    JSR @XLNEXP
        STA 0, CEN
        LDA 1, K100
        JSR @XDIV16
        MOV 1,1,SNR
        JMP CEGRP
        LDA 0, CEN
        JSR @XFINDLN
        JMP CEBAD
        JSR @XDELLN
        JMP CESTOP
CEGRP:  LDA 0, CEN          ; delete every line in the group
        JSR @XFINDLN
        NOP
        LDA 0, 0,2
        MOV 0,0,SNR
        JMP CESTOP
        LDA 1, CEN
        LDA 3, K100
        ADD 3,1
        SUBZ# 1,0,SZC       ; skip if line < next group
        JMP CESTOP
        JSR @XDELLN
        JMP CEGRP
CESTOP: LDA 0, CLP          ; program text moved: stop a running program
        MOV 0,0,SZR
        STA 0, QUITF
        JMP @CERT
CEBAD:  JSR @XERR
        DW EMLIN
CERT:   DW 0
CEN:    DW 0

; WRITE [ALL|line|group]
CWRITE: STA 3, CWRT
        SUB 0,0
        STA 0, CWLO
        LDA 0, KM1
        STA 0, CWHI
        JSR @XSKSP
        JSR @XEOL
        JMP CW1
        JMP CWGO
CW1:    LDA 1, CA
        SUB# 0,1,SZR
        JMP CW3
CW2:    JSR @XADVC
        JSR @XISLET
        JMP CWGO
        JMP CW2
CW3:    JSR @XLNEXP
        STA 0, CWLO
        STA 0, CWHI
        ISZ CWHI
        LDA 1, K100
        JSR @XDIV16
        MOV 1,1,SZR
        JMP CW4
        LDA 0, CWLO         ; group
        LDA 1, K100
        ADD 1,0
        STA 0, CWHI
        JMP CWGO
CW4:    LDA 0, CWLO         ; single line must exist
        JSR @XFINDLN
        JMP CWBAD
CWGO:   LDA 2, PPBASE
CWLP:   LDA 0, 0,2
        MOV 0,0,SNR
        JMP @CWRT
        LDA 1, CWLO
        SUBZ# 1,0,SZC       ; skip if line < low
        JMP CW5
        JMP CWNX
CW5:    LDA 1, CWHI
        SUBZ# 1,0,SZC       ; skip if line < high
        JMP CWNX
        STA 2, CWP
        JSR @XPRLINE
        LDA 2, CWP
CWNX:   JSR @XNEXTLN
        JMP CWLP
CWBAD:  JSR @XERR
        DW EMLIN
CWRT:   DW 0
CWLO:   DW 0
CWHI:   DW 0
CWP:    DW 0

; PRLINE: print the program line at AC2 as "gg.ss text".
PRLINE: STA 3, PLRT
        STA 2, PLP
        LDA 0, 0,2
        JSR @XPRLNO
        LDA 0, CSP
        JSR @XOUTC
        LDA 2, PLP
        INC 2,2
        JSR @XPUTS
        JSR @XCRLF
        JMP @PLRT
PLRT:   DW 0
PLP:    DW 0

; PRLNO: print line number AC0 as gg.ss.
PRLNO:  STA 3, PNORT
        LDA 1, K100
        JSR @XDIV16
        STA 1, PNOS
        JSR @XPR2D
        LDA 0, CDOT
        JSR @XOUTC
        LDA 0, PNOS
        JSR @XPR2D
        JMP @PNORT
PNORT:  DW 0
PNOS:   DW 0

; PR2D: print AC0 (0..99) as two digits.
PR2D:   STA 3, P2RT
        LDA 1, K10
        JSR @XDIV16
        STA 1, P2LO
        LDA 1, CZERO
        ADD 1,0
        JSR @XOUTC
        LDA 0, P2LO
        LDA 1, CZERO
        ADD 1,0
        JSR @XOUTC
        JMP @P2RT
P2RT:   DW 0
P2LO:   DW 0

; TYPE items: "text" ! # %w.d $ expr, separated by commas.
CTYPE:  STA 3, CTRT
CTLP:   JSR @XSKSP
        JSR @XEOL
        JMP CT1
        JMP @CTRT
CT1:    LDA 1, CCOMMA
        SUB# 0,1,SNR
        JMP CTSKIP
        JSR @XTSTR          ; strings, ! and #
        JMP CT2
        JMP CTLP
CT2:    LDA 1, CPCT
        SUB# 0,1,SNR
        JMP CTFMT
        LDA 1, CDOL
        SUB# 0,1,SNR
        JMP CTDOL
        JSR @XEXPR
        JSR @XPRNUM
        JMP CTLP
CTSKIP: ISZ TXP
        JMP CTLP
CTDOL:  ISZ TXP
        JSR @XTDUMP
        JMP CTLP
CTFMT:  JSR @XADVC          ; %w.d, or % alone for E format
        JSR @XISDIG
        JMP CTFE
        JSR @XRDINT
        STA 0, FMTW
        SUB 0,0
        STA 0, FMTD
        JSR @XSKSP
        LDA 1, CDOT
        SUB# 0,1,SZR
        JMP CTLP
        JSR @XADVC
        JSR @XRDINT
        LDA 1, K7           ; at most 7 decimals
        ADCZ# 1,0,SZC
        MOV 1,0
        STA 0, FMTD
        JMP CTLP
CTFE:   SUB 0,0
        STA 0, FMTW
        JMP CTLP
CTRT:   DW 0

; TSTR: AC0 = char at TXP.  Handles "text", ! and #; skip return if it
; consumed one of them, normal return (AC0 intact) otherwise.
TSTR:   STA 3, TSRT
        LDA 1, CBANG
        SUB# 0,1,SNR
        JMP TSBANG
        LDA 1, CHASH
        SUB# 0,1,SNR
        JMP TSHASH
        LDA 1, CQUOT
        SUB# 0,1,SZR
        JMP @TSRT
TSQLP:  JSR @XADVC
        MOV 0,0,SNR
        JMP TSYES
        LDA 1, CQUOT
        SUB# 0,1,SNR
        JMP TSQEND
        JSR @XOUTC
        JMP TSQLP
TSQEND: ISZ TXP
        JMP TSYES
TSBANG: ISZ TXP
        JSR @XCRLF
        JMP TSYES
TSHASH: ISZ TXP
        LDA 0, CCR
        JSR @XOUTC
TSYES:  ISZ TSRT
        JMP @TSRT
TSRT:   DW 0

; TDUMP: TYPE $ - list every variable.
TDUMP:  STA 3, TDRT
        LDA 0, VCNT
        NEG 0,0
        STA 0, TDCNT
        LDA 2, PVTAB
        STA 2, TDP
TDLP:   LDA 0, TDCNT
        MOV 0,0,SNR
        JMP @TDRT
        LDA 2, TDP
        LDA 0, 0,2          ; name: high byte, low byte
        MOVS 0,0
        LDA 1, KFF
        AND 1,0
        JSR @XOUTC
        LDA 2, TDP
        LDA 0, 0,2
        LDA 1, KFF
        AND 1,0
        MOV 0,0,SZR
        JSR @XOUTC
        LDA 2, TDP
        LDA 0, 1,2          ; subscript
        MOV 0,0,SNR
        JMP TD1
        LDA 0, CLPAR
        JSR @XOUTC
        LDA 2, TDP
        LDA 0, 1,2
        JSR @XPR16
        LDA 0, CRPAR
        JSR @XOUTC
TD1:    LDA 0, CEQ
        JSR @XOUTC
        LDA 2, TDP
        LDA 0, 2,2
        STA 0, FA0
        LDA 0, 3,2
        STA 0, FA1
        JSR @XPRNUM
        JSR @XCRLF
        LDA 2, TDP
        LDA 0, K4
        ADD 0,2
        STA 2, TDP
        ISZ TDCNT
        JMP TDLP
        JMP TDLP
TDRT:   DW 0
TDCNT:  DW 0
TDP:    DW 0

; ASK items: "text" ! # and variables.  Each variable prints ':' and
; reads one line, evaluated as an expression (empty line = 0).
CASK:   STA 3, CART
CALP:   JSR @XSKSP
        JSR @XEOL
        JMP CA1
        JMP @CART
CA1:    LDA 1, CCOMMA
        SUB# 0,1,SNR
        JMP CASKIP
        JSR @XTSTR
        JMP CA2
        JMP CALP
CASKIP: ISZ TXP
        JMP CALP
CA2:    JSR @XGETVAR
        STA 2, CAVA
        LDA 0, CCOLON
        JSR @XOUTC
        LDA 2, PASKB
        JSR @XGETLN
        LDA 0, TXP
        STA 0, CATXP
        LDA 2, PASKB
        STA 2, TXP
        SUB 0,0
        STA 0, FA0
        STA 0, FA1
        JSR @XSKSP
        MOV 0,0,SZR
        JSR @XEXPR
        LDA 0, CATXP
        STA 0, TXP
        LDA 2, CAVA
        LDA 0, FA0
        STA 0, 0,2
        LDA 0, FA1
        STA 0, 1,2
        JMP CALP
CART:   DW 0
CAVA:   DW 0
CATXP:  DW 0

; FOR var = start [,step], end ; body
; Stack frame (7 words, frame base = SP-6):
;   +0 variable address  +1,+2 step  +3,+4 end  +5 body TXP  +6 CLP
CFOR:   STA 3, @SP
        JSR @XGETVAR
        STA 2, @SP
        JSR @XSKSP
        LDA 1, CEQ
        SUB# 0,1,SZR
        JMP CFBAD
        ISZ TXP
        JSR @XEXPR
        LDA 2, SP
        LDA 2, 0,2
        LDA 0, FA0
        STA 0, 0,2
        LDA 0, FA1
        STA 0, 1,2
        JSR @XSKSP
        LDA 1, CCOMMA
        SUB# 0,1,SZR
        JMP CFBAD
        ISZ TXP
        JSR @XEXPR
        LDA 0, FA0          ; provisional step slot holds 2nd value
        STA 0, @SP
        LDA 0, FA1
        STA 0, @SP
        JSR @XSKSP
        LDA 1, CCOMMA
        SUB# 0,1,SZR
        JMP CF2
        ISZ TXP             ; three values: start, step, end
        JSR @XEXPR
        LDA 0, FA0
        STA 0, @SP
        LDA 0, FA1
        STA 0, @SP
        JMP CF3
CF2:    LDA 2, SP           ; two values: end = 2nd, step = 1
        LDA 0, -1,2
        STA 0, @SP
        LDA 0, 0,2
        STA 0, @SP
        LDA 0, FONE
        STA 0, -1,2
        LDA 0, FONE+1
        STA 0, 0,2
CF3:    JSR @XSKSP
        LDA 1, CSEMI
        SUB# 0,1,SNR
        ISZ TXP
        LDA 0, TXP
        STA 0, @SP
        LDA 0, CLP
        STA 0, @SP
CFLP:   JSR CFFRM           ; test: done when (var - end) has the sign
        LDA 2, 0,2          ; of the step (and is nonzero)
        LDA 0, 0,2
        STA 0, FA0
        LDA 0, 1,2
        STA 0, FA1
        JSR CFFRM
        LDA 0, 3,2
        STA 0, FB0
        LDA 0, 4,2
        STA 0, FB1
        JSR @XFSUB
        LDA 0, FA0
        LDA 1, FA1
        MOV 0,0,SZR
        JMP CF4
        MOV 1,1,SNR
        JMP CFBODY
CF4:    JSR CFFRM
        LDA 1, 1,2          ; step sign
        LDA 2, K8000
        AND 2,0
        AND 2,1
        SUB# 0,1,SNR
        JMP CFDONE
CFBODY: JSR CFFRM
        LDA 0, 5,2
        STA 0, TXP
        LDA 0, 6,2
        STA 0, CLP
        LDA 0, K1
        SUB 1,1
        JSR @XRUNSEG
        LDA 0, QUITF
        MOV 0,0,SZR
        JMP CFDONE
        LDA 0, RETF
        MOV 0,0,SZR
        JMP CFDONE
        JSR CFFRM           ; var = var + step
        LDA 0, 1,2
        STA 0, FB0
        LDA 0, 2,2
        STA 0, FB1
        LDA 2, 0,2
        LDA 0, 0,2
        STA 0, FA0
        LDA 0, 1,2
        STA 0, FA1
        JSR @XFADD
        JSR CFFRM
        LDA 2, 0,2
        LDA 0, FA0
        STA 0, 0,2
        LDA 0, FA1
        STA 0, 1,2
        JMP CFLP
CFDONE: JSR CFFRM           ; resume at end of the FOR line
        LDA 0, 6,2
        STA 0, CLP
        LDA 2, 5,2
CFEOL:  LDA 0, 0,2
        MOV 0,0,SNR
        JMP CFEND
        INC 2,2
        JMP CFEOL
CFEND:  STA 2, TXP
        LDA 2, SP
        LDA 1, K7
        SUB 1,2
        STA 2, SP
        JMP @XRET
CFBAD:  JSR @XERR
        DW EMSYN

; CFFRM: AC2 = FOR frame base (SP-6).  Uses AC1.
CFFRM:  LDA 2, SP
        LDA 1, K6
        SUB 1,2
        JMP 0,3

; =====================================================================
; Expressions.  Result in FAC.
;   EXPR  := TERM { (+|-) TERM }
;   TERM  := UNARY { (*|/) UNARY }
;   UNARY := (-|+) UNARY | PRIM [ ^ UNARY ]
;   PRIM  := number | (expr) [expr] <expr> | var[(expr)] | Fxxx(expr)

EXPR:   STA 3, @SP
        JSR @XTERM
EXLP:   JSR @XSKSP
        LDA 1, CPLUS
        SUB# 0,1,SNR
        JMP EXOP
        LDA 1, CMINUS
        SUB# 0,1,SNR
        JMP EXOP
        JMP @XRET
EXOP:   STA 0, @SP
        LDA 0, FA0
        STA 0, @SP
        LDA 0, FA1
        STA 0, @SP
        ISZ TXP
        JSR @XTERM
        JSR POPOP
        LDA 1, CPLUS
        SUB# 0,1,SNR
        JMP EXADD
        JSR @XFSUB
        JMP EXLP
EXADD:  JSR @XFADD
        JMP EXLP

; POPOP: FOP = FAC, FAC = popped left operand, AC0 = popped operator.
POPOP:  LDA 0, FA0
        STA 0, FB0
        LDA 0, FA1
        STA 0, FB1
        LDA 2, SP
        LDA 0, 0,2
        STA 0, FA1
        LDA 0, -1,2
        STA 0, FA0
        LDA 0, -2,2
        LDA 1, K3
        SUB 1,2
        STA 2, SP
        JMP 0,3

TERM:   STA 3, @SP
        JSR @XUNARY
TMLP:   JSR @XSKSP
        LDA 1, CSTAR
        SUB# 0,1,SNR
        JMP TMOP
        LDA 1, CSLASH
        SUB# 0,1,SNR
        JMP TMOP
        JMP @XRET
TMOP:   STA 0, @SP
        LDA 0, FA0
        STA 0, @SP
        LDA 0, FA1
        STA 0, @SP
        ISZ TXP
        JSR @XUNARY
        JSR POPOP
        LDA 1, CSTAR
        SUB# 0,1,SNR
        JMP TMMUL
        JSR @XFDIV
        JMP TMLP
TMMUL:  JSR @XFMUL
        JMP TMLP

UNARY:  STA 3, @SP
        JSR @XSKSP
        LDA 1, CMINUS
        SUB# 0,1,SNR
        JMP UNNEG
        LDA 1, CPLUS
        SUB# 0,1,SNR
        JMP UNPOS
        JSR @XPRIM
        JSR @XSKSP
        LDA 1, CUP
        SUB# 0,1,SZR
        JMP @XRET
        LDA 0, FA0          ; x ^ n
        STA 0, @SP
        LDA 0, FA1
        STA 0, @SP
        ISZ TXP
        JSR @XUNARY
        JSR @XFIX16
        STA 0, UNPN
        LDA 2, SP
        LDA 0, 0,2
        STA 0, FA1
        LDA 0, -1,2
        STA 0, FA0
        DSZ SP
        DSZ SP
        LDA 0, UNPN
        JSR @XIPOW
        JMP @XRET
UNNEG:  ISZ TXP
        JSR @XUNARY
        JSR @XFNEG
        JMP @XRET
UNPOS:  ISZ TXP
        JSR @XUNARY
        JMP @XRET
UNPN:   DW 0

PRIM:   STA 3, @SP
        JSR @XSKSP
        LDA 1, CDOT
        SUB# 0,1,SNR
        JMP PRNUM1
        JSR @XISDIG
        JMP PR1
PRNUM1: JSR @XRDNUM
        JMP @XRET
PR1:    LDA 1, CLPAR        ; bracket pairs ( ) [ ] < >
        SUB# 0,1,SNR
        JMP PRPAR
        LDA 1, CLBRK
        SUB# 0,1,SNR
        JMP PRBRK
        LDA 1, CLT
        SUB# 0,1,SNR
        JMP PRANG
        JSR @XISLET
        JMP PRBAD
        LDA 1, CF
        SUB# 0,1,SNR
        JMP PRFUN
        JSR @XGETVAR
        LDA 0, 0,2
        STA 0, FA0
        LDA 0, 1,2
        STA 0, FA1
        JMP @XRET
PRPAR:  LDA 0, CRPAR
        JMP PRGRP
PRBRK:  LDA 0, CRBRK
        JMP PRGRP
PRANG:  LDA 0, CGT
PRGRP:  STA 0, @SP          ; push closing bracket
        LDA 2, SP
        LDA 3, PSTKL
        SUBZ# 3,2,SNC       ; skip if SP >= limit
        JMP PRG1
        JSR @XERR
        DW EMSTK
PRG1:   ISZ TXP
        JSR @XEXPR
        JSR @XSKSP
        LDA 2, SP
        LDA 1, 0,2
        DSZ SP
        SUB# 0,1,SZR
        JMP PRBAD
        ISZ TXP
        JMP @XRET
PRBAD:  JSR @XERR
        DW EMSYN
PRFUN:  JSR @XADVC          ; function: F + two letters, e.g. FABS
        STA 0, PRFK
        JSR @XADVC
        LDA 1, PRFK
        MOVS 1,1
        ADD 0,1
        STA 1, @SP          ; push key
PRF1:   JSR @XADVC
        JSR @XISLET
        JMP PRF2
        JMP PRF1
PRF2:   JSR @XSKSP
        LDA 1, CLPAR
        SUB# 0,1,SZR
        JMP PRBAD
        ISZ TXP
        JSR @XEXPR
        JSR @XSKSP
        LDA 1, CRPAR
        SUB# 0,1,SZR
        JMP PRBAD
        ISZ TXP
        LDA 2, SP           ; pop key
        LDA 0, 0,2
        DSZ SP
        LDA 2, PRFTP
PRFLP:  LDA 1, 0,2
        MOV 1,1,SNR
        JMP PRFBAD
        SUB# 0,1,SNR
        JMP PRFGO
        INC 2,2
        INC 2,2
        JMP PRFLP
PRFGO:  LDA 2, 1,2
        JSR 0,2
        JMP @XRET
PRFBAD: JSR @XERR
        DW EMFUN
PRFK:   DW 0
PRFTP:  DW PRFTAB
PRFTAB: DW 0o40502, FNABS   ; "AB"
        DW 0o51507, FNSGN   ; "SG"
        DW 0o44524, FNITR   ; "IT"
        DW 0o51521, FNSQT   ; "SQ"
        DW 0

FNABS:  LDA 0, FA0
        LDA 1, K7FFF
        AND 1,0
        STA 0, FA0
        JMP 0,3
FNSGN:  JMP @XFSGN
FNITR:  JMP @XFINT
FNSQT:  JMP @XFSQT

; GETVAR: parse a variable name (and subscript) at TXP; AC2 = address
; of its two-word value, created as 0 if new.  Recursive.
GETVAR: STA 3, @SP
        JSR @XSKSP
        JSR @XISLET
        JMP GVBAD
        LDA 1, CF           ; F names are functions
        SUB# 0,1,SNR
        JMP GVBAD
        MOVS 0,0
        STA 0, GVKEY
        JSR @XADVC
        JSR @XISALN
        JMP GV2
        LDA 1, GVKEY
        ADD 0,1
        STA 1, GVKEY
GV1:    JSR @XADVC          ; ignore further letters and digits
        JSR @XISALN
        JMP GV2
        JMP GV1
GV2:    LDA 0, GVKEY
        STA 0, @SP
        SUB 0,0
        STA 0, @SP          ; subscript 0
        JSR @XSKSP
        LDA 1, CLPAR
        SUB# 0,1,SZR
        JMP GV3
        ISZ TXP
        JSR @XEXPR
        JSR @XSKSP
        LDA 1, CRPAR
        SUB# 0,1,SZR
        JMP GVBAD
        ISZ TXP
        JSR @XFIX16
        LDA 2, SP
        STA 0, 0,2
GV3:    LDA 2, SP
        LDA 1, 0,2
        LDA 0, -1,2
        DSZ SP
        DSZ SP
        JSR @XVLOOK
        JMP @XRET
GVBAD:  JSR @XERR
        DW EMSYN
GVKEY:  DW 0

; VLOOK: AC0 = name key, AC1 = subscript -> AC2 = value address.
VLOOK:  STA 3, VLRT
        STA 0, VLK
        STA 1, VLS
        LDA 2, PVTAB
        LDA 3, VCNT
        NEG 3,3
        STA 3, VLC
        MOV 3,3,SNR
        JMP VLNEW
VLLP:   LDA 0, 0,2
        LDA 1, VLK
        SUB# 0,1,SZR
        JMP VLNX
        LDA 0, 1,2
        LDA 1, VLS
        SUB# 0,1,SZR
        JMP VLNX
        INC 2,2
        INC 2,2
        JMP @VLRT
VLNX:   LDA 0, K4
        ADD 0,2
        ISZ VLC
        JMP VLLP
VLNEW:  LDA 0, VCNT
        LDA 1, VMAX
        SUBZ# 1,0,SNC       ; skip if table full
        JMP VL1
        JSR @XERR
        DW EMVAR
VL1:    ISZ VCNT
        LDA 0, VLK
        STA 0, 0,2
        LDA 0, VLS
        STA 0, 1,2
        SUB 0,0
        STA 0, 2,2
        STA 0, 3,2
        INC 2,2
        INC 2,2
        JMP @VLRT
VLRT:   DW 0
VLK:    DW 0
VLS:    DW 0
VLC:    DW 0

; =====================================================================
; Number input and output.

; RDINT: read decimal digits at TXP -> AC0 (16-bit).
RDINT:  STA 3, RIRT
        SUB 0,0
        STA 0, RIV
RILP:   LDA 2, TXP
        LDA 0, 0,2
        JSR @XISDIG
        JMP RIDN
        STA 1, RID
        LDA 0, RIV          ; v = v*10 + d
        MOVZL 0,0
        MOV 0,1
        MOVZL 0,0
        MOVZL 0,0
        ADD 1,0
        LDA 1, RID
        ADD 1,0
        STA 0, RIV
        ISZ TXP
        JMP RILP
RIDN:   LDA 0, RIV
        JMP @RIRT
RIRT:   DW 0
RIV:    DW 0
RID:    DW 0

; RDNUM: read a number (digits, '.', digits, optional E[+-]digits) at
; TXP -> FAC.
RDNUM:  STA 3, RNRT
        SUB 0,0
        STA 0, FA0
        STA 0, FA1
        STA 0, RNK
        STA 0, RNE
RN1:    LDA 2, TXP
        LDA 0, 0,2
        JSR @XISDIG
        JMP RN2
        MOV 1,0
        JSR @XMUL10
        ISZ TXP
        JMP RN1
RN2:    LDA 1, CDOT
        SUB# 0,1,SZR
        JMP RN4
RN3:    JSR @XADVC
        JSR @XISDIG
        JMP RN4
        MOV 1,0
        JSR @XMUL10
        ISZ RNK
        JMP RN3
        JMP RN3
RN4:    LDA 1, CE           ; exponent only if E is followed by a
        SUB# 0,1,SZR        ; digit or sign
        JMP RNSC
        LDA 2, TXP
        LDA 0, 1,2
        SUB 1,1
        STA 1, RNEN
        LDA 1, CMINUS
        SUB# 0,1,SNR
        JMP RNEM
        LDA 1, CPLUS
        SUB# 0,1,SNR
        JMP RNEP
        JSR @XISDIG
        JMP RNSC
        JMP RNED
RNEM:   LDA 1, K1
        STA 1, RNEN
RNEP:   ISZ TXP
RNED:   ISZ TXP
        JSR @XRDINT
        LDA 1, RNEN
        MOV 1,1,SZR
        NEG 0,0
        STA 0, RNE
RNSC:   LDA 0, RNE          ; scale by 10^(e-k)
        LDA 1, RNK
        SUB 1,0
        MOV 0,0,SNR
        JMP @RNRT
        STA 0, RNP
        MOVL# 0,0,SZC
        NEG 0,0
        JSR @XPOW10         ; FOP = 10^|p|
        LDA 0, RNP
        MOVL# 0,0,SZC
        JMP RNDIV
        JSR @XFMUL
        JMP @RNRT
RNDIV:  JSR @XFDIV
        JMP @RNRT
RNRT:   DW 0
RNK:    DW 0
RNE:    DW 0
RNEN:   DW 0
RNP:    DW 0

; MUL10: FAC = FAC*10 + AC0 (digit).
MUL10:  STA 3, MTRT
        STA 0, MTD
        LDA 2, PFTEN
        JSR @XLDFB
        JSR @XFMUL
        LDA 0, FA0
        STA 0, MTS0
        LDA 0, FA1
        STA 0, MTS1
        LDA 0, MTD
        JSR @XFLT16
        LDA 0, MTS0
        STA 0, FB0
        LDA 0, MTS1
        STA 0, FB1
        JSR @XFADD
        JMP @MTRT
MTRT:   DW 0
MTD:    DW 0
MTS0:   DW 0
MTS1:   DW 0

; POW10: FOP = 10^AC0 (AC0 >= 0).  FAC preserved.
POW10:  STA 3, PWRT
        NEG 0,0
        STA 0, PWC
        LDA 0, FA0
        STA 0, PWS0
        LDA 0, FA1
        STA 0, PWS1
        LDA 2, PFONE
        JSR @XLDFA
PWLP:   LDA 0, PWC
        MOV 0,0,SNR
        JMP PWDN
        LDA 2, PFTEN
        JSR @XLDFB
        JSR @XFMUL
        ISZ PWC
        JMP PWLP
PWDN:   LDA 0, FA0
        STA 0, FB0
        LDA 0, FA1
        STA 0, FB1
        LDA 0, PWS0
        STA 0, FA0
        LDA 0, PWS1
        STA 0, FA1
        JMP @PWRT
PWRT:   DW 0
PWC:    DW 0
PWS0:   DW 0
PWS1:   DW 0

; PR16: print AC0 as a signed decimal integer.
PR16:   STA 3, P6RT
        MOVL# 0,0,SNC       ; skip if negative
        JMP P61
        NEG 0,0
        STA 0, P6V
        LDA 0, CMINUS
        JSR @XOUTC
        LDA 0, P6V
P61:    SUB 1,1
        STA 1, P6N
P6LP:   LDA 1, K10
        JSR @XDIV16
        LDA 2, P6BP
        LDA 3, P6N
        ADD 3,2
        STA 1, 0,2
        ISZ P6N
        MOV 0,0,SZR
        JMP P6LP
P6OUT:  DSZ P6N
        JMP P62
        JMP P62
P62:    LDA 2, P6BP
        LDA 3, P6N
        ADD 3,2
        LDA 0, 0,2
        LDA 1, CZERO
        ADD 1,0
        JSR @XOUTC
        LDA 0, P6N
        MOV 0,0,SZR
        JMP P6OUT
        JMP @P6RT
P6RT:   DW 0
P6V:    DW 0
P6N:    DW 0
P6BP:   DW P6BUF
P6BUF:  DW 0, 0, 0, 0, 0, 0

; PRNUM: print FAC using FMTW/FMTD: FMTW digit positions, FMTD of them
; after the point, right-justified, then a sign column (' ' or '-').
; E format when FMTW is 0 or the value needs more than FMTW digits.
PRNUM:  STA 3, PNRT
        LDA 0, FA0
        LDA 1, K8000
        AND 0,1
        STA 1, PNNEG
        LDA 1, K7FFF
        AND 1,0
        STA 0, FA0
        STA 0, PNS0
        LDA 0, FA1
        STA 0, PNS1
        LDA 0, FMTW
        MOV 0,0,SNR
        JMP PNEF
        LDA 0, FMTD
        JSR @XPOW10
        JSR @XFMUL
        JSR @XFIXR
        MOV 0,0,SZR
        JMP PNEF
        LDA 0, FMTD         ; at least FMTD+1 digits
        INC 0,0
        JSR PNDIG
        LDA 0, PNND         ; more digits than the field: E format
        LDA 1, FMTW
        ADCZ# 1,0,SZC       ; skip if digits <= width
        JMP PNEF
        SUB 0,1             ; pad = width - digits
        STA 1, PNPAD
PNPL:   LDA 1, PNPAD
        MOV 1,1,SNR
        JMP PN1
        LDA 0, CSP
        JSR @XOUTC
        DSZ PNPAD
        JMP PNPL
PN1:    JSR PNSIGN
PNDL:   LDA 1, PNND         ; digits, most significant first
        LDA 0, FMTD
        SUB# 0,1,SZR
        JMP PN2
        MOV 0,0,SNR
        JMP PN2
        LDA 0, CDOT
        JSR @XOUTC
PN2:    DSZ PNND
        NOP
        JSR PNOUT
        LDA 1, PNND
        MOV 1,1,SZR
        JMP PNDL
        JMP @PNRT
PNEF:   LDA 3, PNRT         ; E format lives further on
        JMP @PNEFP
PNEFP:  DW PNEFMT
PNRT:   DW 0
PNNEG:  DW 0
PNS0:   DW 0
PNS1:   DW 0
PNPAD:  DW 0

; PNSIGN: print '-' if the value is negative and has a nonzero digit,
; else a space.
PNSIGN: LDA 0, CSP
        LDA 1, PNNEG
        MOV 1,1,SNR
        JMP @XOUTC
        LDA 1, PNNZ
        MOV 1,1,SZR
        LDA 0, CMINUS
        JMP @XOUTC

; PNOUT: print digit PNND from the digit buffer.
PNOUT:  STA 3, PORT
        LDA 2, PNBP
        LDA 1, PNND
        ADD 1,2
        LDA 0, 0,2
        LDA 1, CZERO
        ADD 1,0
        JSR @XOUTC
        JMP @PORT
PORT:   DW 0

; PNDIG: convert FXH:FXL to decimal digits (least significant first) in
; PNBUF, producing at least AC0 digits.  Sets PNND and PNNZ.
PNDIG:  STA 3, PDRT
        STA 0, PDMIN
        SUB 0,0
        STA 0, PNND
        STA 0, PNNZ
PDLP:   LDA 0, FXH
        LDA 1, FXL
        JSR @XDIV10
        STA 0, FXH
        STA 1, FXL
        MOV 2,2,SZR
        ISZ PNNZ
        NOP
        LDA 3, PNBP
        LDA 1, PNND
        ADD 1,3
        STA 2, 0,3
        ISZ PNND
        LDA 0, FXH
        MOV 0,0,SZR
        JMP PDLP
        LDA 0, FXL
        MOV 0,0,SZR
        JMP PDLP
        LDA 0, PNND
        LDA 1, PDMIN
        SUBZ# 1,0,SZC       ; skip if fewer than the minimum
        JMP @PDRT
        JMP PDLP
PDRT:   DW 0
PDMIN:  DW 0
PNND:   DW 0
PNNZ:   DW 0
PNBP:   DW PNBUF
PNBUF:  DW 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0

; PNEFMT: E format, -0.dddddd E+ee
PNEFMT: STA 3, PERT
        LDA 0, PNS0
        STA 0, FA0
        LDA 0, PNS1
        STA 0, FA1
        SUB 0,0
        STA 0, PEEXP
        LDA 0, FA0
        MOV 0,0,SNR
        JMP PE3
PE1:    LDA 2, PFONE        ; while x >= 1: x /= 10
        JSR @XFGE
        JMP PE2
        LDA 2, PFTEN
        JSR @XLDFB
        JSR @XFDIV
        ISZ PEEXP
        JMP PE1
        JMP PE1
PE2:    LDA 0, FA0          ; while x*10 < 1: x *= 10
        STA 0, PES0
        LDA 0, FA1
        STA 0, PES1
        LDA 2, PFTEN
        JSR @XLDFB
        JSR @XFMUL
        LDA 2, PFONE
        JSR @XFGE
        JMP PE2A
        LDA 0, PES0
        STA 0, FA0
        LDA 0, PES1
        STA 0, FA1
        JMP PE3
PE2A:   DSZ PEEXP
        JMP PE2
        JMP PE2
PE3:    LDA 2, PFMIL        ; digits = round(x * 1e6)
        JSR @XLDFB
        JSR @XFMUL
        JSR @XFIXR
        LDA 0, FXH          ; 1000000 = 0x000F4240: round-up carry
        LDA 1, PEMILH
        SUB# 0,1,SZR
        JMP PE4
        LDA 0, FXL
        LDA 1, PEMILL
        SUB# 0,1,SZR
        JMP PE4
        LDA 0, PE100H
        STA 0, FXH
        LDA 0, PE100L
        STA 0, FXL
        ISZ PEEXP
        NOP
PE4:    LDA 0, K6
        JSR PNDIG
        JSR PNSIGN
        LDA 0, CZERO
        JSR @XOUTC
        LDA 0, CDOT
        JSR @XOUTC
PE6:    DSZ PNND
        NOP
        JSR PNOUT
        LDA 1, PNND
        MOV 1,1,SZR
        JMP PE6
        LDA 0, CE
        JSR @XOUTC
        LDA 0, PEEXP
        LDA 1, CPLUS
        MOVL# 0,0,SZC
        LDA 1, CMINUS
        MOVL# 0,0,SZC
        NEG 0,0
        STA 0, PEEXP
        MOV 1,0
        JSR @XOUTC
        LDA 0, PEEXP
        JSR @XPR2D
        JMP @PERT
PERT:   DW 0
PEEXP:  DW 0
PES0:   DW 0
PES1:   DW 0
PEMILH: DW 0o17
PEMILL: DW 0o41100
PE100H: DW 1
PE100L: DW 0o103240

; =====================================================================
; Integer helpers.

; DIV16: AC0 / AC1 (unsigned) -> AC0 quotient, AC1 remainder.
DIV16:  STA 3, DVRT
        STA 1, DVD
        SUB 1,1
        LDA 2, KM16
        STA 2, DVC
DVLP:   MOVZL 0,0
        MOVL 1,1
        LDA 2, DVD
        SUBZ# 2,1,SZC       ; skip if remainder < divisor
        JMP DVSB
        JMP DVNX
DVSB:   SUB 2,1
        INC 0,0
DVNX:   ISZ DVC
        JMP DVLP
        JMP @DVRT
DVRT:   DW 0
DVD:    DW 0
DVC:    DW 0

; DIV10: AC0:AC1 / 10 (unsigned 32-bit) -> AC0:AC1 quotient, AC2 rem.
DIV10:  STA 3, D1RT
        SUB 2,2
        LDA 3, KM32
        STA 3, D1C
D1LP:   MOVZL 1,1
        MOVL 0,0
        MOVL 2,2
        LDA 3, K10
        SUBZ# 3,2,SZC       ; skip if remainder < 10
        JMP D1SB
        JMP D1NX
D1SB:   SUB 3,2
        INC 1,1
D1NX:   ISZ D1C
        JMP D1LP
        JMP @D1RT
D1RT:   DW 0
D1C:    DW 0

; =====================================================================
; Floating point.  Packed: w0 = S|EEEEEEE|FFFFFFFF, w1 = FFFF...;
; value = 0.F * 16^(E-64).  Zero is 0,0.  Unpacked records hold
; sign (0 or 0x8000), unbiased exponent, mantissa hi, lo (24 fraction
; bits in hi and the top byte of lo, guard bits below).

; LDFB / LDFA: load FOP / FAC from the packed float at AC2.
LDFB:   LDA 0, 0,2
        STA 0, FB0
        LDA 0, 1,2
        STA 0, FB1
        JMP 0,3
LDFA:   LDA 0, 0,2
        STA 0, FA0
        LDA 0, 1,2
        STA 0, FA1
        JMP 0,3

; FGE: skip return if FAC >= the packed float at AC2 (both >= 0).
FGE:    LDA 0, FA0
        LDA 1, 0,2
        SUB# 0,1,SZR
        JMP FGE1
        LDA 0, FA1
        LDA 1, 1,2
FGE1:   SUBZ# 1,0,SZC       ; skip if FAC < value
        JMP 1,3
        JMP 0,3

; UNPK: AC2 = packed float -> record at UPD.
UNPK:   STA 3, UPRT
        LDA 0, 0,2
        LDA 1, 1,2
        STA 0, UPW0
        STA 1, UPW1
        LDA 2, UPD
        LDA 3, KFF
        AND 0,3
        MOV 1,1,SZR
        JMP UPNZ
        MOV 3,3,SZR
        JMP UPNZ
        SUB 0,0
        STA 0, 0,2
        STA 0, 1,2
        STA 0, 2,2
        STA 0, 3,2
        JMP @UPRT
UPNZ:   LDA 0, UPW0
        LDA 3, K8000
        AND 0,3
        STA 3, 0,2          ; sign
        MOVS 0,3
        LDA 1, K177
        AND 1,3
        LDA 1, K64
        SUB 1,3
        STA 3, 1,2          ; exponent
        MOVS 0,3
        LDA 1, KFF00
        AND 1,3
        LDA 0, UPW1
        MOVS 0,0
        LDA 1, KFF
        AND 0,1
        ADD 1,3
        STA 3, 2,2          ; mantissa hi
        LDA 1, KFF00
        AND 1,0
        STA 0, 3,2          ; mantissa lo
        JMP @UPRT
UPRT:   DW 0
UPW0:   DW 0
UPW1:   DW 0

; UNPAB: unpack FAC into A and FOP into B.
UNPAB:  STA 3, UABRT
        LDA 2, PUA
        STA 2, UPD
        LDA 2, PFA
        JSR @XUNPK
        LDA 2, PUB
        STA 2, UPD
        LDA 2, PFB
        JSR @XUNPK
        JMP @UABRT
UABRT:   DW 0

; NORMA: normalise A (top hex digit nonzero); zero becomes all zero.
NORMA:  LDA 0, UAH
        LDA 1, UAL
        MOV 0,0,SZR
        JMP NMLP
        MOV 1,1,SZR
        JMP NMLP
        STA 0, UAS
        STA 0, UAE
        STA 0, UAL
        JMP 0,3
NMLP:   LDA 2, KF000
        AND# 0,2,SZR        ; skip if top digit zero
        JMP NMDN
        MOVZL 1,1
        MOVL 0,0
        MOVZL 1,1
        MOVL 0,0
        MOVZL 1,1
        MOVL 0,0
        MOVZL 1,1
        MOVL 0,0
        LDA 2, UAE
        NEG 2,2
        COM 2,2
        STA 2, UAE
        JMP NMLP
NMDN:   STA 0, UAH
        STA 1, UAL
        JMP 0,3

; PACKA: round A and pack it into FAC.
PACKA:  STA 3, PKRT
        LDA 0, UAH
        LDA 1, UAL
        MOV 0,0,SNR
        JMP PKZERO
        LDA 2, K200         ; round at the 24th fraction bit
        ADDZ 2,1,SZC
        INC 0,0
        MOV 0,0,SZR
        JMP PKR1
        LDA 0, K1000H       ; carried out: 0x1000 0000, exponent+1
        LDA 2, UAE
        INC 2,2
        STA 2, UAE
PKR1:   LDA 2, UAE
        LDA 3, K64
        ADD 3,2
        MOVL# 2,2,SZC       ; skip if biased exponent >= 0
        JMP PKZERO
        LDA 3, K177
        ADCZ# 3,2,SZC       ; skip if biased exponent <= 127
        JMP PKOVF
        MOVS 2,2
        LDA 3, UAS
        ADD 3,2
        MOVS 0,3
        STA 3, PKT
        LDA 0, KFF
        AND 0,3
        ADD 3,2
        STA 2, FA0
        LDA 3, PKT
        LDA 0, KFF00
        AND 0,3
        MOVS 1,1
        LDA 0, KFF
        AND 0,1
        ADD 1,3
        STA 3, FA1
        JMP @PKRT
PKZERO: SUB 0,0
        STA 0, FA0
        STA 0, FA1
        JMP @PKRT
PKOVF:  JSR @XERR
        DW EMOVF
PKRT:   DW 0
PKT:    DW 0

; SWAB: exchange records A and B.  Preserves AC0.
SWAB:   LDA 1, UAS
        LDA 2, UBS
        STA 1, UBS
        STA 2, UAS
        LDA 1, UAE
        LDA 2, UBE
        STA 1, UBE
        STA 2, UAE
        LDA 1, UAH
        LDA 2, UBH
        STA 1, UBH
        STA 2, UAH
        LDA 1, UAL
        LDA 2, UBL
        STA 1, UBL
        STA 2, UAL
        JMP 0,3

; FNEG: FAC = -FAC.
FNEG:   LDA 0, FA0
        LDA 1, FA1
        MOV 0,0,SZR
        JMP FNG1
        MOV 1,1,SNR
        JMP 0,3
FNG1:   LDA 1, K8000
        ADD 1,0
        STA 0, FA0
        JMP 0,3

; FSUB: FAC = FAC - FOP.
FSUB:   LDA 0, FB0
        LDA 1, K8000
        ADD 1,0
        STA 0, FB0
        JMP @XFADD

; FADD: FAC = FAC + FOP.
FADD:   STA 3, FART
        JSR @XUNPAB
        LDA 0, UBH
        MOV 0,0,SNR
        JMP @FART
        LDA 0, UAH
        MOV 0,0,SZR
        JMP FAD1
        LDA 0, FB0
        STA 0, FA0
        LDA 0, FB1
        STA 0, FA1
        JMP @FART
FAD1:   LDA 0, UAE          ; align: A gets the larger exponent
        LDA 1, UBE
        SUB 1,0
        MOVL# 0,0,SNC       ; skip if A's exponent is smaller
        JMP FA2
        JSR @XSWAB
        NEG 0,0
FA2:    LDA 1, K8
        ADCZ# 1,0,SZC       ; skip if difference <= 8
        JMP FAST0
        STA 0, FACNT
        LDA 0, UBH
        LDA 1, UBL
FASH:   LDA 2, FACNT
        MOV 2,2,SNR
        JMP FASHD
        MOVZR 0,0
        MOVR 1,1
        MOVZR 0,0
        MOVR 1,1
        MOVZR 0,0
        MOVR 1,1
        MOVZR 0,0
        MOVR 1,1
        DSZ FACNT
        JMP FASH
FASHD:  STA 0, UBH
        STA 1, UBL
        LDA 0, UAS
        LDA 1, UBS
        SUB# 0,1,SZR        ; skip if same sign
        JMP FASUB
        LDA 0, UAH
        LDA 1, UAL
        LDA 2, UBH
        LDA 3, UBL
        ADDZ 3,1,SNC        ; skip if carry out of lo
        JMP FANL
        INCZ 0,0,SZC        ; skip if hi did not wrap
        JMP FAHV0
FANL:   ADDZ 2,0,SZC        ; skip if no carry out of hi
        JMP FAOV
        JMP FAST
FAHV0:  ADD 2,0
FAOV:   MOVOR 0,0           ; shift the carry back in, exponent+1
        MOVR 1,1
        MOVZR 0,0
        MOVR 1,1
        MOVZR 0,0
        MOVR 1,1
        MOVZR 0,0
        MOVR 1,1
        LDA 2, UAE
        INC 2,2
        STA 2, UAE
FAST:   STA 0, UAH
        STA 1, UAL
FAST0:  JSR @XNORM
        JSR @XPACK
        JMP @FART
FASUB:  LDA 0, UAH          ; subtract the smaller magnitude
        LDA 2, UBH
        SUB# 2,0,SZR
        JMP FAC1
        LDA 1, UAL
        LDA 3, UBL
        SUBZ# 3,1,SZC       ; skip if A lo < B lo
        JMP FAGE
        JMP FALT
FAC1:   SUBZ# 2,0,SZC       ; skip if A hi < B hi
        JMP FAGE
FALT:   JSR @XSWAB
FAGE:   LDA 0, UAH
        LDA 1, UAL
        LDA 2, UBH
        LDA 3, UBL
        SUBZ 3,1,SZC        ; skip if borrow
        JMP FANB
        NEG 0,0
        COM 0,0
FANB:   SUB 2,0
        JMP FAST
FART:   DW 0
FACNT:  DW 0

; UMUL: AC0 * AC1 (unsigned) -> AC0 hi, AC1 lo.
UMUL:   STA 3, UMRT
        STA 0, UMX
        STA 1, UMY
        LDA 2, KM16
        STA 2, UMCT
        SUB 0,0
        SUB 1,1
        LDA 2, UMX
UMLP:   MOVZL 1,1
        MOVL 0,0
        MOVZL 2,2,SNC       ; skip if multiplier bit set
        JMP UMNX
        LDA 3, UMY
        ADDZ 3,1,SZC
        INC 0,0
UMNX:   ISZ UMCT
        JMP UMLP
        JMP @UMRT
UMRT:   DW 0
UMX:    DW 0
UMY:    DW 0
UMCT:   DW 0

; FMUL: FAC = FAC * FOP.
FMUL:   STA 3, FMRT
        JSR @XUNPAB
        LDA 0, UAH
        MOV 0,0,SNR
        JMP FMZ
        LDA 0, UBH
        MOV 0,0,SNR
        JMP FMZ
        LDA 0, UAS
        LDA 1, UBS
        ADD 1,0
        STA 0, UAS
        LDA 0, UAE
        LDA 1, UBE
        ADD 1,0
        STA 0, UAE
        LDA 0, UAH          ; hi*hi
        LDA 1, UBH
        JSR @XUMUL
        STA 0, FMH
        STA 1, FML
        LDA 0, UAH          ; + (hi*lo) >> 16
        LDA 1, UBL
        JSR @XUMUL
        LDA 1, FML
        ADDZ 0,1,SZC
        ISZ FMH
        NOP
        STA 1, FML
        LDA 0, UAL          ; + (lo*hi) >> 16
        LDA 1, UBH
        JSR @XUMUL
        LDA 1, FML
        ADDZ 0,1,SZC
        ISZ FMH
        NOP
        STA 1, UAL
        LDA 0, FMH
        STA 0, UAH
        JSR @XNORM
        JSR @XPACK
        JMP @FMRT
FMZ:    SUB 0,0
        STA 0, FA0
        STA 0, FA1
        JMP @FMRT
FMRT:   DW 0
FMH:    DW 0
FML:    DW 0

; FDIV: FAC = FAC / FOP.
FDIV:   STA 3, FDRT
        JSR @XUNPAB
        LDA 0, UBH
        MOV 0,0,SZR
        JMP FD1
        JSR @XERR
        DW EMDIV
FD1:    LDA 0, UAH
        MOV 0,0,SNR
        JMP FDZ
        LDA 0, UAS
        LDA 1, UBS
        ADD 1,0
        STA 0, UAS
        LDA 0, UAE
        LDA 1, UBE
        SUB 1,0
        STA 0, UAE
        LDA 0, UAH          ; make A < B
        LDA 1, UAL
        LDA 2, UBH
        SUB# 2,0,SZR
        JMP FD2
        LDA 3, UBL
        SUBZ# 3,1,SZC       ; skip if A lo < B lo
        JMP FDSH
        JMP FD3
FD2:    SUBZ# 2,0,SZC       ; skip if A hi < B hi
        JMP FDSH
        JMP FD3
FDSH:   MOVZR 0,0
        MOVR 1,1
        MOVZR 0,0
        MOVR 1,1
        MOVZR 0,0
        MOVR 1,1
        MOVZR 0,0
        MOVR 1,1
        LDA 2, UAE
        INC 2,2
        STA 2, UAE
FD3:    SUB 2,2
        STA 2, FDQH
        STA 2, FDQL
        LDA 2, KM32
        STA 2, FDCT
FDLP:   MOVZL 1,1           ; remainder <<= 1, top bit to AC2
        MOVL 0,0
        LDA 2, K0           ; (LDA keeps carry; SUB would not)
        MOVL 2,2
        LDA 3, FDQL         ; quotient <<= 1
        MOVZL 3,3
        STA 3, FDQL
        LDA 3, FDQH
        MOVL 3,3
        STA 3, FDQH
        MOV 2,2,SZR
        JMP FDSUB
        LDA 2, UBH
        SUB# 2,0,SZR
        JMP FDC1
        LDA 3, UBL
        SUBZ# 3,1,SZC       ; skip if remainder lo < B lo
        JMP FDSUB
        JMP FDNX
FDC1:   SUBZ# 2,0,SZC       ; skip if remainder hi < B hi
        JMP FDSUB
        JMP FDNX
FDSUB:  LDA 2, UBH
        LDA 3, UBL
        SUBZ 3,1,SZC        ; skip if borrow
        JMP FDNB
        NEG 0,0
        COM 0,0
FDNB:   SUB 2,0
        ISZ FDQL
        NOP
FDNX:   ISZ FDCT
        JMP FDLP
        LDA 0, FDQH
        STA 0, UAH
        LDA 0, FDQL
        STA 0, UAL
        JSR @XNORM
        JSR @XPACK
        JMP @FDRT
FDZ:    SUB 0,0
        STA 0, FA0
        STA 0, FA1
        JMP @FDRT
FDRT:   DW 0
FDQH:   DW 0
FDQL:   DW 0
FDCT:   DW 0

; FLT16: FAC = float(AC0), AC0 signed.
FLT16:  STA 3, FLTRT
        MOV 0,0,SZR
        JMP FL1
        STA 0, FA0
        STA 0, FA1
        JMP @FLTRT
FL1:    SUB 1,1
        MOVL# 0,0,SNC       ; skip if negative
        JMP FL2
        NEG 0,0
        LDA 1, K8000
FL2:    STA 1, UAS
        STA 0, UAH
        SUB 1,1
        STA 1, UAL
        LDA 1, K4
        STA 1, UAE
        JSR @XNORM
        JSR @XPACK
        JMP @FLTRT
FLTRT:   DW 0

; FIX32: truncate FAC -> FXS sign, FXH:FXL magnitude.
; FIXR:  the same, rounded to nearest (half away from zero).
; AC0 = 0 if it fits, 1 if |FAC| >= 2^32.
FIXR:   STA 3, FXRT
        LDA 0, K1
        JMP FXGO
FIX32:  STA 3, FXRT
        SUB 0,0
FXGO:   STA 0, FXRND
        LDA 2, PUA
        STA 2, UPD
        LDA 2, PFA
        JSR @XUNPK
        LDA 0, UAS
        STA 0, FXS
        SUB 0,0
        STA 0, FXH
        STA 0, FXL
        LDA 0, UAH
        MOV 0,0,SNR
        JMP FXOK
        LDA 2, UAE
        MOVL# 2,2,SZC       ; skip if exponent >= 0
        JMP FXOK
        LDA 3, K8
        ADCZ# 3,2,SZC       ; skip if exponent <= 8
        JMP FXOVF
        SUB 2,3             ; bits to drop = 4 * (8 - exponent)
        MOVZL 3,3
        MOVZL 3,3
        STA 3, FXCT
        LDA 0, UAH
        LDA 1, UAL
        LDA 2, FXRND
        MOV 2,2,SNR
        JMP FXTR
        MOV 3,3,SNR         ; nothing dropped: already exact
        JMP FXST
        DSZ FXCT            ; drop all but the half bit, add it, drop it
        NOP
        JSR FXSHR
        INCZ 1,1,SZC        ; skip if no carry out of lo
        INC 0,0
        MOVZR 0,0
        MOVR 1,1
        JMP FXST
FXTR:   JSR FXSHR
FXST:   STA 0, FXH
        STA 1, FXL
FXOK:   SUB 0,0
        JMP @FXRT
FXOVF:  LDA 0, K1
        JMP @FXRT
FXRT:   DW 0
FXCT:   DW 0
FXRND:  DW 0

; FXSHR: shift AC0:AC1 right FXCT bits.  Uses AC2; keeps AC3.
FXSHR:  LDA 2, FXCT
FXSL:   MOV 2,2,SNR
        JMP 0,3
        MOVZR 0,0
        MOVR 1,1
        NEG 2,2
        COM 2,2
        JMP FXSL

; FIX16: FAC -> AC0, signed 16-bit, truncated (FIXR16: rounded).
; Errors if too big.
FIXR16: STA 3, F6RT         ; rounded variant
        JSR @XFIXR
        JMP F6CHK
FIX16:  STA 3, F6RT
        JSR @XFIX32
F6CHK:  MOV 0,0,SZR
        JMP F6BAD
        LDA 0, FXH
        MOV 0,0,SZR
        JMP F6BAD
        LDA 0, FXL
        MOVL# 0,0,SZC       ; skip if < 0x8000
        JMP F6BAD
        LDA 1, FXS
        MOV 1,1,SZR
        NEG 0,0
        JMP @F6RT
F6BAD:  JSR @XERR
        DW EMOVF
F6RT:   DW 0

; FINT: FAC = integer part of FAC (FITR).
FINT:   STA 3, FIRT
        JSR @XFIX32
        MOV 0,0,SZR
        JMP @FIRT
        LDA 0, FXS
        STA 0, UAS
        LDA 0, FXH
        STA 0, UAH
        LDA 0, FXL
        STA 0, UAL
        LDA 0, K8
        STA 0, UAE
        JSR @XNORM
        JSR @XPACK
        JMP @FIRT
FIRT:   DW 0

; FSGN: FAC = -1, 0 or 1.
FSGN:   STA 3, FGRT
        LDA 0, FA0
        LDA 1, FA1
        MOV 0,0,SZR
        JMP FG1
        MOV 1,1,SNR
        JMP @FGRT
FG1:    LDA 1, K8000
        AND 1,0
        LDA 1, FONE
        ADD 1,0
        STA 0, FA0
        SUB 0,0
        STA 0, FA1
        JMP @FGRT
FGRT:   DW 0

; IPOW: FAC = FAC ^ AC0 (integer power).
IPOW:   STA 3, IPRT
        STA 0, IPN
        LDA 0, FA0
        STA 0, IPX0
        LDA 0, FA1
        STA 0, IPX1
        LDA 2, PFONE
        JSR @XLDFA
        LDA 0, IPN
        MOVL# 0,0,SZC
        NEG 0,0
        NEG 0,0
        STA 0, IPC
IPLP:   LDA 0, IPC
        MOV 0,0,SNR
        JMP IPDN
        LDA 0, IPX0
        STA 0, FB0
        LDA 0, IPX1
        STA 0, FB1
        JSR @XFMUL
        ISZ IPC
        JMP IPLP
IPDN:   LDA 0, IPN
        MOVL# 0,0,SNC       ; skip if negative power
        JMP @IPRT
        LDA 0, FA0
        STA 0, FB0
        LDA 0, FA1
        STA 0, FB1
        LDA 2, PFONE
        JSR @XLDFA
        JSR @XFDIV
        JMP @IPRT
IPRT:   DW 0
IPN:    DW 0
IPX0:   DW 0
IPX1:   DW 0
IPC:    DW 0

; FSQRT: FAC = sqrt(FAC) by Newton's method from a halved exponent.
FSQRT:  STA 3, SQRT
        LDA 0, FA0
        LDA 1, FA1
        MOV 0,0,SZR
        JMP SQ1
        MOV 1,1,SNR
        JMP @SQRT
SQ1:    MOVL# 0,0,SNC       ; skip if negative
        JMP SQ2
        JSR @XERR
        DW EMFUN
SQ2:    STA 0, SQX0
        STA 1, SQX1
        LDA 2, PUA          ; guess: same mantissa, exponent / 2
        STA 2, UPD
        LDA 2, PFA
        JSR @XUNPK
        LDA 0, UAE
        MOVL# 0,0,SZC
        JMP SQNEG
        MOVZR 0,0
        JMP SQ3
SQNEG:  MOVOR 0,0
SQ3:    STA 0, UAE
        JSR @XPACK
        LDA 0, KM16
        LDA 1, K8
        ADD 1,0
        STA 0, SQC          ; 8 iterations
SQLP:   LDA 0, FA0          ; g = (g + x/g) / 2
        STA 0, SQG0
        STA 0, FB0
        LDA 0, FA1
        STA 0, SQG1
        STA 0, FB1
        LDA 0, SQX0
        STA 0, FA0
        LDA 0, SQX1
        STA 0, FA1
        JSR @XFDIV
        LDA 0, SQG0
        STA 0, FB0
        LDA 0, SQG1
        STA 0, FB1
        JSR @XFADD
        LDA 2, PFHALF
        JSR @XLDFB
        JSR @XFMUL
        ISZ SQC
        JMP SQLP
        JMP @SQRT
SQRT:   DW 0
SQX0:   DW 0
SQX1:   DW 0
SQG0:   DW 0
SQG1:   DW 0
SQC:    DW 0

; =====================================================================
; Messages (one char per word, NUL-terminated).
BANNER: DW 0o015, 0o012
        .TXT "FOCAL/Nova V0.1"
        DW 0o015, 0o012, 0
ERAT:   .TXT " @ "
        DW 0
EMSYN:  .TXT "SYN"
        DW 0
EMLIN:  .TXT "LIN"
        DW 0
EMCMD:  .TXT "CMD"
        DW 0
EMDIV:  .TXT "DIV"
        DW 0
EMOVF:  .TXT "OVF"
        DW 0
EMMEM:  .TXT "MEM"
        DW 0
EMSTK:  .TXT "STK"
        DW 0
EMVAR:  .TXT "VAR"
        DW 0
EMFUN:  .TXT "FUN"
        DW 0

; Page-zero image is appended here by abs2flat.py --pz.  Keep last.
PZIMG:
