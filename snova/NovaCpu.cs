using System.Collections.ObjectModel;

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

    private readonly ushort[] _memory = new ushort[1 << 15]; // 32K words.

    public ushort[] Accumulators { get; } = new ushort[4];
    public ushort ProgramCounter { get; private set; }
    public bool Link { get; private set; }
    public bool Halted { get; private set; }
    public NovaIoBus IoBus { get; } = new();

    public ReadOnlyCollection<ushort> Memory => Array.AsReadOnly(_memory);

    public void Reset(ushort startAddress = 0)
    {
        Array.Fill(Accumulators, (ushort)0);
        Array.Fill(_memory, (ushort)0);
        ProgramCounter = startAddress;
        Link = false;
        Halted = false;
    }

    public ushort ReadMemory(ushort address) => _memory[address & AddressMask];

    public void WriteMemory(ushort address, ushort value) => _memory[address & AddressMask] = value;

    public void SetProgramCounter(ushort address) => ProgramCounter = (ushort)(address & AddressMask);

    public void RegisterDevice(INovaIoDevice device) => IoBus.RegisterDevice(device);

    public ExecutionStep Step()
    {
        if (Halted)
        {
            return new ExecutionStep(ProgramCounter, 0, "CPU halted", true, false);
        }

        var instructionAddress = ProgramCounter;
        var instruction = Fetch();
        if (IsIoInstruction(instruction))
        {
            return ExecuteIo(instruction, instructionAddress);
        }

        var opcode = (Instruction)(instruction >> 12);
        var accumulator = (instruction >> 10) & 0x3;
        var indirect = (instruction & 0x200) != 0;
        var page = (instruction & 0x100) != 0;
        var offset = (ushort)(instruction & OffsetMask);
        var description = string.Empty;
        var tookBranch = false;

        ushort EffectiveAddress()
        {
            var baseAddress = page ? (ushort)(ProgramCounter & PageMask) : (ushort)0;
            var ea = (ushort)((baseAddress | offset) & AddressMask);
            if (indirect)
            {
                ea = ReadMemory(ea);
            }

            return ea;
        }

        switch (opcode)
        {
            case Instruction.Nop:
                description = "NOP";
                break;
            case Instruction.Load:
                {
                    var ea = EffectiveAddress();
                    Accumulators[accumulator] = ReadMemory(ea);
                    description = $"LDA AC{accumulator}, @{FormatAddress(ea)}";
                }
                break;
            case Instruction.Store:
                {
                    var ea = EffectiveAddress();
                    WriteMemory(ea, Accumulators[accumulator]);
                    description = $"STA AC{accumulator}, @{FormatAddress(ea)}";
                }
                break;
            case Instruction.Add:
                {
                    var ea = EffectiveAddress();
                    var value = ReadMemory(ea);
                    var (result, carry) = AddWithCarry(Accumulators[accumulator], value, Link);
                    Accumulators[accumulator] = result;
                    Link = carry;
                    description = $"ADD AC{accumulator}, @{FormatAddress(ea)}";
                }
                break;
            case Instruction.Subtract:
                {
                    var ea = EffectiveAddress();
                    var value = ReadMemory(ea);
                    var (result, borrow) = SubtractWithBorrow(Accumulators[accumulator], value, Link);
                    Accumulators[accumulator] = result;
                    Link = borrow;
                    description = $"SUB AC{accumulator}, @{FormatAddress(ea)}";
                }
                break;
            case Instruction.And:
                {
                    var ea = EffectiveAddress();
                    var value = ReadMemory(ea);
                    Accumulators[accumulator] &= value;
                    Link = false;
                    description = $"AND AC{accumulator}, @{FormatAddress(ea)}";
                }
                break;
            case Instruction.Or:
                {
                    var ea = EffectiveAddress();
                    var value = ReadMemory(ea);
                    Accumulators[accumulator] |= value;
                    Link = false;
                    description = $"OR AC{accumulator}, @{FormatAddress(ea)}";
                }
                break;
            case Instruction.Xor:
                {
                    var ea = EffectiveAddress();
                    var value = ReadMemory(ea);
                    Accumulators[accumulator] ^= value;
                    Link = false;
                    description = $"XOR AC{accumulator}, @{FormatAddress(ea)}";
                }
                break;
            case Instruction.Shift:
                {
                    var count = offset & 0xF;
                    var directionRight = (offset & 0x10) != 0;
                    var throughLink = (offset & 0x20) != 0;
                    var value = Accumulators[accumulator];
                    if (count == 0)
                    {
                        description = "SHIFT (no-op)";
                        break;
                    }

                    if (directionRight)
                    {
                        for (var i = 0; i < count; i++)
                        {
                            var newLink = (value & 0x1) != 0;
                            value >>= 1;
                            if (throughLink && Link)
                            {
                                value |= 0x8000;
                            }

                            Link = newLink;
                        }

                        description = $"SHR{(throughLink ? 'L' : ' ')} AC{accumulator}, {count}";
                    }
                    else
                    {
                        for (var i = 0; i < count; i++)
                        {
                            var newLink = (value & 0x8000) != 0;
                            value <<= 1;
                            value &= WordMask;
                            if (throughLink && Link)
                            {
                                value |= 0x1;
                            }

                            Link = newLink;
                        }

                        description = $"SHL{(throughLink ? 'L' : ' ')} AC{accumulator}, {count}";
                    }

                    Accumulators[accumulator] = value;
                }
                break;
            case Instruction.AddImmediate:
                {
                    var imm = SignExtend8(offset);
                    var (result, carry) = AddWithCarry(Accumulators[accumulator], (ushort)imm, Link);
                    Accumulators[accumulator] = result;
                    Link = carry;
                    description = $"ADDI AC{accumulator}, {imm:+#0;-#0;+0}";
                }
                break;
            case Instruction.Branch:
                {
                    var ea = EffectiveAddress();
                    ProgramCounter = ea;
                    description = $"BR @{FormatAddress(ea)}";
                    tookBranch = true;
                }
                break;
            case Instruction.ConditionalBranch:
                {
                    var ea = EffectiveAddress();
                    var targetAcc = Accumulators[accumulator];
                    var shouldBranch = indirect ? !IsZero(targetAcc) : IsZero(targetAcc);
                    if (shouldBranch)
                    {
                        ProgramCounter = ea;
                        tookBranch = true;
                    }

                    description = shouldBranch
                        ? $"B{(indirect ? "NZ" : "Z")} @{FormatAddress(ea)}"
                        : $"B{(indirect ? "NZ" : "Z")} (not taken)";
                }
                break;
            case Instruction.JumpToSubroutine:
                {
                    var ea = EffectiveAddress();
                    Accumulators[accumulator] = ProgramCounter;
                    ProgramCounter = ea;
                    tookBranch = true;
                    description = $"JSR AC{accumulator}, @{FormatAddress(ea)}";
                }
                break;
            case Instruction.LoadImmediate:
                {
                    var imm = (ushort)offset;
                    Accumulators[accumulator] = imm;
                    Link = false;
                    description = $"LDAI AC{accumulator}, {FormatWord(imm)}";
                }
                break;
            case Instruction.IncSkip:
                {
                    var ea = EffectiveAddress();
                    var value = (ushort)((ReadMemory(ea) + 1) & WordMask);
                    WriteMemory(ea, value);
                    var skip = value == 0;
                    if (skip)
                    {
                        ProgramCounter = (ushort)((ProgramCounter + 1) & AddressMask);
                    }

                    description = skip
                        ? $"ISZ @{FormatAddress(ea)} (skip)"
                        : $"ISZ @{FormatAddress(ea)}";
                }
                break;
            case Instruction.Halt:
                description = "HALT";
                Halted = true;
                break;
            default:
                description = $"Unknown opcode {opcode} (halting)";
                Halted = true;
                break;
        }

        return new ExecutionStep(instructionAddress, instruction, description, Halted, tookBranch)
        {
            AccumulatorIndex = accumulator,
            Link = Link
        };
    }

    private ushort Fetch()
    {
        var value = _memory[ProgramCounter];
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

        handled = IoBus.TryExecute(io, ref accumulatorValue, out skip);
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
        var signal = (instruction >> 11) & 0x3;
        var function = (instruction >> 8) & 0x7;
        var ac = (instruction >> 6) & 0x3;
        var device = instruction & 0x3F;

        var start = signal == 1;
        var clear = signal == 2;
        var pulse = signal == 3;

        var kind = function switch
        {
            0 => NovaIoOpKind.NIO,
            1 => NovaIoOpKind.DIA,
            2 => NovaIoOpKind.DOA,
            3 => NovaIoOpKind.DIB,
            4 => NovaIoOpKind.DOB,
            5 => NovaIoOpKind.DIC,
            6 => NovaIoOpKind.DOC,
            _ => ac switch
            {
                0 => NovaIoOpKind.SKPBN,
                1 => NovaIoOpKind.SKPBZ,
                2 => NovaIoOpKind.SKPDN,
                _ => NovaIoOpKind.SKPDZ
            }
        };

        return new NovaIoOp(kind, device, ac, start, clear, pulse);
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
