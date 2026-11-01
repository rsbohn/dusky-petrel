# CVIT friction log

Things that bit us while bringing CVIT up on the Nova. Each entry records
the symptom, the hunt, the fix, and the lesson — so the next person
(possibly future us) doesn't pay twice.

## 2026-10-31 — TYOUT sent text down the binary path (SZR vs SNR)

**Symptom.** `TYPE HELLO` printed the file, but every line started where
the previous one ended:

```
]TYPE HELLO
Hello from CVIT/Nova!
                     This is a sample text file.
                                                ]
```

"Hello from CVIT/Nova!" is 21 characters; the next line was indented
exactly 21 spaces; the `]` prompt 48 (21 + 27). Textbook LF-without-CR:
the terminal moved down a line but the carriage never returned to
column 0.

**The hunt.** The file (`hello.txt`, LF line endings, stored as
`TYPE_TXT = 1`) should have gone through `TYOTXT`, which already
translated LF to CR+LF (`TYOTLF`). But the dispatch at the top of
`TYOUT` read:

```
        LDA AC0, TYTYPE
        LDA AC1, ONE
        SUB AC1, AC0       ; AC0 = type - 1
        MOV AC0, AC0, SZR  ; skip next if AC0 == 0
        JMP TYOTXT
        ; Binary: 2 chars per word
TYOBIN: ...
```

With `SZR`, a text file (type 1, so AC0 = 0 after the subtract) *skips*
the jump to `TYOTXT` and falls straight into `TYOBIN` — the raw binary
path, which emits bytes with no newline translation (and NUL-pads every
byte, invisible on the terminal, which is why the text itself looked
fine). Binary files took the text path. Exactly backwards.

**Fix.** One word, in both copies (`sd/cvit-command.asm`,
`simh/cvit-command-simh.asm`):

```
-        MOV AC0, AC0, SZR
+        MOV AC0, AC0, SNR
```

With `SNR` (skip if nonzero): type 1 leaves AC0 = 0, no skip, `JMP
TYOTXT`; type 2 leaves AC0 = 1, skip, fall into `TYOBIN`. Rebuild and
run `scripts/test-cvit-simh.sh` to confirm — `TYPE HELLO` should land
each line at column 0.

**Lesson.** This is the second inverted-branch bug in COMMAND in as many
days. The first was the swapped `JMP TYNEXT` / `JMP TYFOUND` pair after
the `TYCMP` call (2026-10-30), which made the directory scan "find" the
first *non*-matching entry. The Nova skip idiom (`SUB`/`MOV` +
`SZR`/`SNR` + `JMP`) reads plausibly in either direction: both versions
assemble, both look right, and only a live test tells them apart. When
writing a skip-branch, annotate the intended mapping in a comment (e.g.
`; type==TXT -> TYOTXT`) and exercise both sides of the branch on the
hardware (or SIMH) before moving on.

## 2026-10-31 — PTYP's uppercase never ran (third SZR/SNR inversion)

**Symptom.** Making COMMAND case-insensitive exposed it: the uppercase
block in PTYP (which uppercases `TYPE` filenames) could never execute.
Lowercase filenames silently failed to match.

**The hunt.** The HIMASK range check used `SNR` where it needed `SZR`:
with `SNR`, a lowercase char like 'm' (`char-'a'` positive, sign bit
clear, masked to 0) does *not* skip, so the "not lowercase" jump is taken
and the uppercase never happens. The guard only falls through when
`char < 'a'` — exactly backwards. For the uppercase to run, `char` would
have to be both `< 'a'` and `> 'z'`: impossible. Dead code since written;
invisible because everyone typed uppercase names.

**Fix.** `SNR` → `SZR` in both guards, in PTYP and in the new UPVERB
(which had copied the bug verbatim). Now `AC1 == 0` means `char >= 'a'`,
skip the jump, continue; `AC1 != 0` means `char < 'a'`, take the jump.

**Lesson.** Third inverted skip in COMMAND in two days (TYNEXT/TYFOUND
swap, TYOUT SZR/SNR, now PTYP SNR/SZR). The pattern is always the same:
both directions assemble and the wrong one looks right. When a skip-guard
is meant to *continue* on a condition, trace one in-range and one
out-of-range value through it before moving on.
