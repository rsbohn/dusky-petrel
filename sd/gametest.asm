; Game location demo - Display place names from TU56 tape
; 
; This program demonstrates reading location names from the game tape.
; Each of the 64 blocks contains a place name in the first 64 words.
;
; Usage:
;   1. Attach tape: tc0 attach game.tu56
;   2. Assemble:    asm sd/gametest.asm 100
;   3. Run:         go 100
;
; The program uses the RTC to select a random block (0-63), loads it
; from TC08 device 0o20 (TC0), and prints the zero-terminated ASCII
; string (2 chars per word, high byte first).

        ORG 0o77
HERE:   DW 0

        ORG 0o100

START:
        LDA 0, EPINIT
        STA 0, EPCNT
EPLOOP:
        ; Get random block using RTC (device 0o21)
        ; DIB returns epoch seconds (low word) - changes every second
        DIB 0, 0o21        ; Read epoch seconds (low) into AC0
        LDA 1, HERE
        ADD 1, 0           ; AC0 = seconds + HERE
        LDA 1, MASK77
        AND 1, 0           ; Mask to 0-63 range
        STA 0, HERE        ; Save current block
        STA 0, RNDBLK      ; Save block number

        ; Log: Seeking block [n]
        LDA 2, SEEKMSG
        JSR PRTSTR
        LDA 0, RNDBLK
        JSR PUTNUM2
        LDA 0, NEWLINE
        DOA 0, TTO
        
        ; Read the block from tape using TC08 device (0o20)
        ; TC08 protocol:
        ;   DOA = set transfer address
        ;   DOB = set block number
        ;   DOC = set control (bit 0=drive, bit 1=read, bit 2=write)
        ;   NIOS = start transfer
        ;   SKPDN = skip if done
        
        LDA 0, BUFBASE     ; Transfer address
        DOA 0, 0o20        ; Set address in TC08
        
        LDA 0, RNDBLK      ; Block number
        DOB 0, 0o20        ; Set block in TC08
        
        LDA 0, RDCMD       ; Control: drive 0, read
        DOC 0, 0o20        ; Set control in TC08
        
        NIOS 0, 0o20       ; Start I/O
        
WAIT:   SKPDN 0o20         ; Skip if done
        JMP WAIT           ; Wait for completion
        
        ; Check for error (bit 2 of status)
        DIC 0, 0o20        ; Read status
        LDA 1, ERRMASK     ; Error bit mask
        AND 1, 0           ; Test error bit
        MOV 0, 0, SZR      ; Skip if zero (no error)
        JMP ERROR          ; Jump to error handler
        
        ; Print visit log line
        LDA 2, VISITMSG
        JSR PRTSTR
        LDA 2, BUFBASE
        JSR PRTSTR
        
        ; Print newline
        LDA 0, NEWLINE
        DOA 0, TTO

        ; Print a random observation
        JSR PRTOBS
        LDA 0, NEWLINE
        DOA 0, TTO
        LDA 0, NEWLINE
        DOA 0, TTO
        
        DSZ EPCNT
        JMP EPLOOP
        ; Done - halt
        HALT

ERROR:
        ; Print error message
        ; Need to load ADDRESS of ERRMSG, not content
        LDA 2, ERRADR
        JSR PRTSTR
        HALT

RADD:	DW 0
PIP:	DW 0
; Print zero terminated 1 char per word string via AC2
; Destroys AC0, AC1
PUTSZ:	STA 3, RADD
PSZ1:	LDA 0, 0,2         ; Load next character
	STA 0, PIP          ; Save for output
	MOV 0, 0, SZR       ; Test for zero terminator
	JMP PSZOUT
	JMP @RADD

PSZOUT:	LDA 0, PIP
	DOA 0, TTO          ; Output character
	INC 2, 2            ; Advance pointer
	JMP PSZ1
	JMP @RADD

; Print decimal 00-63 from AC0
; Destroys AC0, AC1, AC2
PUTNUM2:
        STA 3, NUMRET
        LDA 2, DEC2PTR
        ADD 0, 2
        LDA 0, 0,2
        STA 0, TMPWORD
        MOVZR 0, 0
        MOVZR 0, 0
        MOVZR 0, 0
        MOVZR 0, 0
        MOVZR 0, 0
        MOVZR 0, 0
        MOVZR 0, 0
        MOVZR 0, 0
        DOA 0, TTO
        LDA 0, TMPWORD
        LDA 1, LOMASK
        AND 1, 0
        DOA 0, TTO
        JMP @NUMRET
NUMRET: DW 0

; Print one of three observations (random-ish)
; Destroys AC0, AC1, AC2
PRTOBS:
        STA 3, OBSRET
        LDA 0, RNDBLK
        LDA 1, MASK3
        AND 1, 0
        STA 0, OBSSEL
        LDA 0, OBSSEL
        LDA 1, THREE
        SUBZ 1, 0
        MOV 0, 0, SZR
        JMP OBSOK
        LDA 0, ZERO
        STA 0, OBSSEL
OBSOK:  LDA 0, OBSSEL
        LDA 2, OBSTABPTR
        ADD 0, 2
        LDA 2, 0,2
        JSR PRTSTR
        JMP @OBSRET
OBSRET: DW 0

; Print string pointed to by AC2 (zero-terminated, 2 chars per word)
; Destroys AC0, AC1
PRTSTR:
        STA 3, RETADR      ; Save return address
PS1:    LDA 0, 0,2         ; Get word from string
        MOV 0, 0, SZR      ; Test for zero, skip if zero
        JMP PSWORD         ; Not zero, print it
        JMP @RETADR        ; Zero, return
        
PSWORD: STA 0, TMPWORD     ; Save word
        MOVZR 0, 0         ; Shift right 8 bits
        MOVZR 0, 0
        MOVZR 0, 0
        MOVZR 0, 0
        MOVZR 0, 0
        MOVZR 0, 0
        MOVZR 0, 0
        MOVZR 0, 0
        MOV 0, 0, SZR      ; Test if zero, skip if zero
        DOA 0, TTO         ; Output high byte (skipped if zero)
        
        LDA 0, TMPWORD     ; Get word again
        LDA 1, LOMASK
        AND 1, 0           ; AC0 = LOMASK & word (get low byte)
        MOV 0, 0, SZR      ; Test if zero, skip if zero
        DOA 0, TTO         ; Output low byte (skipped if zero)
        
        INC 2, 2           ; Increment pointer (AC2 = AC2 + 1)
        JMP PS1            ; Next word

; Data
RNDBLK:   DW 0
EPINIT:   DW 5
EPCNT:    DW 0
BUFBASE:  DW 0o1000
MASK77:   DW 0o77
MASK3:    DW 0o3
THREE:    DW 3
ZERO:     DW 0
LOMASK:   DW 0o377
NEWLINE:  DW 0o012
RDCMD:    DW 0o2          ; TC08 control: read (bit 1)
ERRMASK:  DW 0o4          ; TC08 status: error (bit 2)
RETADR:   DW 0
TMPWORD:  DW 0
OBSSEL:   DW 0
SEEKMSG:  DW SEEKMSG_STR
VISITMSG: DW VISITMSG_STR
OBSTAB:   DW OBSDULL_STR, OBSBIRD_STR, OBSATK_STR
OBSTABPTR: DW OBSTAB
DEC2PTR:  DW DEC2TAB
ERRADR:   DW ERRMSG       ; Address of error message

        ORG 0o400

SEEKMSG_STR:
          DW 0o051545, 0o062553, 0o064556, 0o063440, 0o061154, 0o067543, 0o065440, 0
VISITMSG_STR:
          DW 0o053545, 0o020166, 0o064563, 0o064564, 0o062544, 0o020000, 0
OBSDULL_STR:
          DW 0o052150, 0o064556, 0o063563, 0o020167, 0o062562, 0o062440, 0o062165, 0o066154, 0o027000, 0
OBSBIRD_STR:
          DW 0o053545, 0o020163, 0o060566, 0o062544, 0o020141, 0o020142, 0o064562, 0o062056, 0
OBSATK_STR:
          DW 0o053545, 0o020167, 0o062562, 0o062440, 0o060564, 0o072141, 0o061553, 0o062544, 0o020142, 0o074440, 0o072150, 0o062440, 0o066157, 0o061541, 0o066163, 0o027000, 0

DEC2TAB:
          DW 0o030060, 0o030061, 0o030062, 0o030063, 0o030064, 0o030065, 0o030066, 0o030067
          DW 0o030070, 0o030071, 0o030460, 0o030461, 0o030462, 0o030463, 0o030464, 0o030465
          DW 0o030466, 0o030467, 0o030470, 0o030471, 0o031060, 0o031061, 0o031062, 0o031063
          DW 0o031064, 0o031065, 0o031066, 0o031067, 0o031070, 0o031071, 0o031460, 0o031461
          DW 0o031462, 0o031463, 0o031464, 0o031465, 0o031466, 0o031467, 0o031470, 0o031471
          DW 0o032060, 0o032061, 0o032062, 0o032063, 0o032064, 0o032065, 0o032066, 0o032067
          DW 0o032070, 0o032071, 0o032460, 0o032461, 0o032462, 0o032463, 0o032464, 0o032465
          DW 0o032466, 0o032467, 0o032470, 0o032471, 0o033060, 0o033061, 0o033062, 0o033063

; Error message "TC08 ERROR: Tape not attached?\n"
ERRMSG:
          DW 0o052103, 0o030070, 0o020105, 0o051122, 0o047522, 0o035040
          DW 0o052141, 0o070145, 0o020156, 0o067564, 0o020141, 0o072164
          DW 0o060543, 0o064145, 0o062077, 0o005000, 0
