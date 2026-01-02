using System.Collections.ObjectModel;
using System.Threading;

namespace Snova;

/// <summary>
/// Minimal Data General Nova 1210 style CPU emulator. Implements a compact subset of the ISA
/// suitable for experimentation through the bundled monitor.
/// </summary>
public class NovaCpu
{
    public const int WordMask = 0xFFFF;
    public const int AddressMask = 0x7FFF; // 15-bit addressing
    public const int PageMask = 0xFF00;
    public const int OffsetMask = 0x00FF;
    private const ushort SlowMemoryBase = 0x7FF0; // 0o77760
    private const int SlowMemoryCount = 8;
    private const int SlowMemoryDelayMs = 100;

    private readonly ushort[] _memory = new ushort[1 << 15]; // 32K words.

    public ushort[] Accumulators { get; } = new ushort[4];
    public ushort ProgramCounter { get; private set; }
    public bool Link { get; private set; }
    public bool Halted { get; private set; }
    public string? HaltReason { get; private set; }
    public NovaIoBus IoBus { get; } = new();

    public ReadOnlyCollection<ushort> Memory => Array.AsReadOnly(_memory);

    public void Reset(ushort startAddress = 0)
    {
        Array.Fill(Accumulators, (ushort)0);
        Array.Fill(_memory, (ushort)0);
        ProgramCounter = startAddress;
        Link = false;
        Halted = false;
        HaltReason = null;
    }

    public void Halt(string? reason = null)
    {
        Halted = true;
        HaltReason = reason;
    }

    public void Resume()
    {
        Halted = false;
        HaltReason = null;
    }

    public ushort ReadMemory(ushort address)
    {
        var masked = (ushort)(address & AddressMask);
        if (IsSlowMemoryAddress(masked))
        {
            Thread.Sleep(SlowMemoryDelayMs);
        }

        return _memory[masked];
    }

    public void WriteMemory(ushort address, ushort value) => _memory[address & AddressMask] = value;

    private static bool IsSlowMemoryAddress(ushort address)
    {
        return address >= SlowMemoryBase && address < SlowMemoryBase + SlowMemoryCount;
    }

    public void SetProgramCounter(ushort address) => ProgramCounter = (ushort)(address & AddressMask);

    public void RegisterDevice(INovaIoDevice device) => IoBus.RegisterDevice(device);

    public ExecutionStep Step()
    {
        if (Halted)
        {
            var reason = string.IsNullOrWhiteSpace(HaltReason) ? string.Empty : $" ({HaltReason})";
            return new ExecutionStep(ProgramCounter, 0, $"CPU halted{reason}", true, false);
        }

        var instructionAddress = ProgramCounter;
        var instruction = Fetch();
        if (IsIoInstruction(instruction))
        {
            return ExecuteIo(instruction, instructionAddress);
        }

        if ((instruction & 0x8000) != 0)
        {
            return ExecuteOperate(instruction, instructionAddress);
        }

        return ExecuteMrf(instruction, instructionAddress);
    }

    private ushort Fetch()
    {
        var value = ReadMemory(ProgramCounter);
        ProgramCounter = (ushort)((ProgramCounter + 1) & AddressMask);
        return value;
    }

    private ExecutionStep ExecuteIo(ushort instruction, ushort instructionAddress)
    {
        var io = DecodeIo(instruction);
        var description = FormatIoDescription(io);
        var skip = false;
        var tookBranch = false;
        var handled = false;

        ushort accumulatorValue = 0;
        var usesAccumulator = io.Kind is NovaIoOpKind.DIA or NovaIoOpKind.DIB or NovaIoOpKind.DIC
            or NovaIoOpKind.DOA or NovaIoOpKind.DOB or NovaIoOpKind.DOC;
        if (usesAccumulator)
        {
            accumulatorValue = Accumulators[io.Ac];
        }

        if (io.DeviceCode == 63 && io.Kind == NovaIoOpKind.DOC && !io.Start && !io.Clear && !io.Pulse) // 0o77
        {
            Halt("HALT instruction");
            handled = true;
        }
        else
        {
            handled = IoBus.TryExecute(io, ref accumulatorValue, out skip);
        }
        if (handled && usesAccumulator)
        {
            Accumulators[io.Ac] = (ushort)(accumulatorValue & WordMask);
        }

        if (skip)
        {
            ProgramCounter = (ushort)((ProgramCounter + 1) & AddressMask);
            tookBranch = true;
        }

        if (!handled)
        {
            description += " (unassigned)";
        }

        return new ExecutionStep(instructionAddress, instruction, description, Halted, tookBranch)
        {
            AccumulatorIndex = usesAccumulator ? io.Ac : 0,
            Link = Link
        };
    }

    private static bool IsIoInstruction(ushort instruction) => (instruction & 0xE000) == 0x6000;

    private static NovaIoOp DecodeIo(ushort instruction)
    {
        var ac = (instruction >> 11) & 0x3;
        var function = (instruction >> 8) & 0x7;
        var pulse = (instruction >> 6) & 0x3;
        var device = instruction & 0x3F;

        var kind = function switch
        {
            0 => NovaIoOpKind.NIO,
            1 => NovaIoOpKind.DIA,
            2 => NovaIoOpKind.DOA,
            3 => NovaIoOpKind.DIB,
            4 => NovaIoOpKind.DOB,
            5 => NovaIoOpKind.DIC,
            6 => NovaIoOpKind.DOC,
            _ => pulse switch
            {
                0 => NovaIoOpKind.SKPBN,
                1 => NovaIoOpKind.SKPBZ,
                2 => NovaIoOpKind.SKPDN,
                _ => NovaIoOpKind.SKPDZ
            }
        };

        var start = function != 7 && pulse == 1;
        var clear = function != 7 && pulse == 2;
        var sendPulse = function != 7 && pulse == 3;

        return new NovaIoOp(kind, device, ac, start, clear, sendPulse);
    }

    private static string FormatIoDescription(NovaIoOp op)
    {
        var device = Convert.ToString(op.DeviceCode, 8).PadLeft(2, '0');
        return op.Kind switch
        {
            NovaIoOpKind.DIA => $"DIA AC{op.Ac}, {device}",
            NovaIoOpKind.DOA => $"DOA AC{op.Ac}, {device}",
            NovaIoOpKind.DIB => $"DIB AC{op.Ac}, {device}",
            NovaIoOpKind.DOB => $"DOB AC{op.Ac}, {device}",
            NovaIoOpKind.DIC => $"DIC AC{op.Ac}, {device}",
            NovaIoOpKind.DOC => $"DOC AC{op.Ac}, {device}",
            NovaIoOpKind.NIO => $"NIO {FormatSignal(op)}{device}",
            NovaIoOpKind.SKPBN => $"SKPBN {device}",
            NovaIoOpKind.SKPBZ => $"SKPBZ {device}",
            NovaIoOpKind.SKPDN => $"SKPDN {device}",
            NovaIoOpKind.SKPDZ => $"SKPDZ {device}",
            _ => $"IO {device}"
        };
    }

    private static string FormatSignal(NovaIoOp op)
    {
        if (op.Start)
        {
            return "S, ";
        }

        if (op.Clear)
        {
            return "C, ";
        }

        if (op.Pulse)
        {
            return "P, ";
        }

        return string.Empty;
    }

    private ExecutionStep ExecuteMrf(ushort instruction, ushort instructionAddress)
    {
        var opac = (instruction >> 11) & 0x1F;
        var indirect = (instruction & 0x0400) != 0;
        var mode = (instruction >> 8) & 0x3;
        var displacement = instruction & 0xFF;

        var ea = EffectiveAddress(indirect, mode, displacement, instructionAddress);
        var description = string.Empty;
        var tookBranch = false;
        var accumulator = 0;

        switch (opac)
        {
            case 0:
                ProgramCounter = ea;
                tookBranch = true;
                description = $"JMP @{FormatAddress(ea)}";
                break;
            case 1:
                Accumulators[3] = ProgramCounter;
                ProgramCounter = ea;
                tookBranch = true;
                description = $"JMS @{FormatAddress(ea)}";
                break;
            case 2:
                {
                    var value = (ushort)((ReadMemory(ea) + 1) & WordMask);
                    WriteMemory(ea, value);
                    if (value == 0)
                    {
                        ProgramCounter = (ushort)((ProgramCounter + 1) & AddressMask);
                        tookBranch = true;
                    }

                    description = $"ISZ @{FormatAddress(ea)}";
                }
                break;
            case 3:
                {
                    var value = (ushort)((ReadMemory(ea) - 1) & WordMask);
                    WriteMemory(ea, value);
                    if (value == 0)
                    {
                        ProgramCounter = (ushort)((ProgramCounter + 1) & AddressMask);
                        tookBranch = true;
                    }

                    description = $"DSZ @{FormatAddress(ea)}";
                }
                break;
            case 4:
            case 5:
            case 6:
            case 7:
                accumulator = opac & 0x3;
                Accumulators[accumulator] = ReadMemory(ea);
                description = $"LDA AC{accumulator}, @{FormatAddress(ea)}";
                break;
            case 8:
            case 9:
            case 10:
            case 11:
                accumulator = opac & 0x3;
                WriteMemory(ea, Accumulators[accumulator]);
                description = $"STA AC{accumulator}, @{FormatAddress(ea)}";
                break;
            default:
                description = $"Unknown MRF opcode {opac} (halting)";
                Halt("Unknown MRF opcode");
                break;
        }

        return new ExecutionStep(instructionAddress, instruction, description, Halted, tookBranch)
        {
            AccumulatorIndex = accumulator,
            Link = Link
        };
    }

    private ExecutionStep ExecuteOperate(ushort instruction, ushort instructionAddress)
    {
        var src = (instruction >> 13) & 0x3;
        var dst = (instruction >> 11) & 0x3;
        var alu = (instruction >> 8) & 0x7;
        var shift = (instruction >> 6) & 0x3;
        var carryControl = (instruction >> 4) & 0x3;
        var noLoad = (instruction & 0x8) != 0;
        var skip = instruction & 0x7;

        var srcValue = Accumulators[src];
        var dstValue = Accumulators[dst];
        var description = $"OPR src=AC{src} dst=AC{dst}";

        var carryIn = ApplyCarryControl(carryControl);
        var result = (ushort)0;
        var carryOut = Link;
        var updatesCarry = false;

        switch (alu)
        {
            case 0: // COM
                result = (ushort)~srcValue;
                break;
            case 1: // NEG
                (result, carryOut) = AddWithCarry((ushort)~srcValue, 0, true);
                updatesCarry = true;
                break;
            case 2: // MOV
                result = srcValue;
                break;
            case 3: // INC
                (result, carryOut) = AddWithCarry(srcValue, 1, false);
                updatesCarry = true;
                break;
            case 4: // ADC
                (result, carryOut) = AddWithCarry(dstValue, srcValue, carryIn);
                updatesCarry = true;
                break;
            case 5: // SUB
                (result, carryOut) = SubtractWithBorrow(dstValue, srcValue, carryIn);
                updatesCarry = true;
                break;
            case 6: // ADD
                (result, carryOut) = AddWithCarry(dstValue, srcValue, false);
                updatesCarry = true;
                break;
            case 7: // AND
                result = (ushort)(dstValue & srcValue);
                break;
        }

        if (updatesCarry)
        {
            Link = carryOut;
        }

        result = ApplyShift(result, shift, Link, out var shiftCarry);
        if (shiftCarry.HasValue)
        {
            Link = shiftCarry.Value;
        }

        if (!noLoad)
        {
            Accumulators[dst] = result;
        }

        var tookBranch = ApplySkip(skip, result);
        if (tookBranch)
        {
            ProgramCounter = (ushort)((ProgramCounter + 1) & AddressMask);
        }

        return new ExecutionStep(instructionAddress, instruction, description, Halted, tookBranch)
        {
            AccumulatorIndex = dst,
            Link = Link
        };
    }

    private ushort EffectiveAddress(bool indirect, int mode, int displacement, ushort instructionAddress)
    {
        var offset = mode == 0 ? displacement : SignExtend8(displacement);
        var baseAddress = mode switch
        {
            0 => 0,
            1 => instructionAddress,
            2 => Accumulators[2],
            _ => Accumulators[3]
        };

        var ea = (ushort)(((baseAddress + offset) & AddressMask));
        return indirect ? ResolveIndirect(ea) : ea;
    }

    private ushort ResolveIndirect(ushort pointer)
    {
        if (pointer >= 16 && pointer <= 23) // 0o20-0o27
        {
            var updated = (ushort)((ReadMemory(pointer) + 1) & WordMask);
            WriteMemory(pointer, updated);
            return (ushort)(updated & AddressMask);
        }

        if (pointer >= 24 && pointer <= 31) // 0o30-0o37
        {
            var updated = (ushort)((ReadMemory(pointer) - 1) & WordMask);
            WriteMemory(pointer, updated);
            return (ushort)(updated & AddressMask);
        }

        return (ushort)(ReadMemory(pointer) & AddressMask);
    }

    private bool ApplyCarryControl(int carryControl)
    {
        var carryIn = carryControl switch
        {
            1 => false,
            2 => true,
            3 => !Link,
            _ => Link
        };

        Link = carryIn;
        return carryIn;
    }

    private static ushort ApplyShift(ushort value, int shift, bool linkIn, out bool? carryOut)
    {
        carryOut = null;
        switch (shift)
        {
            case 1: // left
                carryOut = (value & 0x8000) != 0;
                return (ushort)(((value << 1) & WordMask) | (linkIn ? 1 : 0));
            case 2: // right
                carryOut = (value & 0x1) != 0;
                return (ushort)((value >> 1) | (linkIn ? 0x8000 : 0));
            case 3: // swap
                return (ushort)(((value & 0xFF) << 8) | ((value >> 8) & 0xFF));
            default:
                return value;
        }
    }

    private bool ApplySkip(int skip, ushort result)
    {
        return skip switch
        {
            1 => true,
            2 => !Link,
            3 => Link,
            4 => result == 0,
            5 => result != 0,
            6 => !Link || result == 0,
            7 => Link && result != 0,
            _ => false
        };
    }

    private static (ushort Result, bool Carry) AddWithCarry(ushort left, ushort right, bool link)
    {
        var carryIn = link ? 1 : 0;
        var total = left + right + carryIn;
        return ((ushort)(total & WordMask), (total & ~WordMask) != 0);
    }

    private static (ushort Result, bool Borrow) SubtractWithBorrow(ushort left, ushort right, bool link)
    {
        // Link acts as a borrow bit here as a small convenience for chaining.
        var borrowIn = link ? 1 : 0;
        var total = left - right - borrowIn;
        var borrow = total < 0;
        return ((ushort)(total & WordMask), borrow);
    }

    private static bool IsZero(ushort value) => value == 0;

    private static short SignExtend8(int value)
    {
        var masked = value & 0xFF;
        if ((masked & 0x80) != 0)
        {
            return (short)(masked | unchecked((short)0xFF00));
        }

        return (short)masked;
    }

    private static string FormatAddress(ushort value) => Convert.ToString(value, 8).PadLeft(4, '0');

    public static string FormatWord(ushort value) => Convert.ToString(value, 8).PadLeft(6, '0');
}

public readonly record struct ExecutionStep(
    ushort Address,
    ushort Instruction,
    string Description,
    bool Halted,
    bool BranchTaken)
{
    public int AccumulatorIndex { get; init; }
    public bool Link { get; init; }
}

public enum Instruction
{
    Nop = 0,
    Load = 1,
    Store = 2,
    Add = 3,
    Subtract = 4,
    And = 5,
    Or = 6,
    Xor = 7,
    Shift = 8,
    AddImmediate = 9,
    Branch = 10,
    ConditionalBranch = 11,
    JumpToSubroutine = 12,
    LoadImmediate = 13,
    IncSkip = 14,
    Halt = 15
}
