using System.IO;
using System.Text;

namespace Snova;

public sealed class NovaAssembler
{
    public AssemblerResult Assemble(string source)
    {
        var result = new AssemblerResult();
        var symbols = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase)
        {
            ["TTI"] = 8,
            ["TTO"] = 9
        };
        var items = new List<AsmItem>();
        var location = 0;
        var lines = source.Replace("\r\n", "\n").Replace('\r', '\n').Split('\n');

        for (var lineIndex = 0; lineIndex < lines.Length; lineIndex++)
        {
            var lineNumber = lineIndex + 1;
            var text = StripComment(lines[lineIndex]).Trim();
            if (string.IsNullOrWhiteSpace(text))
            {
                continue;
            }

            var labelSplit = SplitLabel(text);
            if (labelSplit.Label is not null)
            {
                if (!IsValidLabel(labelSplit.Label))
                {
                    result.Diagnostics.Add(new AssemblerDiagnostic(lineNumber, $"Invalid label '{labelSplit.Label}'."));
                }
                else if (!symbols.TryAdd(labelSplit.Label, location))
                {
                    result.Diagnostics.Add(new AssemblerDiagnostic(lineNumber, $"Duplicate label '{labelSplit.Label}'."));
                }
            }

            text = labelSplit.Remainder;
            if (string.IsNullOrWhiteSpace(text))
            {
                continue;
            }

            if (TryParseTextDirective(text, out var textLiteral, out var textError, out var isText))
            {
                if (isText)
                {
                    if (!string.IsNullOrEmpty(textError))
                    {
                        result.Diagnostics.Add(new AssemblerDiagnostic(lineNumber, textError));
                    }
                    else
                    {
                        items.Add(new AsmItem(AsmItemKind.Text, lineNumber, location, ".TXT", new[] { textLiteral }));
                        location += textLiteral.Length;
                    }

                    continue;
                }
            }

            var tokens = Tokenize(text);
            if (tokens.Count == 0)
            {
                continue;
            }

            var op = tokens[0];
            if (IsDirective(op, "org"))
            {
                if (tokens.Count < 2)
                {
                    result.Diagnostics.Add(new AssemblerDiagnostic(lineNumber, "ORG requires an address expression."));
                    continue;
                }

                if (!TryEvaluateExpression(tokens[1], symbols, out var orgValue, out var orgError))
                {
                    result.Diagnostics.Add(new AssemblerDiagnostic(lineNumber, orgError));
                    continue;
                }

                location = orgValue & NovaCpu.AddressMask;
                continue;
            }

            if (IsDirective(op, "word") || IsDirective(op, "dw"))
            {
                if (tokens.Count < 2)
                {
                    result.Diagnostics.Add(new AssemblerDiagnostic(lineNumber, "DW requires at least one value."));
                    continue;
                }

                var operands = tokens.Skip(1).ToArray();
                items.Add(new AsmItem(AsmItemKind.Word, lineNumber, location, op, operands));
                location += operands.Length;
                continue;
            }

            items.Add(new AsmItem(AsmItemKind.Instruction, lineNumber, location, op, tokens.Skip(1).ToArray()));
            location++;
        }

        foreach (var item in items)
        {
            if (item.Kind == AsmItemKind.Word)
            {
                for (var i = 0; i < item.Operands.Length; i++)
                {
                    if (!TryEvaluateExpression(item.Operands[i], symbols, out var value, out var error))
                    {
                        result.Diagnostics.Add(new AssemblerDiagnostic(item.LineNumber, error));
                        continue;
                    }

                    var addr = (ushort)((item.Address + i) & NovaCpu.AddressMask);
                    var word = (ushort)(value & NovaCpu.WordMask);
                    result.Words.Add(new AssembledWord(addr, word, item.LineNumber));
                }

                continue;
            }

            if (item.Kind == AsmItemKind.Text)
            {
                var text = item.Operands.Length > 0 ? item.Operands[0] : string.Empty;
                for (var i = 0; i < text.Length; i++)
                {
                    var ch = text[i];
                    if (ch > 0x7F)
                    {
                        result.Diagnostics.Add(new AssemblerDiagnostic(item.LineNumber, "TXT supports ASCII characters only."));
                        ch = '?';
                    }

                    var addr = (ushort)((item.Address + i) & NovaCpu.AddressMask);
                    var word = (ushort)(ch & 0xFF);
                    result.Words.Add(new AssembledWord(addr, word, item.LineNumber));
                }

                continue;
            }

            if (!TryAssembleInstruction(item, symbols, out var instruction, out var instError))
            {
                result.Diagnostics.Add(new AssemblerDiagnostic(item.LineNumber, instError));
                continue;
            }

            result.Words.Add(new AssembledWord((ushort)item.Address, instruction, item.LineNumber));
        }

        if (result.Words.Count > 0)
        {
            result.StartAddress = result.Words.Min(w => w.Address);
        }

        return result;
    }

    public AssemblerResult AssembleFile(string path)
    {
        var source = File.ReadAllText(path, Encoding.ASCII);
        return Assemble(source);
    }

    private static bool TryAssembleInstruction(
        AsmItem item,
        Dictionary<string, int> symbols,
        out ushort instruction,
        out string error)
    {
        instruction = 0;
        error = string.Empty;
        var mnemonic = item.Mnemonic.ToUpperInvariant();
        var operands = item.Operands;
        var pc = item.Address;

        if (mnemonic.StartsWith("NIO", StringComparison.OrdinalIgnoreCase))
        {
            return AssembleNio(item, symbols, out instruction, out error);
        }

        switch (mnemonic)
        {
            case "NOP":
                if (operands.Length != 0)
                {
                    error = "NOP takes no operands.";
                    return false;
                }

                instruction = EncodeInstruction(Instruction.Nop, 0);
                return true;
            case "HALT":
                if (operands.Length != 0)
                {
                    error = "HALT takes no operands.";
                    return false;
                }

                instruction = EncodeInstruction(Instruction.Halt, 0);
                return true;
            case "LDA":
                return AssembleMemory(Instruction.Load, item, symbols, pc, out instruction, out error);
            case "STA":
                return AssembleMemory(Instruction.Store, item, symbols, pc, out instruction, out error);
            case "ADD":
                return AssembleMemory(Instruction.Add, item, symbols, pc, out instruction, out error);
            case "SUB":
                return AssembleMemory(Instruction.Subtract, item, symbols, pc, out instruction, out error);
            case "AND":
                return AssembleMemory(Instruction.And, item, symbols, pc, out instruction, out error);
            case "OR":
                return AssembleMemory(Instruction.Or, item, symbols, pc, out instruction, out error);
            case "XOR":
                return AssembleMemory(Instruction.Xor, item, symbols, pc, out instruction, out error);
            case "BR":
                return AssembleBranch(Instruction.Branch, item, symbols, pc, out instruction, out error);
            case "BZ":
                return AssembleBranch(Instruction.ConditionalBranch, item, symbols, pc, out instruction, out error, branchOnZero: true);
            case "BNZ":
                return AssembleBranch(Instruction.ConditionalBranch, item, symbols, pc, out instruction, out error, branchOnZero: false);
            case "JSR":
                return AssembleMemory(Instruction.JumpToSubroutine, item, symbols, pc, out instruction, out error);
            case "ISZ":
                return AssembleIncSkip(item, symbols, pc, out instruction, out error);
            case "LDAI":
                return AssembleImmediate(Instruction.LoadImmediate, item, symbols, out instruction, out error);
            case "ADDI":
                return AssembleImmediate(Instruction.AddImmediate, item, symbols, out instruction, out error, allowSigned: true);
            case "SHL":
                return AssembleShift(item, symbols, out instruction, out error, right: false, throughLink: false);
            case "SHLL":
                return AssembleShift(item, symbols, out instruction, out error, right: false, throughLink: true);
            case "SHR":
                return AssembleShift(item, symbols, out instruction, out error, right: true, throughLink: false);
            case "SHRL":
                return AssembleShift(item, symbols, out instruction, out error, right: true, throughLink: true);
            case "DIA":
                return AssembleIoData(NovaIoOpKind.DIA, item, symbols, out instruction, out error);
            case "DOA":
                return AssembleIoData(NovaIoOpKind.DOA, item, symbols, out instruction, out error);
            case "DIB":
                return AssembleIoData(NovaIoOpKind.DIB, item, symbols, out instruction, out error);
            case "DOB":
                return AssembleIoData(NovaIoOpKind.DOB, item, symbols, out instruction, out error);
            case "DIC":
                return AssembleIoData(NovaIoOpKind.DIC, item, symbols, out instruction, out error);
            case "DOC":
                return AssembleIoData(NovaIoOpKind.DOC, item, symbols, out instruction, out error);
            case "SKPBN":
                return AssembleIoSkip(NovaIoOpKind.SKPBN, item, symbols, out instruction, out error);
            case "SKPBZ":
                return AssembleIoSkip(NovaIoOpKind.SKPBZ, item, symbols, out instruction, out error);
            case "SKPDN":
                return AssembleIoSkip(NovaIoOpKind.SKPDN, item, symbols, out instruction, out error);
            case "SKPDZ":
                return AssembleIoSkip(NovaIoOpKind.SKPDZ, item, symbols, out instruction, out error);
            default:
                error = $"Unknown mnemonic '{item.Mnemonic}'.";
                return false;
        }
    }

    private static bool AssembleImmediate(
        Instruction opcode,
        AsmItem item,
        Dictionary<string, int> symbols,
        out ushort instruction,
        out string error,
        bool allowSigned = false)
    {
        instruction = 0;
        error = string.Empty;
        if (item.Operands.Length != 2)
        {
            error = $"{item.Mnemonic} expects AC and immediate value.";
            return false;
        }

        if (!TryParseAc(item.Operands[0], out var ac))
        {
            error = $"Invalid accumulator '{item.Operands[0]}'.";
            return false;
        }

        if (!TryEvaluateExpression(item.Operands[1], symbols, out var value, out var valueError))
        {
            error = valueError;
            return false;
        }

        if (allowSigned)
        {
            if (value < -128 || value > 255)
            {
                error = $"{item.Mnemonic} immediate out of range (-128..255).";
                return false;
            }
        }
        else if (value < 0 || value > 255)
        {
            error = $"{item.Mnemonic} immediate out of range (0..255).";
            return false;
        }

        instruction = EncodeImmediate(opcode, ac, value & 0xFF);
        return true;
    }

    private static bool AssembleShift(
        AsmItem item,
        Dictionary<string, int> symbols,
        out ushort instruction,
        out string error,
        bool right,
        bool throughLink)
    {
        instruction = 0;
        error = string.Empty;
        if (item.Operands.Length != 2)
        {
            error = $"{item.Mnemonic} expects AC and count.";
            return false;
        }

        if (!TryParseAc(item.Operands[0], out var ac))
        {
            error = $"Invalid accumulator '{item.Operands[0]}'.";
            return false;
        }

        if (!TryEvaluateExpression(item.Operands[1], symbols, out var count, out var countError))
        {
            error = countError;
            return false;
        }

        if (count < 0 || count > 15)
        {
            error = "Shift count must be 0..15.";
            return false;
        }

        var offset = count & 0xF;
        if (right)
        {
            offset |= 0x10;
        }

        if (throughLink)
        {
            offset |= 0x20;
        }

        instruction = EncodeImmediate(Instruction.Shift, ac, offset);
        return true;
    }

    private static bool AssembleBranch(
        Instruction opcode,
        AsmItem item,
        Dictionary<string, int> symbols,
        int pc,
        out ushort instruction,
        out string error,
        bool branchOnZero = true)
    {
        instruction = 0;
        error = string.Empty;
        if (opcode == Instruction.Branch && item.Operands.Length != 1)
        {
            error = "BR expects a single target.";
            return false;
        }

        if (item.Operands.Length != 1 && item.Operands.Length != 2)
        {
            error = $"{item.Mnemonic} expects target (and optional AC).";
            return false;
        }

        var ac = 0;
        var operandIndex = 0;
        if (item.Operands.Length == 2)
        {
            if (!TryParseAc(item.Operands[0], out ac))
            {
                error = $"Invalid accumulator '{item.Operands[0]}'.";
                return false;
            }

            operandIndex = 1;
        }

        if (!TryParseEffective(item.Operands[operandIndex], symbols, pc, out var ea, out error))
        {
            return false;
        }

        if (opcode == Instruction.ConditionalBranch)
        {
            if (ea.Indirect)
            {
                error = "Conditional branches cannot use indirect addressing.";
                return false;
            }

            instruction = EncodeInstruction(opcode, ac, indirect: !branchOnZero, page: ea.Page, offset: ea.Offset);
            return true;
        }

        instruction = EncodeInstruction(opcode, ac, ea.Indirect, ea.Page, ea.Offset);
        return true;
    }

    private static bool AssembleIncSkip(
        AsmItem item,
        Dictionary<string, int> symbols,
        int pc,
        out ushort instruction,
        out string error)
    {
        instruction = 0;
        error = string.Empty;
        if (item.Operands.Length != 1 && item.Operands.Length != 2)
        {
            error = "ISZ expects address (and optional AC).";
            return false;
        }

        var ac = 0;
        var operandIndex = 0;
        if (item.Operands.Length == 2)
        {
            if (!TryParseAc(item.Operands[0], out ac))
            {
                error = $"Invalid accumulator '{item.Operands[0]}'.";
                return false;
            }

            operandIndex = 1;
        }

        if (!TryParseEffective(item.Operands[operandIndex], symbols, pc, out var ea, out error))
        {
            return false;
        }

        instruction = EncodeInstruction(Instruction.IncSkip, ac, ea.Indirect, ea.Page, ea.Offset);
        return true;
    }

    private static bool AssembleNio(
        AsmItem item,
        Dictionary<string, int> symbols,
        out ushort instruction,
        out string error)
    {
        instruction = 0;
        error = string.Empty;
        if (!TryParseSignal(item.Mnemonic, out var start, out var clear, out var pulse, out error))
        {
            return false;
        }

        if (item.Operands.Length != 1)
        {
            error = "NIO expects a single device code.";
            return false;
        }

        if (!TryParseDevice(item.Operands[0], symbols, out var device, out error))
        {
            return false;
        }

        instruction = EncodeIo(NovaIoOpKind.NIO, 0, device, start, clear, pulse);
        return true;
    }

    private static bool AssembleIoData(
        NovaIoOpKind kind,
        AsmItem item,
        Dictionary<string, int> symbols,
        out ushort instruction,
        out string error)
    {
        instruction = 0;
        error = string.Empty;
        if (item.Operands.Length != 1 && item.Operands.Length != 2)
        {
            error = $"{item.Mnemonic} expects device (and optional AC).";
            return false;
        }

        var ac = 0;
        var operandIndex = 0;
        if (item.Operands.Length == 2)
        {
            if (!TryParseAc(item.Operands[0], out ac))
            {
                error = $"Invalid accumulator '{item.Operands[0]}'.";
                return false;
            }

            operandIndex = 1;
        }

        if (!TryParseDevice(item.Operands[operandIndex], symbols, out var device, out error))
        {
            return false;
        }

        instruction = EncodeIo(kind, ac, device, start: false, clear: false, pulse: false);
        return true;
    }

    private static bool AssembleIoSkip(
        NovaIoOpKind kind,
        AsmItem item,
        Dictionary<string, int> symbols,
        out ushort instruction,
        out string error)
    {
        instruction = 0;
        error = string.Empty;
        if (item.Operands.Length != 1)
        {
            error = $"{item.Mnemonic} expects a device code.";
            return false;
        }

        if (!TryParseDevice(item.Operands[0], symbols, out var device, out error))
        {
            return false;
        }

        instruction = EncodeIo(kind, 0, device, start: false, clear: false, pulse: false);
        return true;
    }

    private static bool AssembleMemory(
        Instruction opcode,
        AsmItem item,
        Dictionary<string, int> symbols,
        int pc,
        out ushort instruction,
        out string error)
    {
        instruction = 0;
        error = string.Empty;
        if (item.Operands.Length != 2)
        {
            error = $"{item.Mnemonic} expects AC and address.";
            return false;
        }

        if (!TryParseAc(item.Operands[0], out var ac))
        {
            error = $"Invalid accumulator '{item.Operands[0]}'.";
            return false;
        }

        if (!TryParseEffective(item.Operands[1], symbols, pc, out var ea, out error))
        {
            return false;
        }

        instruction = EncodeInstruction(opcode, ac, ea.Indirect, ea.Page, ea.Offset);
        return true;
    }

    private static bool TryParseEffective(
        string operand,
        Dictionary<string, int> symbols,
        int pc,
        out EffectiveAddress ea,
        out string error)
    {
        ea = default;
        error = string.Empty;

        var text = operand.Trim();
        var indirect = false;
        if (text.StartsWith("@", StringComparison.Ordinal))
        {
            indirect = true;
            text = text[1..].Trim();
        }

        var pageExplicit = false;
        var page = false;
        if (text.StartsWith("P:", StringComparison.OrdinalIgnoreCase))
        {
            pageExplicit = true;
            page = true;
            text = text[2..].Trim();
        }

        if (!TryEvaluateExpression(text, symbols, out var address, out var addressError))
        {
            error = addressError;
            return false;
        }

        address &= NovaCpu.AddressMask;
        var pageBase = (pc + 1) & NovaCpu.PageMask;
        if (pageExplicit)
        {
            if ((address & NovaCpu.PageMask) != pageBase)
            {
                error = $"Address {FormatOctal(address)} is not on the current page.";
                return false;
            }
        }
        else if (address <= 0xFF)
        {
            page = false;
        }
        else if ((address & NovaCpu.PageMask) == pageBase)
        {
            page = true;
        }
        else
        {
            error = $"Address {FormatOctal(address)} not reachable without P: prefix.";
            return false;
        }

        ea = new EffectiveAddress(indirect, page, address & 0xFF);
        return true;
    }

    private static ushort EncodeInstruction(Instruction opcode, int accumulator, bool indirect = false, bool page = false, int offset = 0)
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

    private static ushort EncodeImmediate(Instruction opcode, int accumulator, int value)
    {
        return (ushort)(((int)opcode << 12) | (accumulator << 10) | (value & 0xFF));
    }

    private static ushort EncodeIo(
        NovaIoOpKind kind,
        int accumulator,
        int device,
        bool start,
        bool clear,
        bool pulse)
    {
        var signal = 0;
        if (start) signal = 1;
        else if (clear) signal = 2;
        else if (pulse) signal = 3;

        var function = kind switch
        {
            NovaIoOpKind.NIO => 0,
            NovaIoOpKind.DIA => 1,
            NovaIoOpKind.DOA => 2,
            NovaIoOpKind.DIB => 3,
            NovaIoOpKind.DOB => 4,
            NovaIoOpKind.DIC => 5,
            NovaIoOpKind.DOC => 6,
            _ => 7
        };

        var ac = kind switch
        {
            NovaIoOpKind.SKPBN => 0,
            NovaIoOpKind.SKPBZ => 1,
            NovaIoOpKind.SKPDN => 2,
            NovaIoOpKind.SKPDZ => 3,
            _ => accumulator & 0x3
        };

        var word = 0x6000 | (signal << 11) | (function << 8) | (ac << 6) | (device & 0x3F);
        return (ushort)word;
    }

    private static bool TryParseAc(string token, out int ac)
    {
        ac = 0;
        var text = token.Trim().ToUpperInvariant();
        if (text.StartsWith("AC", StringComparison.Ordinal))
        {
            text = text[2..];
        }

        return int.TryParse(text, out ac) && ac >= 0 && ac <= 3;
    }

    private static string StripComment(string line)
    {
        var semi = line.IndexOf(';');
        var slash = line.IndexOf("//", StringComparison.Ordinal);
        var cut = semi >= 0 && slash >= 0 ? Math.Min(semi, slash) : Math.Max(semi, slash);
        return cut >= 0 ? line[..cut] : line;
    }

    private static LabelSplit SplitLabel(string line)
    {
        var colonIndex = line.IndexOf(':');
        if (colonIndex <= 0)
        {
            return new LabelSplit(null, line);
        }

        var label = line[..colonIndex].Trim();
        var remainder = line[(colonIndex + 1)..].Trim();
        return new LabelSplit(label, remainder);
    }

    private static bool IsValidLabel(string label)
    {
        if (string.IsNullOrWhiteSpace(label))
        {
            return false;
        }

        if (!char.IsLetter(label[0]) && label[0] != '_')
        {
            return false;
        }

        return label.All(ch => char.IsLetterOrDigit(ch) || ch == '_');
    }

    private static bool IsDirective(string token, string directive)
    {
        var text = token.Trim();
        if (text.StartsWith(".", StringComparison.Ordinal))
        {
            text = text[1..];
        }

        return text.Equals(directive, StringComparison.OrdinalIgnoreCase);
    }

    private static List<string> Tokenize(string line)
    {
        var tokens = new List<string>();
        var current = new StringBuilder();
        foreach (var ch in line)
        {
            if (char.IsWhiteSpace(ch) || ch == ',')
            {
                if (current.Length > 0)
                {
                    tokens.Add(current.ToString());
                    current.Clear();
                }
            }
            else
            {
                current.Append(ch);
            }
        }

        if (current.Length > 0)
        {
            tokens.Add(current.ToString());
        }

        return tokens;
    }

    private static bool TryParseTextDirective(
        string line,
        out string text,
        out string error,
        out bool isTextDirective)
    {
        text = string.Empty;
        error = string.Empty;
        isTextDirective = false;
        if (string.IsNullOrWhiteSpace(line))
        {
            return true;
        }

        var trimmed = line.Trim();
        var tokenEnd = 0;
        while (tokenEnd < trimmed.Length && !char.IsWhiteSpace(trimmed[tokenEnd]))
        {
            tokenEnd++;
        }

        var token = trimmed[..tokenEnd];
        if (!IsDirective(token, "txt"))
        {
            return true;
        }

        isTextDirective = true;
        var rest = trimmed[tokenEnd..].Trim();
        if (string.IsNullOrEmpty(rest))
        {
            error = "TXT requires /string/.";
            return true;
        }

        var firstSlash = rest.IndexOf('/');
        if (firstSlash < 0)
        {
            error = "TXT requires /string/.";
            return true;
        }

        var lastSlash = rest.LastIndexOf('/');
        if (lastSlash == firstSlash)
        {
            error = "TXT requires a closing '/'.";
            return true;
        }

        if (!string.IsNullOrWhiteSpace(rest[..firstSlash]))
        {
            error = "TXT expects /string/.";
            return true;
        }

        if (!string.IsNullOrWhiteSpace(rest[(lastSlash + 1)..]))
        {
            error = "TXT supports only a single /string/.";
            return true;
        }

        text = rest.Substring(firstSlash + 1, lastSlash - firstSlash - 1);
        return true;
    }

    private static bool TryEvaluateExpression(
        string expr,
        Dictionary<string, int> symbols,
        out int value,
        out string error)
    {
        value = 0;
        error = string.Empty;
        if (string.IsNullOrWhiteSpace(expr))
        {
            error = "Missing expression.";
            return false;
        }

        var index = 0;
        var total = 0;
        var sign = 1;
        var sawTerm = false;
        while (index < expr.Length)
        {
            var ch = expr[index];
            if (ch == '+')
            {
                sign = 1;
                index++;
                continue;
            }
            if (ch == '-')
            {
                sign = -1;
                index++;
                continue;
            }

            var start = index;
            while (index < expr.Length && expr[index] != '+' && expr[index] != '-')
            {
                index++;
            }

            var term = expr[start..index].Trim();
            if (term.Length == 0)
            {
                error = $"Invalid expression '{expr}'.";
                return false;
            }

            if (TryParseNumber(term, out var number))
            {
                total += sign * number;
                sign = 1;
                sawTerm = true;
                continue;
            }

            if (!IsValidLabel(term))
            {
                error = $"Invalid symbol '{term}'.";
                return false;
            }

            if (!symbols.TryGetValue(term, out var symbolValue))
            {
                error = $"Undefined symbol '{term}'.";
                return false;
            }

            total += sign * symbolValue;
            sign = 1;
            sawTerm = true;
        }

        if (!sawTerm)
        {
            error = $"Invalid expression '{expr}'.";
            return false;
        }

        value = total;
        return true;
    }

    private static bool TryParseNumber(string text, out int value)
    {
        value = 0;
        text = text.Trim();
        if (text.Length == 0)
        {
            return false;
        }

        var sign = 1;
        if (text[0] == '+')
        {
            text = text[1..];
        }
        else if (text[0] == '-')
        {
            sign = -1;
            text = text[1..];
        }

        if (text.StartsWith("0x", StringComparison.OrdinalIgnoreCase))
        {
            if (int.TryParse(text[2..], System.Globalization.NumberStyles.HexNumber, null, out var parsed))
            {
                value = sign * parsed;
                return true;
            }

            return false;
        }

        var radix = 8;
        if (text.StartsWith("0o", StringComparison.OrdinalIgnoreCase))
        {
            text = text[2..];
            radix = 8;
        }
        else if (text.StartsWith("0b", StringComparison.OrdinalIgnoreCase))
        {
            text = text[2..];
            radix = 2;
        }

        try
        {
            value = sign * Convert.ToInt32(text, radix);
            return true;
        }
        catch
        {
            return false;
        }
    }

    private static bool TryParseDevice(
        string token,
        Dictionary<string, int> symbols,
        out int device,
        out string error)
    {
        if (!TryEvaluateExpression(token, symbols, out var value, out error))
        {
            device = 0;
            return false;
        }

        if (value < 0 || value > 0x3F)
        {
            error = "Device code must be 0..63.";
            device = 0;
            return false;
        }

        device = value;
        return true;
    }

    private static bool TryParseSignal(
        string mnemonic,
        out bool start,
        out bool clear,
        out bool pulse,
        out string error)
    {
        start = false;
        clear = false;
        pulse = false;
        error = string.Empty;
        var text = mnemonic.Trim();
        var suffixIndex = text.IndexOf('.', StringComparison.Ordinal);
        if (suffixIndex < 0)
        {
            return true;
        }

        var suffix = text[(suffixIndex + 1)..].ToUpperInvariant();
        foreach (var ch in suffix)
        {
            switch (ch)
            {
                case 'S':
                    start = true;
                    break;
                case 'C':
                    clear = true;
                    break;
                case 'P':
                    pulse = true;
                    break;
                default:
                    error = $"Invalid NIO signal '{ch}'.";
                    return false;
            }
        }

        var count = (start ? 1 : 0) + (clear ? 1 : 0) + (pulse ? 1 : 0);
        if (count > 1)
        {
            error = "NIO supports only one of S, C, or P.";
            return false;
        }

        return true;
    }

    private static string FormatOctal(int value) => Convert.ToString(value & NovaCpu.WordMask, 8).PadLeft(6, '0');

    private readonly record struct LabelSplit(string? Label, string Remainder);

    private readonly record struct AsmItem(AsmItemKind Kind, int LineNumber, int Address, string Mnemonic, string[] Operands);

    private readonly record struct EffectiveAddress(bool Indirect, bool Page, int Offset);
}

public sealed class AssemblerResult
{
    public List<AssemblerDiagnostic> Diagnostics { get; } = new();
    public List<AssembledWord> Words { get; } = new();
    public ushort? StartAddress { get; set; }
    public bool Success => Diagnostics.Count == 0;
}

public readonly record struct AssembledWord(ushort Address, ushort Value, int LineNumber);

public readonly record struct AssemblerDiagnostic(int LineNumber, string Message);

internal enum AsmItemKind
{
    Word,
    Text,
    Instruction
}
