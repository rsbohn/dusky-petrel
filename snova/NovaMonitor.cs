using System.Collections.Generic;
using System.Globalization;
using System.Text;

namespace Snova;

public class NovaMonitor
{
    private readonly NovaCpu _cpu;
    private readonly HashSet<ushort> _breakpoints = new();
    private readonly Dictionary<string, string> _helpText;

    public NovaMonitor(NovaCpu cpu)
    {
        _cpu = cpu;
        _cpu.Reset();
        _helpText = BuildHelp();
    }

    public void Run()
    {
        Console.WriteLine("snova - Data General Nova 1210 emulator");
        Console.WriteLine("Type 'help' for command summary. Numbers default to octal; prefix with 0x for hex.");
        while (true)
        {
            Console.Write("snova> ");
            var line = Console.ReadLine();
            if (line is null)
            {
                break;
            }

            if (string.IsNullOrWhiteSpace(line))
            {
                continue;
            }

            if (!HandleCommand(line.Trim()))
            {
                break;
            }
        }
    }

    private bool HandleCommand(string line)
    {
        var parts = line.Split(' ', StringSplitOptions.RemoveEmptyEntries);
        var command = parts[0].ToLowerInvariant();
        var args = parts.Skip(1).ToArray();
        switch (command)
        {
            case "q":
            case "quit":
            case "exit":
                return false;
            case "help":
                ShowHelp(args);
                break;
            case "reset":
                Reset(args);
                break;
            case "regs":
            case "r":
                DumpRegisters();
                break;
            case "exam":
            case "x":
                Examine(args);
                break;
            case "deposit":
            case "dep":
            case "d":
                Deposit(args);
                break;
            case "step":
            case "s":
                Step(args);
                break;
            case "run":
                RunUntilHalt(args);
                break;
            case "break":
            case "b":
                ToggleBreakpoint(args);
                break;
            case "breaks":
                ListBreakpoints();
                break;
            case "dis":
                Disassemble(args);
                break;
            case "sample":
                LoadSample();
                break;
            default:
                Console.WriteLine($"Unknown command '{command}'. Type 'help' for options.");
                break;
        }

        return true;
    }

    private void ShowHelp(string[] args)
    {
        if (args.Length == 0)
        {
            Console.WriteLine("Available commands:");
            foreach (var kvp in _helpText)
            {
                Console.WriteLine($"   {kvp.Key,-12} {kvp.Value}");
            }

            return;
        }

        var key = args[0].ToLowerInvariant();
        if (_helpText.TryGetValue(key, out var details))
        {
            Console.WriteLine(details);
        }
        else
        {
            Console.WriteLine($"No help entry for '{key}'.");
        }
    }

    private void Reset(string[] args)
    {
        var start = args.Length > 0 && TryParseNumber(args[0], out var parsed)
            ? parsed
            : (ushort)0;
        _cpu.Reset(start);
        _breakpoints.Clear();
        Console.WriteLine($"CPU reset. PC={NovaCpu.FormatWord(_cpu.ProgramCounter)}");
    }

    private void DumpRegisters()
    {
        var sb = new StringBuilder();
        for (var i = 0; i < _cpu.Accumulators.Length; i++)
        {
            sb.Append($"AC{i}: {NovaCpu.FormatWord(_cpu.Accumulators[i])}  ");
        }

        sb.Append($"PC: {NovaCpu.FormatWord(_cpu.ProgramCounter)}  ");
        sb.Append($"LINK: {(_cpu.Link ? 1 : 0)}  ");
        sb.Append($"HALT: {_cpu.Halted}");
        Console.WriteLine(sb.ToString());
    }

    private void Examine(string[] args)
    {
        if (args.Length == 0 || !TryParseNumber(args[0], out var start))
        {
            Console.WriteLine("Usage: exam <address> [count]");
            return;
        }

        var count = args.Length > 1 && TryParseNumber(args[1], out var parsedCount)
            ? parsedCount
            : (ushort)8;

        for (var i = 0; i < count; i++)
        {
            var addr = (ushort)(start + i);
            if (i % 8 == 0)
            {
                if (i > 0) Console.WriteLine();
                Console.Write($"{NovaCpu.FormatWord(addr)}: ");
            }
            Console.Write($"{NovaCpu.FormatWord(_cpu.ReadMemory(addr))} ");
        }
        Console.WriteLine();
    }

    private void Deposit(string[] args)
    {
        if (args.Length < 2 || !TryParseNumber(args[0], out var address))
        {
            Console.WriteLine("Usage: deposit <address> <value> [value2 ...]");
            return;
        }

        for (var i = 1; i < args.Length; i++)
        {
            if (!TryParseNumber(args[i], out var value))
            {
                Console.WriteLine($"Invalid value: {args[i]}");
                return;
            }
            var addr = (ushort)(address + i - 1);
            _cpu.WriteMemory(addr, value);
            Console.WriteLine($"[{NovaCpu.FormatWord(addr)}] <= {NovaCpu.FormatWord(value)}");
        }
    }

    private void Step(string[] args)
    {
        var count = args.Length > 0 && TryParseNumber(args[0], out var parsed)
            ? parsed
            : (ushort)1;

        for (var i = 0; i < count; i++)
        {
            var step = _cpu.Step();
            RenderStep(step);
            if (step.Halted)
            {
                break;
            }

            if (_breakpoints.Contains(_cpu.ProgramCounter))
            {
                Console.WriteLine($"Reached breakpoint at {NovaCpu.FormatWord(_cpu.ProgramCounter)}");
                break;
            }
        }
    }

    private void RunUntilHalt(string[] args)
    {
        var maxSteps = args.Length > 0 && int.TryParse(args[0], out var parsed) ? parsed : int.MaxValue;
        var executed = 0;
        while (!_cpu.Halted && executed < maxSteps)
        {
            if (_breakpoints.Contains(_cpu.ProgramCounter))
            {
                Console.WriteLine($"Breakpoint hit at {NovaCpu.FormatWord(_cpu.ProgramCounter)}");
                break;
            }

            var step = _cpu.Step();
            executed++;
            if (step.Halted)
            {
                RenderStep(step);
                break;
            }
        }

        Console.WriteLine($"Stopped after {executed} step(s). PC={NovaCpu.FormatWord(_cpu.ProgramCounter)} HALT={_cpu.Halted}");
    }

    private void ToggleBreakpoint(string[] args)
    {
        if (args.Length == 0 || !TryParseNumber(args[0], out var address))
        {
            Console.WriteLine("Usage: break <address>");
            return;
        }

        if (_breakpoints.Remove(address))
        {
            Console.WriteLine($"Breakpoint cleared at {NovaCpu.FormatWord(address)}");
        }
        else
        {
            _breakpoints.Add(address);
            Console.WriteLine($"Breakpoint set at {NovaCpu.FormatWord(address)}");
        }
    }

    private void ListBreakpoints()
    {
        if (_breakpoints.Count == 0)
        {
            Console.WriteLine("No active breakpoints.");
            return;
        }

        Console.WriteLine("Breakpoints:");
        foreach (var bp in _breakpoints.OrderBy(b => b))
        {
            Console.WriteLine($"  {NovaCpu.FormatWord(bp)}");
        }
    }

    private void Disassemble(string[] args)
    {
        if (args.Length == 0 || !TryParseNumber(args[0], out var start))
        {
            Console.WriteLine("Usage: dis <address> [count]");
            return;
        }

        var count = args.Length > 1 && TryParseNumber(args[1], out var parsedCount)
            ? parsedCount
            : (ushort)8;

        for (var i = 0; i < count; i++)
        {
            var address = (ushort)(start + i);
            var instruction = _cpu.ReadMemory(address);
            var text = DisassembleWord(address, instruction);
            Console.WriteLine(text);
        }
    }

    private void LoadSample()
    {
        _cpu.Reset(0x0200);
        // A tiny demonstration program. AC0 counts up to 10, halting when done.
        var program = new ushort[]
        {
            EncodeImmediate(Instruction.LoadImmediate, 0, 0), // AC0 = 0
            EncodeImmediate(Instruction.LoadImmediate, 1, 10), // AC1 = 10
            EncodeImmediate(Instruction.AddImmediate, 0, 1),   // loop: AC0++
            EncodeImmediate(Instruction.AddImmediate, 1, unchecked((ushort)-1)), // AC1--
            EncodeInstruction(Instruction.ConditionalBranch, 1, page: true, offset: 0x02), // BNZ to loop
            EncodeInstruction(Instruction.Halt, 0),
        };

        for (var i = 0; i < program.Length; i++)
        {
            _cpu.WriteMemory((ushort)(_cpu.ProgramCounter + i), program[i]);
        }

        Console.WriteLine("Sample program loaded at 0200. Use 'run' or 'step' to execute.");
    }

    private ushort EncodeImmediate(Instruction opcode, int accumulator, int value)
    {
        return (ushort)(((int)opcode << 12) | (accumulator << 10) | (value & 0xFF));
    }

    private ushort EncodeInstruction(Instruction opcode, int accumulator = 0, bool indirect = false, bool page = false, int offset = 0)
    {
        var word = ((int)opcode << 12) | (accumulator << 10);
        if (indirect)
        {
            word |= 0x200;
        }

        if (page)
        {
            word |= 0x100;
        }

        word |= offset & NovaCpu.OffsetMask;
        return (ushort)word;
    }

    private void RenderStep(ExecutionStep step)
    {
        var pcText = NovaCpu.FormatWord(step.Address);
        var instText = NovaCpu.FormatWord(step.Instruction);
        Console.WriteLine($"{pcText}: {instText}  {step.Description}");
    }

    private string DisassembleWord(ushort address, ushort instruction)
    {
        var opcode = (Instruction)(instruction >> 12);
        var accumulator = (instruction >> 10) & 0x3;
        var indirect = (instruction & 0x200) != 0;
        var page = (instruction & 0x100) != 0;
        var offset = (ushort)(instruction & NovaCpu.OffsetMask);
        return opcode switch
        {
            Instruction.Nop => FormatInstruction(address, instruction, "NOP"),
            Instruction.Load => FormatInstruction(address, instruction, $"LDA AC{accumulator}, {FormatEffective(address, page, indirect, offset)}"),
            Instruction.Store => FormatInstruction(address, instruction, $"STA AC{accumulator}, {FormatEffective(address, page, indirect, offset)}"),
            Instruction.Add => FormatInstruction(address, instruction, $"ADD AC{accumulator}, {FormatEffective(address, page, indirect, offset)}"),
            Instruction.Subtract => FormatInstruction(address, instruction, $"SUB AC{accumulator}, {FormatEffective(address, page, indirect, offset)}"),
            Instruction.And => FormatInstruction(address, instruction, $"AND AC{accumulator}, {FormatEffective(address, page, indirect, offset)}"),
            Instruction.Or => FormatInstruction(address, instruction, $"OR AC{accumulator}, {FormatEffective(address, page, indirect, offset)}"),
            Instruction.Xor => FormatInstruction(address, instruction, $"XOR AC{accumulator}, {FormatEffective(address, page, indirect, offset)}"),
            Instruction.Shift => FormatInstruction(address, instruction, $"SHFT AC{accumulator}, {(indirect ? "R" : "L")}{offset & 0xF}{((offset & 0x20) != 0 ? "L" : string.Empty)}"),
            Instruction.AddImmediate => FormatInstruction(address, instruction, $"ADDI AC{accumulator}, {NovaCpu.FormatWord(offset)}"),
            Instruction.Branch => FormatInstruction(address, instruction, $"BR {FormatEffective(address, page, indirect, offset)}"),
            Instruction.ConditionalBranch => FormatInstruction(address, instruction, $"B{(indirect ? "NZ" : "Z")} AC{accumulator}, {FormatEffective(address, page, indirect, offset)}"),
            Instruction.JumpToSubroutine => FormatInstruction(address, instruction, $"JSR AC{accumulator}, {FormatEffective(address, page, indirect, offset)}"),
            Instruction.LoadImmediate => FormatInstruction(address, instruction, $"LDAI AC{accumulator}, {NovaCpu.FormatWord(offset)}"),
            Instruction.IncSkip => FormatInstruction(address, instruction, $"ISZ {FormatEffective(address, page, indirect, offset)}"),
            Instruction.Halt => FormatInstruction(address, instruction, "HALT"),
            _ => FormatInstruction(address, instruction, $"DW {NovaCpu.FormatWord(instruction)}")
        };
    }

    private string FormatInstruction(ushort address, ushort instruction, string text)
    {
        return $"{NovaCpu.FormatWord(address)}: {NovaCpu.FormatWord(instruction)} {text}";
    }

    private string FormatEffective(ushort pc, bool page, bool indirect, ushort offset)
    {
        var baseAddress = page ? (pc & NovaCpu.PageMask) : 0;
        var target = (ushort)((baseAddress | offset) & NovaCpu.AddressMask);
        var text = $"{NovaCpu.FormatWord(target)}";
        if (indirect)
        {
            text += " (I)";
        }

        return text;
    }

    private static bool TryParseNumber(string text, out ushort value)
    {
        text = text.Trim();
        var style = NumberStyles.AllowLeadingSign;
        int radix;
        if (text.StartsWith("0x", StringComparison.OrdinalIgnoreCase))
        {
            radix = 16;
            text = text[2..];
            style |= NumberStyles.AllowHexSpecifier;
        }
        else if (text.StartsWith("0o", StringComparison.OrdinalIgnoreCase))
        {
            radix = 8;
            text = text[2..];
        }
        else if (text.StartsWith("0b", StringComparison.OrdinalIgnoreCase))
        {
            radix = 2;
            text = text[2..];
        }
        else
        {
            radix = 8; // Traditional Nova monitors are octal-first.
        }

        try
        {
            var parsed = Convert.ToInt32(text, radix);
            value = (ushort)(parsed & NovaCpu.WordMask);
            return true;
        }
        catch
        {
            value = 0;
            return false;
        }
    }

    private Dictionary<string, string> BuildHelp()
    {
        return new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
        {
            ["help"] = "help [command]       Show command list or details",
            ["reset"] = "reset [addr]         Reset CPU and clear memory (start at optional addr)",
            ["regs"] = "regs                 Display registers",
            ["exam"] = "exam <addr> [n]      Examine n words from addr",
            ["deposit"] = "deposit <addr> <v>  Store value at address",
            ["step"] = "step [n]             Step through n instructions",
            ["run"] = "run [n]              Run until HALT/breakpoint or n instructions",
            ["break"] = "break <addr>         Toggle breakpoint",
            ["breaks"] = "breaks              List breakpoints",
            ["dis"] = "dis <addr> [n]       Disassemble n words from addr",
            ["sample"] = "sample               Load a small counting demo at 0200",
            ["exit"] = "exit                 Quit the monitor"
        };
    }
}
