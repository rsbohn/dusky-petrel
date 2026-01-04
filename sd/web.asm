        ORG 0o200

START:  NIOC AC0, WEB     ; clear device state
        LDA AC1, URLPTR
        STA AC1, MPTR

SEND:   LDA AC0, @MPTR
        MOV AC0, AC0, SNR
        JMP CONFIG
        DOA AC0, WEB
        LDA AC1, MPTR
        LDA AC2, ONE
        ADDZ AC2, AC1
        STA AC1, MPTR
        JMP SEND

CONFIG: LDA AC0, CTRL
        DOC AC0, WEB
        NIOS AC0, WEB     ; REFRESH

WAIT:   SKPDN WEB         ; wait for DONE
        JMP WAIT

        LDA AC0, ZERO
        DOB AC0, WEB
        DIC AC0, WEB
        STA AC0, STATUS

        LDA AC1, COUNT
READ:   DIA AC0, WEB
        DOA AC0, UTTO
        LDA AC2, ONE
        SUBZ AC2, AC1
        MOV AC1, AC1, SNR
        JMP DONE
        JMP READ

DONE:   HALT

MPTR:   DW 0
URLPTR: DW URL
ONE:    DW 1
ZERO:   DW 0
COUNT:  DW 0o200
CTRL:   DW 2            ; MODE=UTF-16, METHOD=GET
STATUS: DW 0

URL0:    .TXT /https:/
        DW 0o057
        DW 0o057
        .TXT /gist.githubusercontent.com/
        DW 0o057
        .TXT /rsbohn/
        DW 0o057
        .TXT /1e3d0312e52aff7400b8fcae6d1986f9/
        DW 0o057
        .TXT /raw/
        DW 0o057
        .TXT /f6dfabe94f844ad1191f9c623c99a0096dcd7723/
        DW 0o057
        .TXT /README.md/
        DW 0
URL:	.TXT "https://fdo.rocketlaunch.live/json/launches/next/1"
	DW 0
