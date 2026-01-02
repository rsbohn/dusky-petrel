using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Security.Cryptography;
using System.Text;

namespace Snova;

public class NovaMonitor
{
    private const int TcIndexWordsPerEntry = 8;
    private const int TcIndexLabelWords = 3;
    private const int TcIndexLabelChars = 6;
    private const int TcIndexEntries = Tc08.DataWordsPerBlock / TcIndexWordsPerEntry;

    private readonly NovaCpu _cpu;
    private readonly NovaConsoleTty? _tty;
    private readonly NovaWatchdogDevice? _watchdog;
    private readonly Tc08? _tc08;
    private readonly NovaRtcDevice? _rtc;
    private readonly NovaPaperTape? _paperTape;
    private readonly NovaLinePrinterDevice? _linePrinter;
    private readonly HashSet<ushort> _breakpoints = new();
    private readonly Dictionary<string, string> _helpText;
    private readonly object _commandLock = new();

    public NovaMonitor(
        NovaCpu cpu,
        NovaConsoleTty? tty = null,
        NovaWatchdogDevice? watchdog = null,
        Tc08? tc08 = null,
        NovaRtcDevice? rtc = null,
        NovaPaperTape? paperTape = null,
        NovaLinePrinterDevice? linePrinter = null)
    {
        _cpu = cpu;
        _tty = tty;
        _watchdog = watchdog;
        _tc08 = tc08;
        _rtc = rtc;
        _paperTape = paperTape;
        _linePrinter = linePrinter;
        _cpu.Reset();
        _watchdog?.ResetDeviceState();
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

            if (!ExecuteCommandLocal(line.Trim()))
            {
                break;
            }
        }
    }

    public string ExecuteCommandLine(string line, bool allowExit)
    {
        var trimmed = line.Trim();
        if (!allowExit && IsExitCommand(trimmed))
        {
            return "Exit is disabled on the unix console.\n";
        }

        using var writer = new StringWriter();
        lock (_commandLock)
        {
            var originalOut = Console.Out;
            var originalError = Console.Error;
            try
            {
                Console.SetOut(writer);
                Console.SetError(writer);
                _ = HandleCommand(trimmed);
            }
            catch (Exception ex)
            {
                writer.WriteLine($"Unix console error: {ex.Message}");
            }
            finally
            {
                Console.SetOut(originalOut);
                Console.SetError(originalError);
            }
        }

        var response = writer.ToString();
        if (string.IsNullOrEmpty(response))
        {
            response = "OK\n";
        }

        return response;
    }

    private bool ExecuteCommandLocal(string line)
    {
        lock (_commandLock)
        {
            return HandleCommand(line);
        }
    }

    private static bool IsExitCommand(string line)
    {
        if (string.IsNullOrWhiteSpace(line))
        {
            return false;
        }

        var trimmed = line.Trim();
        var spaceIndex = trimmed.IndexOf(' ');
        var command = spaceIndex >= 0 ? trimmed[..spaceIndex] : trimmed;
        command = command.ToLowerInvariant();
        return command == "q" || command == "quit" || command == "exit";
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
            case "trace":
            case "t":
                Trace(args);
                break;
            case "run":
                RunUntilHalt(args);
                break;
            case "go":
                RunFromAddress(args);
                break;
            case "tc":
                HandleTc(args);
                break;
            case "tc0":
                HandleTcUnit(0, args);
                break;
            case "tc1":
                HandleTcUnit(1, args);
                break;
            case "rtc":
                HandleRtc(args);
                break;
            case "devices":
                ShowDevices();
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
            case "tty":
                HandleTty(args);
                break;
            case "ptr":
                HandlePtr(args);
                break;
            case "ptp":
                HandlePtp(args);
                break;
            case "lpt":
                HandleLpt(args);
                break;
            case "wdt":
                HandleWatchdog(args);
                break;
            case "asm":
            case "assemble":
                AssembleFileCommand(args);
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

    private void ShowDevices()
    {
        var devices = _cpu.IoBus.GetDevices();
        if (devices.Count == 0)
        {
            Console.WriteLine("No devices attached.");
            return;
        }

        Console.WriteLine("Attached devices:");
        foreach (var (deviceCode, device) in devices)
        {
            Console.WriteLine($"  {FormatDeviceCode(deviceCode)} {DescribeDevice(deviceCode, device)}");
        }
    }

    private void HandleRtc(string[] args)
    {
        if (_rtc is null)
        {
            Console.WriteLine("RTC device not configured.");
            return;
        }

        if (args.Length != 1 || !args[0].Equals("status", StringComparison.OrdinalIgnoreCase))
        {
            Console.WriteLine("Usage: rtc status");
            return;
        }

        var minutes = _rtc.ReadMinutesSinceMidnight();
        var epochSeconds = _rtc.ReadEpochSeconds();
        var deviceCode = FormatDeviceCode(_rtc.DeviceCode);
        Console.WriteLine($"RTC device: {deviceCode}");
        Console.WriteLine($"minutes_since_midnight={minutes}");
        Console.WriteLine($"epoch_seconds={epochSeconds}");
    }

    private void Reset(string[] args)
    {
        var start = args.Length > 0 && TryParseNumber(args[0], out var parsed)
            ? parsed
            : (ushort)0;
        _cpu.Reset(start);
        _watchdog?.ResetDeviceState();
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

        if (_cpu.Halted)
        {
            _cpu.Resume();
        }

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

    private void Trace(string[] args)
    {
        var count = 1;
        if (args.Length > 0)
        {
            if (!TryParseNumber(args[0], out var parsed))
            {
                Console.WriteLine("Usage: trace [n]");
                return;
            }

            count = parsed;
        }

        if (_cpu.Halted)
        {
            _cpu.Resume();
        }

        for (var i = 0; i < count; i++)
        {
            if (_breakpoints.Contains(_cpu.ProgramCounter))
            {
                Console.WriteLine($"Breakpoint hit at {NovaCpu.FormatWord(_cpu.ProgramCounter)}");
                break;
            }

            var step = _cpu.Step();
            RenderStep(step);
            Console.WriteLine(FormatTraceRegisters());
            if (step.Halted)
            {
                break;
            }
        }
    }

    private void RunUntilHalt(string[] args)
    {
        var maxSteps = ParseStepLimit(args, 0);
        RunUntilHalt(maxSteps);
    }

    private void RunFromAddress(string[] args)
    {
        if (args.Length == 0 || !TryParseNumber(args[0], out var start))
        {
            Console.WriteLine("Usage: go <addr> [n]");
            return;
        }

        _cpu.SetProgramCounter(start);
        var maxSteps = ParseStepLimit(args, 1);
        RunUntilHalt(maxSteps);
    }

    private void RunUntilHalt(int maxSteps)
    {
        var executed = 0;
        if (_cpu.Halted)
        {
            _cpu.Resume();
        }
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

        var utcNow = DateTime.UtcNow;
        Console.WriteLine($"UTC {utcNow:HH:mm:ss}");
        var haltReason = string.IsNullOrWhiteSpace(_cpu.HaltReason) ? string.Empty : $" ({_cpu.HaltReason})";
        Console.WriteLine($"Stopped after {executed} step(s). PC={NovaCpu.FormatWord(_cpu.ProgramCounter)} HALT={_cpu.Halted}{haltReason}");
    }

    private static int ParseStepLimit(string[] args, int index)
    {
        if (args.Length > index && int.TryParse(args[index], out var parsed))
        {
            return parsed;
        }

        return int.MaxValue;
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

    private void HandleTc(string[] args)
    {
        if (_tc08 is null)
        {
            Console.WriteLine("TC08 not configured.");
            return;
        }

        if (args.Length == 0)
        {
            Console.WriteLine("Usage: tc <status>");
            return;
        }

        var command = args[0].ToLowerInvariant();
        if (command == "status")
        {
            ShowTcStatus();
            return;
        }

        Console.WriteLine("Usage: tc status");
    }

    private void HandleTcUnit(int unit, string[] args)
    {
        if (_tc08 is null)
        {
            Console.WriteLine("TC08 not configured.");
            return;
        }

        if (args.Length == 0)
        {
            Console.WriteLine("Usage: tc0 <attach|read|write|verify|index> ...");
            return;
        }

        var command = args[0].ToLowerInvariant();
        switch (command)
        {
            case "att":
            case "attach":
                HandleTcAttach(unit, args.Skip(1).ToArray());
                return;
            case "read":
                HandleTcRead(unit, args.Skip(1).ToArray());
                return;
            case "write":
                HandleTcWrite(unit, args.Skip(1).ToArray());
                return;
            case "verify":
                HandleTcVerify(unit, args.Skip(1).ToArray());
                return;
            case "index":
                HandleTcIndex(unit, args.Skip(1).ToArray());
                return;
        }

        Console.WriteLine($"Usage: tc{unit} <attach|read|write|verify|index> ...");
    }

    private void ShowTcStatus()
    {
        for (var i = 0; i < Tc08.DriveCount; i++)
        {
            var status = _tc08!.GetDriveStatus(i);
            var attached = status.Attached ? "attached" : "detached";
            var detail = status.Attached ? $"{status.Path} ({status.SizeBytes} bytes)" : "no media";
            Console.WriteLine($"TC{i}: {attached} - {detail}");
        }
    }

    private void HandleTcAttach(int unit, string[] args)
    {
        if (args.Length < 1)
        {
            Console.WriteLine($"Usage: tc{unit} attach <path> [new]");
            return;
        }

        var path = args[0];
        var create = args.Length > 1 && args[1].Equals("new", StringComparison.OrdinalIgnoreCase);
        if (_tc08!.Attach(unit, path, create, out var error))
        {
            Console.WriteLine($"TC{unit}: attached {path}");
            return;
        }

        Console.WriteLine($"TC{unit}: attach failed - {error}");
    }

    private void HandleTcRead(int unit, string[] args)
    {
        if (args.Length < 2 || !TryParseNumber(args[0], out var block) || !TryParseNumber(args[1], out var addr))
        {
            Console.WriteLine($"Usage: tc{unit} read <block> <addr>");
            return;
        }

        Span<ushort> buffer = stackalloc ushort[Tc08.WordsPerBlock];
        if (!_tc08!.TryReadBlock(unit, block, buffer, out var error))
        {
            Console.WriteLine($"TC{unit}: read failed - {error}");
            return;
        }

        for (var i = 0; i < Tc08.WordsPerBlock; i++)
        {
            _cpu.WriteMemory((ushort)(addr + i), buffer[i]);
        }

        Console.WriteLine($"TC{unit}: read block {NovaCpu.FormatWord(block)} -> {NovaCpu.FormatWord(addr)}");
    }

    private void HandleTcWrite(int unit, string[] args)
    {
        if (args.Length < 2 || !TryParseNumber(args[0], out var block) || !TryParseNumber(args[1], out var addr))
        {
            Console.WriteLine($"Usage: tc{unit} write <block> <addr>");
            return;
        }

        Span<ushort> buffer = stackalloc ushort[Tc08.WordsPerBlock];
        for (var i = 0; i < Tc08.WordsPerBlock; i++)
        {
            buffer[i] = _cpu.ReadMemory((ushort)(addr + i));
        }

        if (!_tc08!.TryWriteBlock(unit, block, buffer, out var error))
        {
            Console.WriteLine($"TC{unit}: write failed - {error}");
            return;
        }

        Console.WriteLine($"TC{unit}: wrote block {NovaCpu.FormatWord(block)} <- {NovaCpu.FormatWord(addr)}");
    }

    private void HandleTcVerify(int unit, string[] args)
    {
        if (args.Length < 2 || !TryParseNumber(args[0], out var block) || !TryParseNumber(args[1], out var addr))
        {
            Console.WriteLine($"Usage: tc{unit} verify <block> <addr>");
            return;
        }

        Span<ushort> buffer = stackalloc ushort[Tc08.WordsPerBlock];
        if (!_tc08!.TryReadBlock(unit, block, buffer, out var error))
        {
            Console.WriteLine($"TC{unit}: verify failed - {error}");
            return;
        }

        var mismatches = 0;
        for (var i = 0; i < Tc08.WordsPerBlock; i++)
        {
            var mem = _cpu.ReadMemory((ushort)(addr + i));
            if (mem != buffer[i])
            {
                mismatches++;
                if (mismatches == 1)
                {
                    var loc = (ushort)(addr + i);
                    Console.WriteLine($"TC{unit}: mismatch at {NovaCpu.FormatWord(loc)} mem={NovaCpu.FormatWord(mem)} tape={NovaCpu.FormatWord(buffer[i])}");
                }
            }
        }

        if (mismatches == 0)
        {
            Console.WriteLine($"TC{unit}: verify OK for block {NovaCpu.FormatWord(block)} at {NovaCpu.FormatWord(addr)}");
            return;
        }

        Console.WriteLine($"TC{unit}: verify found {mismatches} mismatch(es)");
    }

    private void HandleTcIndex(int unit, string[] args)
    {
        if (_tc08 is null)
        {
            Console.WriteLine("TC08 not configured.");
            return;
        }

        if (args.Length == 0 || args[0].Equals("list", StringComparison.OrdinalIgnoreCase))
        {
            HandleTcIndexList(unit);
            return;
        }

        var subcommand = args[0].ToLowerInvariant();
        switch (subcommand)
        {
            case "set":
                HandleTcIndexSet(unit, args.Skip(1).ToArray());
                return;
            case "clear":
                HandleTcIndexClear(unit, args.Skip(1).ToArray());
                return;
            default:
                Console.WriteLine($"Usage: tc{unit} index [list|set|clear] ...");
                return;
        }
    }

    private void HandleTcIndexList(int unit)
    {
        Span<ushort> buffer = stackalloc ushort[Tc08.WordsPerBlock];
        if (!_tc08!.TryReadBlock(unit, 0, buffer, out var error))
        {
            if (error == "Block beyond end of tape.")
            {
                Console.WriteLine($"TC{unit}: no index block (block 0 missing).");
                return;
            }

            Console.WriteLine($"TC{unit}: index read failed - {error}");
            return;
        }

        Console.WriteLine($"TC{unit} index (block 0):");
        for (var entry = 0; entry < TcIndexEntries; entry++)
        {
            var offset = entry * TcIndexWordsPerEntry;
            var empty = true;
            for (var i = 0; i < TcIndexWordsPerEntry; i++)
            {
                if (buffer[offset + i] != 0)
                {
                    empty = false;
                    break;
                }
            }

            var entryLabel = Convert.ToString(entry, 8).PadLeft(2, '0');
            if (empty)
            {
                Console.WriteLine($"  {entryLabel}: <empty>");
                continue;
            }

            var block = buffer[offset];
            var addr = buffer[offset + 1];
            var label = DecodeTcIndexLabel(buffer.Slice(offset + 2, TcIndexLabelWords));
            Console.WriteLine($"  {entryLabel}: block={NovaCpu.FormatWord(block)} addr={NovaCpu.FormatWord(addr)} label={label}");
        }
    }

    private void HandleTcIndexSet(int unit, string[] args)
    {
        if (args.Length < 4 ||
            !TryParseNumber(args[0], out var slotWord) ||
            !TryParseNumber(args[1], out var block) ||
            !TryParseNumber(args[2], out var addr))
        {
            Console.WriteLine($"Usage: tc{unit} index set <slot> <block> <addr> <label>");
            return;
        }

        var slot = slotWord;
        if (slot >= TcIndexEntries)
        {
            Console.WriteLine($"TC{unit}: slot out of range (0-{TcIndexEntries - 1}).");
            return;
        }

        var label = string.Join(' ', args.Skip(3));
        if (!TryEncodeTcIndexLabel(label, out var labelWords, out var labelError))
        {
            Console.WriteLine($"TC{unit}: {labelError}");
            return;
        }

        Span<ushort> buffer = stackalloc ushort[Tc08.WordsPerBlock];
        if (!_tc08!.TryReadBlock(unit, 0, buffer, out var error))
        {
            if (error == "Block beyond end of tape.")
            {
                buffer.Clear();
            }
            else
            {
                Console.WriteLine($"TC{unit}: index read failed - {error}");
                return;
            }
        }

        var offset = slot * TcIndexWordsPerEntry;
        buffer[offset] = block;
        buffer[offset + 1] = addr;
        for (var i = 0; i < TcIndexLabelWords; i++)
        {
            buffer[offset + 2 + i] = labelWords[i];
        }
        for (var i = offset + 2 + TcIndexLabelWords; i < offset + TcIndexWordsPerEntry; i++)
        {
            buffer[i] = 0;
        }

        if (!_tc08.TryWriteBlock(unit, 0, buffer, out error))
        {
            Console.WriteLine($"TC{unit}: index write failed - {error}");
            return;
        }

        Console.WriteLine($"TC{unit}: index entry {Convert.ToString(slot, 8).PadLeft(2, '0')} updated.");
    }

    private void HandleTcIndexClear(int unit, string[] args)
    {
        if (args.Length < 1 || !TryParseNumber(args[0], out var slotWord))
        {
            Console.WriteLine($"Usage: tc{unit} index clear <slot>");
            return;
        }

        var slot = slotWord;
        if (slot >= TcIndexEntries)
        {
            Console.WriteLine($"TC{unit}: slot out of range (0-{TcIndexEntries - 1}).");
            return;
        }

        Span<ushort> buffer = stackalloc ushort[Tc08.WordsPerBlock];
        if (!_tc08!.TryReadBlock(unit, 0, buffer, out var error))
        {
            if (error == "Block beyond end of tape.")
            {
                buffer.Clear();
            }
            else
            {
                Console.WriteLine($"TC{unit}: index read failed - {error}");
                return;
            }
        }

        var offset = slot * TcIndexWordsPerEntry;
        for (var i = 0; i < TcIndexWordsPerEntry; i++)
        {
            buffer[offset + i] = 0;
        }

        if (!_tc08.TryWriteBlock(unit, 0, buffer, out error))
        {
            Console.WriteLine($"TC{unit}: index write failed - {error}");
            return;
        }

        Console.WriteLine($"TC{unit}: index entry {Convert.ToString(slot, 8).PadLeft(2, '0')} cleared.");
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
            var text = NovaDisassembler.DisassembleWord(address, instruction);
            Console.WriteLine(text);
        }
    }

    private void LoadSample()
    {
        var startAddress = (ushort)0x0200; // 0o0200
        _cpu.Reset(startAddress);

        const string source = """
ORG 0200
START:  LDA AC0, ZERO
        STA AC0, COUNT
        LDA AC0, TEN
        STA AC0, LIMIT
LOOP:   ISZ COUNT
        DSZ LIMIT
        JMP LOOP
        HALT
ZERO:   DW 0
TEN:    DW 0o12
COUNT:  DW 0
LIMIT:  DW 0
""";

        var assembler = new NovaAssembler();
        var result = assembler.Assemble(source);
        if (!result.Success)
        {
            Console.WriteLine("Sample assembly failed:");
            foreach (var diag in result.Diagnostics)
            {
                var label = diag.Severity == DiagnosticSeverity.Warning ? "warning" : "error";
                Console.WriteLine($"  Line {diag.LineNumber} ({label}): {diag.Message}");
            }

            return;
        }

        if (result.Diagnostics.Count > 0)
        {
            Console.WriteLine("Sample assembly warnings:");
            foreach (var diag in result.Diagnostics.Where(diag => diag.Severity == DiagnosticSeverity.Warning))
            {
                Console.WriteLine($"  Line {diag.LineNumber} (warning): {diag.Message}");
            }
        }

        foreach (var word in result.Words)
        {
            _cpu.WriteMemory(word.Address, word.Value);
        }

        if (result.StartAddress.HasValue)
        {
            _cpu.SetProgramCounter(result.StartAddress.Value);
        }

        Console.WriteLine("Sample program loaded at 0200. Use 'run' or 'step' to execute.");
    }

    private void HandleTty(string[] args)
    {
        if (_tty is null)
        {
            Console.WriteLine("TTY device not configured.");
            return;
        }

        if (args.Length < 1)
        {
            Console.WriteLine("Usage: tty read <filename>");
            return;
        }

        var subcommand = args[0].ToLowerInvariant();
        switch (subcommand)
        {
            case "read":
                if (args.Length < 2)
                {
                    Console.WriteLine("Usage: tty read <filename>");
                    return;
                }

                var path = args[1];
                if (!File.Exists(path))
                {
                    Console.WriteLine($"File not found: {path}");
                    return;
                }

                try
                {
                    _tty.EnqueueInputFile(path, appendEof: true);
                    Console.WriteLine($"Queued {_tty.PendingInput} byte(s) for TTI (EOF appended).");
                }
                catch (Exception ex)
                {
                    Console.WriteLine($"TTY read failed: {ex.Message}");
                }
                break;
            default:
                Console.WriteLine($"Unknown tty command '{subcommand}'.");
                break;
        }
    }

    private void HandlePtr(string[] args)
    {
        if (_paperTape is null)
        {
            Console.WriteLine("Paper tape not configured.");
            return;
        }

        if (args.Length < 1)
        {
            Console.WriteLine("Usage: ptr <read|status> ...");
            return;
        }

        var subcommand = args[0].ToLowerInvariant();
        switch (subcommand)
        {
            case "read":
                if (args.Length < 2)
                {
                    Console.WriteLine("Usage: ptr read <filename>");
                    return;
                }

                var path = args[1];
                if (!File.Exists(path))
                {
                    Console.WriteLine($"File not found: {path}");
                    return;
                }

                try
                {
                    _paperTape.EnqueueInputFile(path);
                    Console.WriteLine($"Queued {_paperTape.PendingInput} byte(s) for PTR.");
                }
                catch (Exception ex)
                {
                    Console.WriteLine($"PTR read failed: {ex.Message}");
                }
                break;
            case "status":
                Console.WriteLine($"PTR queued bytes: {_paperTape.PendingInput}");
                break;
            default:
                Console.WriteLine($"Unknown ptr command '{subcommand}'.");
                break;
        }
    }

    private void HandlePtp(string[] args)
    {
        if (_paperTape is null)
        {
            Console.WriteLine("Paper tape not configured.");
            return;
        }

        if (args.Length < 1)
        {
            Console.WriteLine("Usage: ptp <attach|status> ...");
            return;
        }

        var subcommand = args[0].ToLowerInvariant();
        switch (subcommand)
        {
            case "attach":
                if (args.Length < 2)
                {
                    Console.WriteLine("Usage: ptp attach <filename>");
                    return;
                }

                _paperTape.SetPunchPath(args[1]);
                Console.WriteLine($"PTP output set to {_paperTape.PunchPath}");
                break;
            case "status":
                Console.WriteLine($"PTP output: {_paperTape.PunchPath}");
                break;
            default:
                Console.WriteLine($"Unknown ptp command '{subcommand}'.");
                break;
        }
    }

    private void HandleLpt(string[] args)
    {
        if (_linePrinter is null)
        {
            Console.WriteLine("Line printer not configured.");
            return;
        }

        if (args.Length < 1)
        {
            Console.WriteLine("Usage: lpt status");
            return;
        }

        var subcommand = args[0].ToLowerInvariant();
        switch (subcommand)
        {
            case "status":
                Console.WriteLine($"LPT output: {_linePrinter.OutputPath}");
                break;
            default:
                Console.WriteLine($"Unknown lpt command '{subcommand}'.");
                break;
        }
    }

    private void AssembleFileCommand(string[] args)
    {
        if (args.Length == 0)
        {
            Console.WriteLine("Usage: asm <filename> [start]");
            Console.WriteLine("       asm -l <filename>");
            return;
        }

        var listOnly = false;
        string path;
        if (args[0].Equals("-l", StringComparison.OrdinalIgnoreCase))
        {
            if (args.Length < 2)
            {
                Console.WriteLine("Usage: asm -l <filename>");
                return;
            }

            listOnly = true;
            path = args[1];
        }
        else
        {
            path = args[0];
        }
        if (!File.Exists(path))
        {
            Console.WriteLine($"File not found: {path}");
            return;
        }

        var fingerprint = ComputeMd5(path);

        var assembler = new NovaAssembler();
        AssemblerResult result;
        try
        {
            result = assembler.AssembleFile(path);
        }
        catch (Exception ex)
        {
            Console.WriteLine($"Assembly failed: {ex.Message}");
            return;
        }

        if (!result.Success)
        {
            Console.WriteLine("Assembly failed:");
            foreach (var diag in result.Diagnostics)
            {
                var label = diag.Severity == DiagnosticSeverity.Warning ? "warning" : "error";
                Console.WriteLine($"  line {diag.LineNumber} ({label}): {diag.Message}");
            }

            return;
        }

        if (result.Diagnostics.Count > 0)
        {
            Console.WriteLine("Assembly warnings:");
            foreach (var diag in result.Diagnostics.Where(diag => diag.Severity == DiagnosticSeverity.Warning))
            {
                Console.WriteLine($"  line {diag.LineNumber} (warning): {diag.Message}");
            }
        }

        if (listOnly)
        {
            foreach (var word in result.Words.OrderBy(w => w.Address))
            {
                var addressText = Convert.ToString(word.Address, 8).PadLeft(5, '0');
                var text = NovaDisassembler.DisassembleInstructionListing(word.Address, word.Value);
                Console.WriteLine($"{addressText}: {text}");
            }

            return;
        }

        foreach (var word in result.Words)
        {
            _cpu.WriteMemory(word.Address, word.Value);
        }

        if (args.Length > 1 && TryParseNumber(args[1], out var start))
        {
            _cpu.SetProgramCounter(start);
        }
        else if (result.StartAddress.HasValue)
        {
            _cpu.SetProgramCounter(result.StartAddress.Value);
        }

        Console.WriteLine($"Assembled {result.Words.Count} word(s). PC={NovaCpu.FormatWord(_cpu.ProgramCounter)} MD5={fingerprint}");
    }

    private void HandleWatchdog(string[] args)
    {
        if (_watchdog is null)
        {
            Console.WriteLine("Watchdog device not configured.");
            return;
        }

        if (args.Length == 0)
        {
            Console.WriteLine("Usage: wdt <status|host|enable|disable|timeout|repeat|action|arm|disarm|pet|clear|fire>");
            return;
        }

        var subcommand = args[0].ToLowerInvariant();
        switch (subcommand)
        {
            case "status":
                ShowWatchdogStatus();
                break;
            case "host":
                if (args.Length < 2)
                {
                    Console.WriteLine("Usage: wdt host <on|off>");
                    return;
                }
                if (!TryParseOnOff(args[1], out var hostEnabled))
                {
                    Console.WriteLine("Usage: wdt host <on|off>");
                    return;
                }
                _watchdog.SetHostEnabled(hostEnabled);
                Console.WriteLine($"Watchdog host enabled: {hostEnabled}");
                break;
            case "enable":
                _watchdog.SetHostEnabled(true);
                _watchdog.SetEnabled(true);
                _watchdog.Arm();
                Console.WriteLine("Watchdog enabled and armed.");
                break;
            case "disable":
                _watchdog.SetEnabled(false);
                _watchdog.Clear();
                Console.WriteLine("Watchdog disabled.");
                break;
            case "timeout":
                if (args.Length < 2 || !TryParseMs(args[1], out var timeout))
                {
                    Console.WriteLine("Usage: wdt timeout <ms>");
                    return;
                }
                _watchdog.SetTimeoutMs(timeout);
                Console.WriteLine($"Watchdog timeout set to {timeout} ms.");
                break;
            case "repeat":
                if (args.Length < 2 || !TryParseOnOff(args[1], out var repeat))
                {
                    Console.WriteLine("Usage: wdt repeat <on|off>");
                    return;
                }
                _watchdog.SetRepeat(repeat);
                Console.WriteLine($"Watchdog repeat: {repeat}");
                break;
            case "action":
                if (args.Length < 2 || !TryParseAction(args[1], out var action))
                {
                    Console.WriteLine("Usage: wdt action <none|interrupt|halt|reset>");
                    return;
                }
                _watchdog.SetAction(action);
                Console.WriteLine($"Watchdog action: {action}");
                break;
            case "arm":
                _watchdog.Arm();
                Console.WriteLine("Watchdog armed.");
                break;
            case "disarm":
                _watchdog.Clear();
                Console.WriteLine("Watchdog disarmed and cleared.");
                break;
            case "pet":
                _watchdog.Pet();
                Console.WriteLine("Watchdog petted.");
                break;
            case "clear":
                _watchdog.ClearFired();
                Console.WriteLine("Watchdog fired state cleared.");
                break;
            case "fire":
                _watchdog.ForceFire();
                Console.WriteLine("Watchdog fired.");
                break;
            default:
                Console.WriteLine($"Unknown wdt command '{subcommand}'.");
                break;
        }
    }

    private void ShowWatchdogStatus()
    {
        var status = _watchdog!.GetStatus();
        Console.WriteLine($"WDT device: {Convert.ToString(status.DeviceCode, 8).PadLeft(2, '0')}");
        Console.WriteLine($"host={status.HostEnabled} enable={status.Enabled} active={status.Active} fired={status.Fired}");
        Console.WriteLine($"repeat={status.Repeat} action={status.Action} timeout_ms={status.TimeoutMs}");
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

    private string FormatTraceRegisters()
    {
        var ac0 = NovaCpu.FormatWord(_cpu.Accumulators[0]);
        var ac1 = NovaCpu.FormatWord(_cpu.Accumulators[1]);
        var ac2 = NovaCpu.FormatWord(_cpu.Accumulators[2]);
        var ac3 = NovaCpu.FormatWord(_cpu.Accumulators[3]);
        var pc = NovaCpu.FormatWord(_cpu.ProgramCounter);
        var link = _cpu.Link ? 1 : 0;
        var halted = _cpu.Halted ? "T" : "F";
        return $"[{ac0} {ac1} {ac2} {ac3}] PC={pc} L={link} H={halted}";
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

    private static string DecodeTcIndexLabel(ReadOnlySpan<ushort> words)
    {
        Span<char> chars = stackalloc char[TcIndexLabelChars];
        var idx = 0;
        for (var i = 0; i < TcIndexLabelWords; i++)
        {
            var word = words[i];
            chars[idx++] = (char)((word >> 8) & 0xFF);
            chars[idx++] = (char)(word & 0xFF);
        }

        var label = new string(chars);
        return label.TrimEnd('\0', ' ');
    }

    private static bool TryEncodeTcIndexLabel(string label, out ushort[] words, out string? error)
    {
        words = new ushort[TcIndexLabelWords];
        if (label.Length > TcIndexLabelChars)
        {
            error = $"Label too long (max {TcIndexLabelChars} characters).";
            return false;
        }

        Span<byte> bytes = stackalloc byte[TcIndexLabelChars];
        bytes.Clear();
        for (var i = 0; i < label.Length; i++)
        {
            var ch = label[i];
            if (ch > 0xFF)
            {
                error = "Label must use 8-bit characters.";
                return false;
            }

            bytes[i] = (byte)ch;
        }

        for (var i = 0; i < TcIndexLabelWords; i++)
        {
            words[i] = (ushort)((bytes[i * 2] << 8) | bytes[i * 2 + 1]);
        }

        error = null;
        return true;
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
            ["trace"] = "trace [n]            Trace n instructions with registers",
            ["run"] = "run [n]              Run until HALT/breakpoint or n instructions",
            ["go"] = "go <addr> [n]        Set PC and run until HALT/breakpoint or n instructions",
            ["devices"] = "devices              List attached I/O devices",
            ["rtc"] = "rtc status            Show RTC status",
            ["tc"] = "tc status            Show TC08 drive status",
            ["tc0"] = "tc0 <cmd> ...        TC08 unit 0 (attach/read/write/verify/index)",
            ["tc1"] = "tc1 <cmd> ...        TC08 unit 1 (attach/read/write/verify/index)",
            ["break"] = "break <addr>         Toggle breakpoint",
            ["breaks"] = "breaks              List breakpoints",
            ["dis"] = "dis <addr> [n]       Disassemble n words from addr",
            ["sample"] = "sample               Load a small counting demo at 0200",
            ["asm"] = "asm <file> [addr]    Assemble file and load into memory",
            ["asm -l"] = "asm -l <file>        Print assembler listing",
            ["tty"] = "tty read <file>      Queue input bytes for console TTI",
            ["ptr"] = "ptr read <file>      Queue input bytes for paper tape reader",
            ["ptp"] = "ptp attach <file>    Set output file for paper tape punch",
            ["lpt"] = "lpt status           Show line printer output path",
            ["wdt"] = "wdt <cmd> [args]     Configure watchdog timer",
            ["exit"] = "exit                 Quit the monitor"
        };
    }

    private static string FormatDeviceCode(int deviceCode)
    {
        return Convert.ToString(deviceCode & 0x3F, 8).PadLeft(2, '0');
    }

    private static string DescribeDevice(int deviceCode, INovaIoDevice device)
    {
        return deviceCode switch
        {
            8 => "TTI (console input)",
            9 => "TTO (console output)",
            10 => "PTR (paper tape reader)",
            11 => "PTP (paper tape punch)",
            12 => "LPT (line printer)",
            _ => device switch
            {
                NovaWatchdogDevice => "WDT watchdog",
                NovaTc08Device => "TC08 tape",
                NovaRtcDevice => "RTC clock",
                _ => device.GetType().Name
            }
        };
    }

    private static bool TryParseOnOff(string text, out bool value)
    {
        if (text.Equals("on", StringComparison.OrdinalIgnoreCase) ||
            text.Equals("true", StringComparison.OrdinalIgnoreCase) ||
            text.Equals("1", StringComparison.OrdinalIgnoreCase))
        {
            value = true;
            return true;
        }

        if (text.Equals("off", StringComparison.OrdinalIgnoreCase) ||
            text.Equals("false", StringComparison.OrdinalIgnoreCase) ||
            text.Equals("0", StringComparison.OrdinalIgnoreCase))
        {
            value = false;
            return true;
        }

        value = false;
        return false;
    }

    private static bool TryParseAction(string text, out NovaWatchdogAction action)
    {
        if (text.Equals("none", StringComparison.OrdinalIgnoreCase))
        {
            action = NovaWatchdogAction.None;
            return true;
        }

        if (text.Equals("interrupt", StringComparison.OrdinalIgnoreCase))
        {
            action = NovaWatchdogAction.Interrupt;
            return true;
        }

        if (text.Equals("halt", StringComparison.OrdinalIgnoreCase))
        {
            action = NovaWatchdogAction.Halt;
            return true;
        }

        if (text.Equals("reset", StringComparison.OrdinalIgnoreCase))
        {
            action = NovaWatchdogAction.Reset;
            return true;
        }

        action = NovaWatchdogAction.None;
        return false;
    }

    private static bool TryParseMs(string text, out int value)
    {
        text = text.Trim();
        int radix;
        if (text.StartsWith("0x", StringComparison.OrdinalIgnoreCase))
        {
            radix = 16;
            text = text[2..];
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
            radix = 10;
        }

        try
        {
            var parsed = Convert.ToInt32(text, radix);
            value = parsed;
            return parsed >= 0 && parsed <= 0xFFFF;
        }
        catch
        {
            value = 0;
            return false;
        }
    }


    private static string ComputeMd5(string path)
    {
        using var stream = File.OpenRead(path);
        var hash = MD5.HashData(stream);
        return Convert.ToHexString(hash).ToLowerInvariant();
    }
}
