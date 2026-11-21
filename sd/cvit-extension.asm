; CVIT resident extension, loaded at 0o65000 by the disk bootstrap.
; Initial entry is a probe: returns 0o12345 in AC0, preserving AC3.
        ORG 0o65000
EXT_PROBE: LDA 0, SIGNATURE
        JMP 0,3
SIGNATURE: DW 0o12345
