; lobbymon.asm: FujiNet lobby traffic monitor for Dusky Petrel.
; Prints one game per minute, refetching the lobby each time, then wraps around.
; Run from the monitor with: asm lobbymon.asm, then go START
; Each line is: HH:MM (UTC)  game  servers N  players P/M
; Stop with Ctrl-C. Handles up to 9999 lobby entries.
; Numbers in this file are octal unless marked otherwise.
        ORG 0o0

; Subroutine vectors, so calls can reach across the program.
FETCHV:   DW FETCH
QUERYV:   DW QUERY
SAVEV:    DW SAVE
SAMEV:    DW SAME
NUMV:     DW NUMBER
DECV:     DW DEC
PAD2V:    DW PAD2
PRINTV:   DW PRINT
PUTV:     DW PUTCH
REPORTV:  DW REPORT
WAITV:    DW WAITMIN
SLOWP:    DW 0o77760

; Cells used with @ must stay below 0o20: 0o20-0o37 auto-index on indirect reads.
; Output vector used by DEC: PUTCH for the console, PUTJSP to build a query.
OUTP:     DW PUTCH
CONOUT:   DW PUTCH
JSPOUT:   DW PUTJSP

; Pointers
URLPTR:   DW URL
FGAME:    DW F_GAME
FCUR:     DW F_CUR
FMAX:     DW F_MAX
NAMEPTR:  DW NAME
PWRPTR:   DW POWERS
S_SRV:    DW T_SRV
S_PLR:    DW T_PLR
S_NONE:   DW T_NONE

; Constants
ZERO:     DW 0
ONE:      DW 1
TWO:      DW 2
TEN:      DW 0o12
SIXTY:    DW 0o74
WIDTH:    DW 0o22
DIG0:     DW 0o060
SLASH:    DW 0o057
COLON:    DW 0o072
BLANK:    DW 0o040
CR:       DW 0o015
LF:       DW 0o012
WEBCTRL:  DW 0
JSPCTRL:  DW 1

; State
CURSOR:   DW 0
INDEX:    DW 0
COUNT:    DW 0
NLEN:     DW 0
MATCH:    DW 0
SERVERS:  DW 0
PLAYERS:  DW 0
SLOTS:    DW 0
LASTMIN:  DW 0
HOURS:    DW 0
MINS:     DW 0

; Subroutine work cells
D_VAL:    DW 0
D_CH:     DW 0
D_ANY:    DW 0
N_VAL:    DW 0
N_TMP:    DW 0
Q_FLD:    DW 0

        ORG 0o200

START:  DIA AC0, 0o21
        STA AC0, LASTMIN
        JSR @FETCHV

; Read the game at CURSOR. An empty value means we passed the end of the list.
        LDA AC0, CURSOR
        STA AC0, INDEX
        LDA AC1, FGAME
        JSR @QUERYV
        LDA AC0, COUNT
        MOV AC0, AC0, SZR
        JMP HAVE

        LDA AC0, ZERO
        STA AC0, CURSOR
        STA AC0, INDEX
        LDA AC1, FGAME
        JSR @QUERYV
        LDA AC0, COUNT
        MOV AC0, AC0, SZR
        JMP HAVE

; Still empty: the lobby gave no usable reply.
        STA AC0, NLEN
        JSR @REPORTV
        JMP IDLE

HAVE:   JSR @SAVEV
        LDA AC0, ZERO
        STA AC0, SERVERS
        STA AC0, PLAYERS
        STA AC0, SLOTS

; Add up the run of entries that share this game name.
SUM:    LDA AC1, FCUR
        JSR @QUERYV
        JSR @NUMV
        LDA AC1, PLAYERS
        ADDZ AC1, AC0
        STA AC0, PLAYERS
        LDA AC1, FMAX
        JSR @QUERYV
        JSR @NUMV
        LDA AC1, SLOTS
        ADDZ AC1, AC0
        STA AC0, SLOTS
        LDA AC0, SERVERS
        INC AC0, AC0
        STA AC0, SERVERS
        LDA AC0, INDEX
        INC AC0, AC0
        STA AC0, INDEX
        LDA AC1, FGAME
        JSR @QUERYV
        JSR @SAMEV
        LDA AC0, MATCH
        MOV AC0, AC0, SNR
        JMP SUMMED
        JMP SUM

SUMMED: LDA AC0, INDEX
        STA AC0, CURSOR
        JSR @REPORTV

IDLE:   JSR @WAITV
        JMP START

; Waits for the RTC minute to change. Slow memory pauses 100 ms per read.
WAITMIN:
        STA AC3, W_RET
W_LOOP: LDA AC0, @SLOWP
        DIA AC0, 0o21
        LDA AC1, LASTMIN
        SUBZ AC1, AC0
        MOV AC0, AC0, SNR
        JMP W_LOOP
        JMP @W_RET
W_RET:  DW 0

; Fetches the full lobby list. JSON parsing happens on the emulator's host.
FETCH:  STA AC3, F_RET
        NIOC AC0, WEB
        LDA AC2, URLPTR
F_LOOP: LDA AC0, 0,AC2
        MOV AC0, AC0, SNR
        JMP F_GO
        DOA AC0, WEB
        INC AC2, AC2
        JMP F_LOOP
F_GO:   LDA AC0, WEBCTRL
        DOC AC0, WEB
        NIOS AC0, WEB
F_WAIT: SKPDN WEB
        JMP F_WAIT
        JMP @F_RET
F_RET:  DW 0

; AC1 = pointer to field name. Queries /<INDEX>/<field>, sets COUNT to the length.
QUERY:  STA AC3, Q_RET
        STA AC1, Q_FLD
        NIOC AC0, JSP
        LDA AC0, SLASH
        DOA AC0, JSP
        LDA AC0, JSPOUT
        STA AC0, OUTP
        LDA AC0, INDEX
        JSR @DECV
        LDA AC0, CONOUT
        STA AC0, OUTP
        LDA AC0, SLASH
        DOA AC0, JSP
        LDA AC2, Q_FLD
Q_STR:  LDA AC0, 0,AC2
        MOV AC0, AC0, SNR
        JMP Q_GO
        DOA AC0, JSP
        INC AC2, AC2
        JMP Q_STR
Q_GO:   LDA AC0, JSPCTRL
        DOC AC0, JSP
        NIOS AC0, JSP
Q_WAIT: SKPDN JSP
        JMP Q_WAIT
        LDA AC0, TWO
        DOB AC0, JSP
        DIC AC0, JSP
        STA AC0, COUNT
        JMP @Q_RET
Q_RET:  DW 0

; Stores the current JSP value in NAME and its length in NLEN.
SAVE:   STA AC3, V_RET
        LDA AC1, COUNT
        STA AC1, NLEN
        LDA AC2, NAMEPTR
V_LOOP: DIA AC0, JSP
        STA AC0, 0,AC2
        INC AC2, AC2
        LDA AC0, ONE
        SUBZ AC0, AC1
        MOV AC1, AC1, SNR
        JMP @V_RET
        JMP V_LOOP
V_RET:  DW 0

; Sets MATCH to 1 if the current JSP value equals NAME, otherwise 0.
SAME:   STA AC3, M_RET
        LDA AC0, ZERO
        STA AC0, MATCH
        LDA AC1, COUNT
        MOV AC1, AC1, SNR
        JMP @M_RET
        LDA AC0, NLEN
        SUBZ AC1, AC0
        MOV AC0, AC0, SZR
        JMP @M_RET
        LDA AC2, NAMEPTR
M_LOOP: DIA AC0, JSP
        LDA AC3, 0,AC2
        SUBZ AC3, AC0
        MOV AC0, AC0, SZR
        JMP @M_RET
        INC AC2, AC2
        LDA AC0, ONE
        SUBZ AC0, AC1
        MOV AC1, AC1, SZR
        JMP M_LOOP
        LDA AC0, ONE
        STA AC0, MATCH
        JMP @M_RET
M_RET:  DW 0

; Reads the current JSP value as a decimal number into AC0. Empty reads as 0.
NUMBER: STA AC3, N_RET
        LDA AC0, ZERO
        STA AC0, N_VAL
        LDA AC1, COUNT
        MOV AC1, AC1, SNR
        JMP N_DONE
N_LOOP: LDA AC0, N_VAL
        MOVZL AC0, AC0
        STA AC0, N_TMP
        MOVZL AC0, AC0
        MOVZL AC0, AC0
        LDA AC2, N_TMP
        ADDZ AC2, AC0
        STA AC0, N_VAL
        DIA AC0, JSP
        LDA AC2, DIG0
        SUBZ AC2, AC0
        LDA AC2, N_VAL
        ADDZ AC2, AC0
        STA AC0, N_VAL
        LDA AC2, ONE
        SUBZ AC2, AC1
        MOV AC1, AC1, SZR
        JMP N_LOOP
N_DONE: LDA AC0, N_VAL
        JMP @N_RET
N_RET:  DW 0

; Prints AC0 in decimal through OUTP, with no leading zeros.
DEC:    STA AC3, D_RET
        STA AC0, D_VAL
        LDA AC0, ZERO
        STA AC0, D_ANY
        LDA AC2, PWRPTR
D_POW:  LDA AC1, 0,AC2
        MOV AC1, AC1, SNR
        JMP @D_RET
        LDA AC0, DIG0
        STA AC0, D_CH
D_SUB:  LDA AC0, D_VAL
        SUBZ AC1, AC0
        MOVZL AC0, AC3, SNC
        JMP D_KEEP
        JMP D_EMIT
D_KEEP: STA AC0, D_VAL
        LDA AC0, D_CH
        INC AC0, AC0
        STA AC0, D_CH
        JMP D_SUB
D_EMIT: LDA AC0, D_CH
        LDA AC3, D_ANY
        MOV AC3, AC3, SZR
        JMP D_PUT
        LDA AC3, DIG0
        SUBZ AC0, AC3
        MOV AC3, AC3, SZR
        JMP D_PUT
        LDA AC3, ONE
        SUBZ AC1, AC3
        MOV AC3, AC3, SNR
        JMP D_PUT
        JMP D_NEXT
D_PUT:  JSR @OUTP
        LDA AC0, ONE
        STA AC0, D_ANY
D_NEXT: INC AC2, AC2
        JMP D_POW
D_RET:  DW 0

; Prints AC0 in decimal with at least two digits.
PAD2:   STA AC3, P_RET
        STA AC0, P_VAL
        LDA AC1, TEN
        SUBZ AC1, AC0
        MOVZL AC0, AC3, SNC
        JMP P_OUT
        LDA AC0, DIG0
        JSR @PUTV
P_OUT:  LDA AC0, P_VAL
        JSR @DECV
        JMP @P_RET
P_RET:  DW 0
P_VAL:  DW 0

; Prints one line for the current game, or a no-reply line if NLEN is zero.
REPORT: STA AC3, R_RET
        LDA AC0, ZERO
        STA AC0, HOURS
        DIA AC0, 0o21
R_DIV:  STA AC0, MINS
        LDA AC1, SIXTY
        SUBZ AC1, AC0
        MOVZL AC0, AC3, SNC
        JMP R_HOUR
        JMP R_TIME
R_HOUR: LDA AC1, HOURS
        INC AC1, AC1
        STA AC1, HOURS
        JMP R_DIV
R_TIME: LDA AC0, HOURS
        JSR @PAD2V
        LDA AC0, COLON
        JSR @PUTV
        LDA AC0, MINS
        JSR @PAD2V
        LDA AC0, BLANK
        JSR @PUTV
        LDA AC0, BLANK
        JSR @PUTV
        LDA AC1, NLEN
        MOV AC1, AC1, SZR
        JMP R_NAME
        LDA AC2, S_NONE
        JSR @PRINTV
        JMP R_END

R_NAME: LDA AC2, NAMEPTR
R_CHR:  LDA AC0, 0,AC2
        JSR @PUTV
        INC AC2, AC2
        LDA AC0, ONE
        SUBZ AC0, AC1
        MOV AC1, AC1, SZR
        JMP R_CHR
        LDA AC1, WIDTH
        LDA AC0, NLEN
        SUBZ AC0, AC1
R_PAD:  LDA AC0, BLANK
        JSR @PUTV
        LDA AC0, ONE
        SUBZ AC0, AC1
        MOV AC1, AC1, SZR
        JMP R_PAD
        LDA AC2, S_SRV
        JSR @PRINTV
        LDA AC0, SERVERS
        JSR @DECV
        LDA AC2, S_PLR
        JSR @PRINTV
        LDA AC0, PLAYERS
        JSR @DECV
        LDA AC0, SLASH
        JSR @PUTV
        LDA AC0, SLOTS
        JSR @DECV

R_END:  LDA AC0, CR
        JSR @PUTV
        LDA AC0, LF
        JSR @PUTV
        JMP @R_RET
R_RET:  DW 0

; AC2 = pointer to zero-terminated string
PRINT:  STA AC3, S_RET
S_LOOP: LDA AC0, 0,AC2
        MOV AC0, AC0, SNR
        JMP @S_RET
        JSR @PUTV
        INC AC2, AC2
        JMP S_LOOP
S_RET:  DW 0

; Character outputs. Both keep AC1 and AC2.
PUTJSP: DOA AC0, JSP
        JMP 0,AC3

PUTCH:
        NIOC AC0, UTTO
        DOAS AC0, UTTO
PT_WAIT:
        SKPDN UTTO
        JMP PT_WAIT
        JMP 0,AC3

        ORG 0o2000

URL:    .TXT "http://fujinet.online:8080/viewFull"
        DW 0
F_GAME: .TXT "game"
        DW 0
F_CUR:  .TXT "curplayers"
        DW 0
F_MAX:  .TXT "maxplayers"
        DW 0
T_SRV:  .TXT "servers "
        DW 0
T_PLR:  .TXT "  players "
        DW 0
T_NONE: .TXT "no reply from lobby"
        DW 0
POWERS: DW 0o1750
        DW 0o144
        DW 0o12
        DW 1
        DW 0
NAME:   DW 0

