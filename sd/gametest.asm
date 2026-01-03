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

        ORG 0o100

START:
        ; Get random block using RTC (device 0o21)
        ; DIB returns epoch seconds (low word) - changes every second
        DIB 0, 0o21        ; Read epoch seconds (low) into AC0
        LDA 1, MASK77
        AND 1, 0           ; Mask to 0-63 range
        STA 0, RNDBLK      ; Save block number
        
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
        
        ; Print the location name from buffer (memory 0o1000)
        LDA 2, BUFBASE
        JSR PRTSTR
        
        ; Print newline
        LDA 0, NEWLINE
        DOA 0, TTO
        
        ; Done - halt
        HALT

ERROR:
        ; Print error message
        ; Need to load ADDRESS of ERRMSG, not content
        LDA 2, ERRADR
        JSR PRTSTR
        HALT

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
BUFBASE:  DW 0o1000
MASK77:   DW 0o77
LOMASK:   DW 0o377
NEWLINE:  DW 0o012
RDCMD:    DW 0o2          ; TC08 control: read (bit 1)
ERRMASK:  DW 0o4          ; TC08 status: error (bit 2)
RETADR:   DW 0
TMPWORD:  DW 0

; Error message "TC08 ERROR: Tape not attached?\n"
ERRADR:   DW ERRMSG       ; Address of error message
ERRMSG:   DW 0o052103, 0o030070, 0o020105, 0o051122, 0o047522, 0o035040
          DW 0o052141, 0o070145, 0o020156, 0o067564, 0o020141, 0o072164
          DW 0o060543, 0o064145, 0o062077, 0o005000, 0
