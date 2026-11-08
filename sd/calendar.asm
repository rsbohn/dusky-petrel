; Print a fixed November 2026 calendar.
; Standalone Nova program: assemble at 0o2000 and run on SIMH or Dusky.
; November 1, 2026 is Sunday. This intentionally uses no RTC.
; Under CVIT, RUN CALENDAR returns to COMMAND through the kernel warm
; start vector (0o1001).

        ORG     0o2000

START:  LDA     AC2, TEXTADR
NEXT:   LDA     AC0, 0,AC2
        MOV     AC0, AC0, SZR
        JMP     OUTPUT
        JMP     @WARMP
OUTPUT: SKPBZ   TTO
        JMP     OUTPUT
        DOAS    AC0, TTO
        INC     AC2, AC2
        JMP     NEXT

TEXTADR: DW      TEXT
WARMP:   DW      0o1001
TEXT:
        DW      0o40, 0o40, 0o40, 0o40, 0o40, 0o40, 0o116, 0o157
        DW      0o166, 0o145, 0o155, 0o142, 0o145, 0o162, 0o40, 0o62
        DW      0o60, 0o62, 0o66, 0o15, 0o12, 0o123, 0o165, 0o40
        DW      0o40, 0o115, 0o157, 0o40, 0o40, 0o124, 0o165, 0o40
        DW      0o40, 0o127, 0o145, 0o40, 0o40, 0o124, 0o150, 0o40
        DW      0o40, 0o106, 0o162, 0o40, 0o40, 0o123, 0o141, 0o15
        DW      0o12, 0o40, 0o61, 0o40, 0o40, 0o40, 0o62, 0o40
        DW      0o40, 0o40, 0o63, 0o40, 0o40, 0o40, 0o64, 0o40
        DW      0o40, 0o40, 0o65, 0o40, 0o40, 0o40, 0o66, 0o40
        DW      0o40, 0o40, 0o67, 0o15, 0o12, 0o40, 0o70, 0o40
        DW      0o40, 0o40, 0o71, 0o40, 0o40, 0o61, 0o60, 0o40
        DW      0o40, 0o61, 0o61, 0o40, 0o40, 0o61, 0o62, 0o40
        DW      0o40, 0o61, 0o63, 0o40, 0o40, 0o61, 0o64, 0o15
        DW      0o12, 0o61, 0o65, 0o40, 0o40, 0o61, 0o66, 0o40
        DW      0o40, 0o61, 0o67, 0o40, 0o40, 0o61, 0o70, 0o40
        DW      0o40, 0o61, 0o71, 0o40, 0o40, 0o62, 0o60, 0o40
        DW      0o40, 0o62, 0o61, 0o15, 0o12, 0o62, 0o62, 0o40
        DW      0o40, 0o62, 0o63, 0o40, 0o40, 0o62, 0o64, 0o40
        DW      0o40, 0o62, 0o65, 0o40, 0o40, 0o62, 0o66, 0o40
        DW      0o40, 0o62, 0o67, 0o40, 0o40, 0o62, 0o70, 0o15
        DW      0o12, 0o62, 0o71, 0o40, 0o40, 0o63, 0o60, 0o15
        DW      0o12, 0o0
