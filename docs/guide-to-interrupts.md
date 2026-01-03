# Guide to Interrupts (Nova Emulator)

This emulator models the Nova interrupt mechanism as described for the 1210-era hardware. The design is intentionally simple: a single interrupt request line shared by all devices, and a daisy-chain acknowledge used to identify the highest-priority requester.

## Core Behavior

- Single interrupt request line: devices assert a pending interrupt when they are done.
- The CPU services an interrupt after finishing the current instruction.
- Interrupts are disabled on entry to the handler.
- The return address is stored in memory location `000000`.
- The interrupt vector is an indirect jump through memory location `000001`.

### Interrupt Entry Sequence

When an interrupt is taken:

1) The CPU writes the current PC to memory `000000`.
2) The CPU loads the new PC from memory `@000001` (indirect jump).
3) Interrupts are disabled until re-enabled by `INTEN`.

## INTEN / INTDS / INTA

- `INTEN` enables interrupts **after a one-instruction delay**. This allows the classic return sequence:

```
INTEN
JMP @0
```

The CPU will not accept a new interrupt until after the `JMP @0` completes.

- `INTDS` disables interrupts immediately and cancels any pending INTEN delay.
- `INTA` returns the device code (channel) of the highest-priority pending interrupt.

## Interrupt Priority (Daisy Chain)

The acknowledge signal is modeled using device registration order. If multiple devices request interrupts, `INTA` returns the first registered device that is pending. This matches the “closest to the CPU” priority used in the real backplane daisy chain.

## Clearing Interrupt Requests

By convention, the interrupting device clears its request when the CPU issues an I/O clear to that device’s channel. In this emulator, any `NIO` with the Clear signal for a device will clear its pending interrupt.

Example (watchdog device is `0o70`):

```
NIOC AC0, 0o70
```

## Minimal ISR Skeleton

A minimal interrupt service routine (ISR) typically:

1) Saves the registers it will modify.
2) Executes `INTA` to discover the device.
3) Clears the device’s interrupt request with `NIOC`.
4) Restores registers.
5) Executes `INTEN` followed by `JMP @0`.

```
ISR:
    STA 0, SAV0
    STA 1, SAV1
    INTA 1
    NIOC AC0, 0o70
    LDA 1, SAV1
    LDA 0, SAV0
    INTEN
    JMP @0
```

## Notes

- The emulator currently exposes interrupts from the watchdog device. Other devices can be wired to request interrupts as needed.
- Use `INTDS` if you want to mask interrupts while performing critical work.
