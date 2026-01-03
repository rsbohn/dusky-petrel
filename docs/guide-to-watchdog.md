# Guide to the Watchdog Device

The emulator includes a watchdog timer device (WDT) at device code `0o70` (decimal 56). It is a host-backed timer that can interrupt, halt, or reset the CPU when it expires.

## Enabling the Device

The watchdog is disabled at the host level by default. You must enable it in the monitor before I/O will work:

```
wdt host on
```

If host enable is off, all watchdog I/O operations are ignored.

## Basic I/O Model

The watchdog uses standard Nova I/O operations:

- `DOA` sets the timeout in milliseconds.
- `DOB` writes the control word (enable, repeat, action, pet, clear fired).
- `DIA` reads back the timeout in milliseconds.
- `DIB` reads the control word.
- `DIC` reads the status word.
- `NIO` with `Start` arms the timer.
- `NIO` with `Clear` clears the active/fired state.
- `NIO` with `Pulse` forces an immediate fire.

## Control Word (DOB)

The control word bit layout is:

- Bit 0: Enable (1 = enable, 0 = disable)
- Bit 1: Repeat (1 = auto-rearm after firing)
- Bits 2-3: Action
  - `0` = None
  - `1` = Interrupt
  - `2` = Halt
  - `3` = Reset
- Bit 4: Pet (re-arm now if enabled)
- Bit 5: Clear fired

Example: one-shot interrupt with pet+clear fired set is `0o65`.

## Status Word (DIC)

The status word bit layout is:

- Bit 0: Fired
- Bit 1: Active
- Bit 2: Repeat
- Bits 3-4: Action (same encoding as control word)

## Typical Sequence

A common pattern to arm the watchdog for a one-shot interrupt:

```
NIOC AC0, 0o70        ; clear active/fired
LDA  AC0, TIMEOUT_MS
DOA  AC0, 0o70        ; set timeout
LDA  AC0, CTRL
DOB  AC0, 0o70        ; enable + action + pet + clear fired
NIOS AC0, 0o70        ; start (arm)
```

Where `CTRL` would be `0o65` for a one-shot interrupt (enable + interrupt + pet + clear fired).

## Action Behavior

- Interrupt: requests a CPU interrupt on device `0o70`.
- Halt: halts the CPU with reason "Watchdog".
- Reset: resets the CPU.

## Notes

- The watchdog uses a host timer. It does not advance in step-mode unless time elapses on the host.
- A device clear (`NIOC`) also clears the fired state.
