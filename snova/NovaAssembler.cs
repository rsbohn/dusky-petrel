using System.IO;
using System.Linq;
using System.Text;

namespace Snova;

public sealed class NovaAssembler
{
    private const int SimhDisplacementMask = 0xFF;
    private const int SimhDispSign = 0x80;
    private const int SimhDispRange = 0x100;
    private const int SimhModePc = 1;

    private const int SimhOpShiftSrc = 13;
    private const int SimhOpShiftDst = 11;
    private const int SimhOpShiftMode = 8;
    private const int SimhOpShiftIndirect = 10;

    private static readonly IReadOnlyDictionary<string, SimhOpcodeEntry> SimhOpcodeLookup =
        BuildSimhOpcodeLookup();

    private static readonly IReadOnlyDictionary<string, int> SimhDeviceSymbols =
        new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase)
        {
            ["TTI"] = 8, // 0o10
            ["TTO"] = 9, // 0o11
            ["PTR"] = 10, // 0o12
            ["PTP"] = 11, // 0o13
            ["RTC"] = 12, // 0o14
            ["PLT"] = 13, // 0o15
            ["CDR"] = 14, // 0o16
            ["LPT"] = 15, // 0o17
            ["DSK"] = 16, // 0o20
            ["MTA"] = 18, // 0o22
            ["DCM"] = 20, // 0o24
            ["QTY"] = 24, // 0o30
            ["ADCV"] = 24, // 0o30
            ["DKP"] = 27, // 0o33
            ["CAS"] = 28, // 0o34
            ["TTI1"] = 40, // 0o50
            ["TTO1"] = 41, // 0o51
            ["CPU"] = 63, // 0o77
        };

    public AssemblerResult Assemble(string source)
    {
        var result = new AssemblerResult();
        var symbols = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase)
        {
            ["TTI"] = 8,
            ["TTO"] = 9
        };
        foreach (var (name, value) in SimhDeviceSymbols)
        {
            symbols[name] = value;
        }

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
                    result.Diagnostics.Add(new AssemblerDiagnostic(lineNumber, DiagnosticSeverity.Error, $"Invalid label '{labelSplit.Label}'."));
                }
                else if (!symbols.TryAdd(labelSplit.Label, location))
                {
                    var existingValue = symbols[labelSplit.Label];
                    result.Diagnostics.Add(new AssemblerDiagnostic(
                        lineNumber,
                        DiagnosticSeverity.Warning,
                        $"Symbol '{labelSplit.Label}' already defined as {FormatOctal(existingValue)}; keeping original value."));
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
                        result.Diagnostics.Add(new AssemblerDiagnostic(lineNumber, DiagnosticSeverity.Error, textError));
                    }
                    else
                    {
                        items.Add(new AsmItem(AsmItemKind.Text, lineNumber, location, ".TXT", new[] { textLiteral }, textLiteral.Length));
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
                    result.Diagnostics.Add(new AssemblerDiagnostic(lineNumber, DiagnosticSeverity.Error, "ORG requires an address expression."));
                    continue;
                }

                if (!TryEvaluateExpression(tokens[1], symbols, out var orgValue, out var orgError))
                {
                    result.Diagnostics.Add(new AssemblerDiagnostic(lineNumber, DiagnosticSeverity.Error, orgError));
                    continue;
                }

                location = orgValue & NovaCpu.AddressMask;
                continue;
            }

            if (IsDirective(op, "word") || IsDirective(op, "dw"))
            {
                if (tokens.Count < 2)
                {
                    result.Diagnostics.Add(new AssemblerDiagnostic(lineNumber, DiagnosticSeverity.Error, "DW requires at least one value."));
                    continue;
                }

                var operands = SplitCommaOperands(tokens.Skip(1));
                items.Add(new AsmItem(AsmItemKind.Word, lineNumber, location, op, operands, operands.Length));
                location += operands.Length;
                continue;
            }

            var instructionOperands = tokens.Skip(1).ToArray();
            var wordCount = GetInstructionWordCount(op);
            items.Add(new AsmItem(AsmItemKind.Instruction, lineNumber, location, op, instructionOperands, wordCount));
            location += wordCount;
        }

        foreach (var item in items)
        {
            if (item.Kind == AsmItemKind.Word)
            {
                for (var i = 0; i < item.Operands.Length; i++)
                {
                    if (!TryEvaluateExpression(item.Operands[i], symbols, out var value, out var error))
                    {
                        result.Diagnostics.Add(new AssemblerDiagnostic(item.LineNumber, DiagnosticSeverity.Error, error));
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
                        result.Diagnostics.Add(new AssemblerDiagnostic(item.LineNumber, DiagnosticSeverity.Error, "TXT supports ASCII characters only."));
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
                result.Diagnostics.Add(new AssemblerDiagnostic(item.LineNumber, DiagnosticSeverity.Error, instError));
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
        return TryAssembleSimhInstruction(item, symbols, out instruction, out error);
    }

    private static bool TryAssembleSimhInstruction(
        AsmItem item,
        Dictionary<string, int> symbols,
        out ushort instruction,
        out string error)
    {
        instruction = 0;
        error = string.Empty;
        var mnemonic = item.Mnemonic.Trim().ToUpperInvariant();
        var operandText = string.Join(" ", item.Operands).Trim();

        if (mnemonic == "NOP")
        {
            if (!string.IsNullOrWhiteSpace(operandText))
            {
                error = "NOP takes no operands.";
                return false;
            }

            instruction = 33280; // 0o0101000
            return true;
        }

        if (!SimhOpcodeLookup.TryGetValue(mnemonic, out var entry))
        {
            error = $"Unknown mnemonic '{item.Mnemonic}'.";
            return false;
        }

        switch (entry.Class)
        {
            case SimhOperandClass.NPN:
                if (!string.IsNullOrWhiteSpace(operandText))
                {
                    error = $"{item.Mnemonic} takes no operands.";
                    return false;
                }
                instruction = (ushort)entry.BaseWord;
                return true;
            case SimhOperandClass.R:
                if (!TryParseRegisterOperand(operandText, out var reg, out error))
                {
                    return false;
                }
                instruction = (ushort)(entry.BaseWord | (reg << SimhOpShiftDst));
                return true;
            case SimhOperandClass.D:
                if (!TryParseDeviceOperand(operandText, symbols, out var device, out error))
                {
                    return false;
                }
                instruction = (ushort)(entry.BaseWord | (device & 0x3F));
                return true;
            case SimhOperandClass.RD:
                if (!TryParseRegDeviceOperands(operandText, symbols, out var rdReg, out var rdDevice, out error))
                {
                    return false;
                }
                instruction = (ushort)(entry.BaseWord | (rdReg << SimhOpShiftDst) | (rdDevice & 0x3F));
                return true;
            case SimhOperandClass.M:
                if (!TryParseSimhAddressOperand(operandText, symbols, item.Address, out var ea, out error))
                {
                    return false;
                }
                instruction = (ushort)(entry.BaseWord | (ea.Indirect ? (1 << SimhOpShiftIndirect) : 0)
                    | (ea.Mode << SimhOpShiftMode) | ea.Displacement);
                return true;
            case SimhOperandClass.RM:
                if (!TryParseRegAddressOperands(operandText, symbols, item.Address, out var rmReg, out ea, out error))
                {
                    return false;
                }
                instruction = (ushort)(entry.BaseWord | (rmReg << SimhOpShiftDst)
                    | (ea.Indirect ? (1 << SimhOpShiftIndirect) : 0)
                    | (ea.Mode << SimhOpShiftMode) | ea.Displacement);
                return true;
            case SimhOperandClass.RR:
                if (!TryParseOperateOperands(operandText, out var srcReg, out var dstReg, out var skipCode, out error))
                {
                    return false;
                }
                instruction = (ushort)(entry.BaseWord | (srcReg << SimhOpShiftSrc) | (dstReg << SimhOpShiftDst) | skipCode);
                return true;
            case SimhOperandClass.BY:
                if (!TryParseByteOperands(operandText, out var byReg, out var byDst, out error))
                {
                    return false;
                }
                instruction = (ushort)(entry.BaseWord | (byReg << 6) | (byDst << SimhOpShiftDst));
                return true;
            default:
                error = $"Mnemonic '{item.Mnemonic}' is not supported by this assembler.";
                return false;
        }
    }

    private static bool TryParseRegisterOperand(string operandText, out int reg, out string error)
    {
        reg = 0;
        error = string.Empty;
        if (string.IsNullOrWhiteSpace(operandText))
        {
            error = "Missing register operand.";
            return false;
        }

        if (!TryParseRegister(operandText, out reg))
        {
            error = $"Invalid register '{operandText}'.";
            return false;
        }

        return true;
    }

    private static bool TryParseRegDeviceOperands(
        string operandText,
        Dictionary<string, int> symbols,
        out int reg,
        out int device,
        out string error)
    {
        reg = 0;
        device = 0;
        error = string.Empty;
        if (!SplitFirstComma(operandText, out var regText, out var deviceText))
        {
            error = "Expected register and device (e.g. AC0, TTI).";
            return false;
        }

        if (!TryParseRegister(regText, out reg))
        {
            error = $"Invalid register '{regText}'.";
            return false;
        }

        if (!TryParseDeviceOperand(deviceText, symbols, out device, out error))
        {
            return false;
        }

        return true;
    }

    private static bool TryParseRegAddressOperands(
        string operandText,
        Dictionary<string, int> symbols,
        int pc,
        out int reg,
        out SimhEffectiveAddress ea,
        out string error)
    {
        reg = 0;
        ea = default;
        error = string.Empty;
        if (!SplitFirstComma(operandText, out var regText, out var addrText))
        {
            error = "Expected register and address (e.g. AC0, 100).";
            return false;
        }

        if (!TryParseRegister(regText, out reg))
        {
            error = $"Invalid register '{regText}'.";
            return false;
        }

        return TryParseSimhAddressOperand(addrText, symbols, pc, out ea, out error);
    }

    private static bool TryParseOperateOperands(
        string operandText,
        out int src,
        out int dst,
        out int skipCode,
        out string error)
    {
        src = 0;
        dst = 0;
        skipCode = 0;
        error = string.Empty;

        if (!SplitFirstComma(operandText, out var srcText, out var rest))
        {
            error = "Expected src,dst registers.";
            return false;
        }

        if (!TryParseRegister(srcText, out src))
        {
            error = $"Invalid register '{srcText}'.";
            return false;
        }

        var restTokens = rest.Split(new[] { ',', ' ', '\t' }, StringSplitOptions.RemoveEmptyEntries);
        if (restTokens.Length == 0)
        {
            error = "Missing destination register.";
            return false;
        }

        if (!TryParseRegister(restTokens[0], out dst))
        {
            error = $"Invalid register '{restTokens[0]}'.";
            return false;
        }

        if (restTokens.Length > 1)
        {
            if (!TryParseSkipMnemonic(restTokens[1], out skipCode))
            {
                error = $"Invalid skip mnemonic '{restTokens[1]}'.";
                return false;
            }
        }

        if (restTokens.Length > 2)
        {
            error = "Too many operands for operate instruction.";
            return false;
        }

        return true;
    }

    private static bool TryParseByteOperands(
        string operandText,
        out int src,
        out int dst,
        out string error)
    {
        src = 0;
        dst = 0;
        error = string.Empty;
        if (!SplitFirstComma(operandText, out var srcText, out var dstText))
        {
            error = "Expected src,dst registers.";
            return false;
        }

        if (!TryParseRegister(srcText, out src))
        {
            error = $"Invalid register '{srcText}'.";
            return false;
        }

        if (!TryParseRegister(dstText, out dst))
        {
            error = $"Invalid register '{dstText}'.";
            return false;
        }

        return true;
    }

    private static bool TryParseDeviceOperand(
        string operandText,
        Dictionary<string, int> symbols,
        out int device,
        out string error)
    {
        device = 0;
        error = string.Empty;
        if (string.IsNullOrWhiteSpace(operandText))
        {
            error = "Missing device operand.";
            return false;
        }

        if (!TryParseDevice(operandText, symbols, out device, out error))
        {
            return false;
        }

        return true;
    }

    private static bool TryParseSimhAddressOperand(
        string operandText,
        Dictionary<string, int> symbols,
        int pc,
        out SimhEffectiveAddress ea,
        out string error)
    {
        ea = default;
        error = string.Empty;
        if (string.IsNullOrWhiteSpace(operandText))
        {
            error = "Missing address operand.";
            return false;
        }

        var text = operandText.Trim();
        var indirect = false;
        if (text.StartsWith("@", StringComparison.Ordinal))
        {
            indirect = true;
            text = text[1..].Trim();
        }

        var hasDot = false;
        if (text.StartsWith(".", StringComparison.Ordinal))
        {
            hasDot = true;
            text = text[1..].Trim();
        }

        var mode = 0;
        var dispText = text;
        string? indexText = null;
        var commaIndex = text.IndexOf(',');
        if (commaIndex >= 0)
        {
            dispText = text[..commaIndex].Trim();
            indexText = text[(commaIndex + 1)..].Trim();
            if (string.IsNullOrWhiteSpace(indexText))
            {
                error = "Missing index register after comma.";
                return false;
            }
        }

        if (indexText is not null)
        {
            if (!TryParseRegister(indexText, out var indexReg) || indexReg < 2)
            {
                error = $"Invalid index register '{indexText}'.";
                return false;
            }

            mode = indexReg;
        }
        else if (hasDot)
        {
            mode = SimhModePc;
        }

        var dispValue = 0;
        if (!string.IsNullOrWhiteSpace(dispText))
        {
            if (!TryEvaluateExpression(dispText, symbols, out dispValue, out var dispError))
            {
                error = dispError;
                return false;
            }
        }

        if (hasDot || indexText is not null)
        {
            if (dispValue < -SimhDispSign || dispValue > SimhDispSign - 1)
            {
                error = $"Displacement {dispValue} out of range (-128..127).";
                return false;
            }

            var disp = dispValue & SimhDisplacementMask;
            ea = new SimhEffectiveAddress(indirect, mode, disp);
            return true;
        }

        if (dispValue < 0 || dispValue > NovaCpu.AddressMask)
        {
            error = $"Address {dispValue} out of range.";
            return false;
        }

        if (dispValue < SimhDispRange)
        {
            ea = new SimhEffectiveAddress(indirect, 0, dispValue & SimhDisplacementMask);
            return true;
        }

        var basePc = pc & NovaCpu.AddressMask;
        var delta = dispValue - basePc;
        if (delta < -SimhDispSign || delta > SimhDispSign - 1)
        {
            error = $"Address {FormatOctal(dispValue)} not reachable from PC {FormatOctal(basePc)}.";
            return false;
        }

        ea = new SimhEffectiveAddress(indirect, SimhModePc, delta & SimhDisplacementMask);
        return true;
    }

    private static bool TryParseSkipMnemonic(string token, out int skipCode)
    {
        skipCode = 0;
        var text = token.Trim().ToUpperInvariant();
        switch (text)
        {
            case "SKP":
                skipCode = 1;
                return true;
            case "SZC":
                skipCode = 2;
                return true;
            case "SNC":
                skipCode = 3;
                return true;
            case "SZR":
                skipCode = 4;
                return true;
            case "SNR":
                skipCode = 5;
                return true;
            case "SEZ":
                skipCode = 6;
                return true;
            case "SBN":
                skipCode = 7;
                return true;
            default:
                return false;
        }
    }

    private static bool TryParseRegister(string token, out int reg)
    {
        reg = 0;
        var text = token.Trim().ToUpperInvariant();
        if (text.StartsWith("AC", StringComparison.Ordinal))
        {
            text = text[2..];
        }

        if (!TryParseNumber(text, out var value))
        {
            return false;
        }

        reg = value;
        return reg >= 0 && reg <= 3;
    }

    private static bool TryParseDevice(string token, Dictionary<string, int> symbols, out int device, out string error)
    {
        device = 0;
        error = string.Empty;
        if (TryEvaluateExpression(token, symbols, out var value, out error))
        {
            device = value & 0x3F;
            return true;
        }

        return false;
    }

    private static bool SplitFirstComma(string text, out string left, out string right)
    {
        var index = text.IndexOf(',');
        if (index < 0)
        {
            left = string.Empty;
            right = string.Empty;
            return false;
        }

        left = text[..index].Trim();
        right = text[(index + 1)..].Trim();
        return !(string.IsNullOrEmpty(left) || string.IsNullOrEmpty(right));
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
            if (char.IsWhiteSpace(ch))
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

    private static string[] SplitCommaOperands(IEnumerable<string> parts)
    {
        var combined = string.Join(" ", parts);
        return combined.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
    }

    private static int GetInstructionWordCount(string mnemonic)
    {
        if (!SimhOpcodeLookup.TryGetValue(mnemonic.Trim().ToUpperInvariant(), out var entry))
        {
            return 1;
        }

        return entry.Class switch
        {
            SimhOperandClass.LI => 2,
            SimhOperandClass.RLI => 2,
            SimhOperandClass.LM => 2,
            SimhOperandClass.RLM => 2,
            SimhOperandClass.FRM => 2,
            SimhOperandClass.FST => 2,
            _ => 1
        };
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
            value = 0;
            return false;
        }
    }

    private static string FormatOctal(int value) => Convert.ToString(value & NovaCpu.WordMask, 8).PadLeft(6, '0');

    private readonly record struct LabelSplit(string? Label, string Remainder);

    private readonly record struct AsmItem(AsmItemKind Kind, int LineNumber, int Address, string Mnemonic, string[] Operands, int WordCount);

    private readonly record struct SimhEffectiveAddress(bool Indirect, int Mode, int Displacement);

    private readonly record struct SimhOpcodeEntry(string Mnemonic, int BaseWord, SimhOperandClass Class);

    private static IReadOnlyDictionary<string, SimhOpcodeEntry> BuildSimhOpcodeLookup()
    {
        var entries = new[]
        {
            new SimhOpcodeEntry("JMP", 0, SimhOperandClass.M), // 0o0000000
            new SimhOpcodeEntry("JSR", 2048, SimhOperandClass.M), // 0o0004000
            new SimhOpcodeEntry("ISZ", 4096, SimhOperandClass.M), // 0o0010000
            new SimhOpcodeEntry("DSZ", 6144, SimhOperandClass.M), // 0o0014000
            new SimhOpcodeEntry("LDA", 8192, SimhOperandClass.RM), // 0o0020000
            new SimhOpcodeEntry("STA", 16384, SimhOperandClass.RM), // 0o0040000
            new SimhOpcodeEntry("COM", 32768, SimhOperandClass.RR), // 0o0100000
            new SimhOpcodeEntry("COMZ", 32784, SimhOperandClass.RR), // 0o0100020
            new SimhOpcodeEntry("COMO", 32800, SimhOperandClass.RR), // 0o0100040
            new SimhOpcodeEntry("COMC", 32816, SimhOperandClass.RR), // 0o0100060
            new SimhOpcodeEntry("COML", 32832, SimhOperandClass.RR), // 0o0100100
            new SimhOpcodeEntry("COMZL", 32848, SimhOperandClass.RR), // 0o0100120
            new SimhOpcodeEntry("COMOL", 32864, SimhOperandClass.RR), // 0o0100140
            new SimhOpcodeEntry("COMCL", 32880, SimhOperandClass.RR), // 0o0100160
            new SimhOpcodeEntry("COMR", 32896, SimhOperandClass.RR), // 0o0100200
            new SimhOpcodeEntry("COMZR", 32912, SimhOperandClass.RR), // 0o0100220
            new SimhOpcodeEntry("COMOR", 32928, SimhOperandClass.RR), // 0o0100240
            new SimhOpcodeEntry("COMCR", 32944, SimhOperandClass.RR), // 0o0100260
            new SimhOpcodeEntry("COMS", 32960, SimhOperandClass.RR), // 0o0100300
            new SimhOpcodeEntry("COMZS", 32976, SimhOperandClass.RR), // 0o0100320
            new SimhOpcodeEntry("COMOS", 32992, SimhOperandClass.RR), // 0o0100340
            new SimhOpcodeEntry("COMCS", 33008, SimhOperandClass.RR), // 0o0100360
            new SimhOpcodeEntry("COM#", 32776, SimhOperandClass.RR), // 0o0100010
            new SimhOpcodeEntry("COMZ#", 32792, SimhOperandClass.RR), // 0o0100030
            new SimhOpcodeEntry("COMO#", 32808, SimhOperandClass.RR), // 0o0100050
            new SimhOpcodeEntry("COMC#", 32824, SimhOperandClass.RR), // 0o0100070
            new SimhOpcodeEntry("COML#", 32840, SimhOperandClass.RR), // 0o0100110
            new SimhOpcodeEntry("COMZL#", 32856, SimhOperandClass.RR), // 0o0100130
            new SimhOpcodeEntry("COMOL#", 32872, SimhOperandClass.RR), // 0o0100150
            new SimhOpcodeEntry("COMCL#", 32888, SimhOperandClass.RR), // 0o0100170
            new SimhOpcodeEntry("COMR#", 32904, SimhOperandClass.RR), // 0o0100210
            new SimhOpcodeEntry("COMZR#", 32920, SimhOperandClass.RR), // 0o0100230
            new SimhOpcodeEntry("COMOR#", 32936, SimhOperandClass.RR), // 0o0100250
            new SimhOpcodeEntry("COMCR#", 32952, SimhOperandClass.RR), // 0o0100270
            new SimhOpcodeEntry("COMS#", 32968, SimhOperandClass.RR), // 0o0100310
            new SimhOpcodeEntry("COMZS#", 32984, SimhOperandClass.RR), // 0o0100330
            new SimhOpcodeEntry("COMOS#", 33000, SimhOperandClass.RR), // 0o0100350
            new SimhOpcodeEntry("COMCS#", 33016, SimhOperandClass.RR), // 0o0100370
            new SimhOpcodeEntry("NEG", 33024, SimhOperandClass.RR), // 0o0100400
            new SimhOpcodeEntry("NEGZ", 33040, SimhOperandClass.RR), // 0o0100420
            new SimhOpcodeEntry("NEGO", 33056, SimhOperandClass.RR), // 0o0100440
            new SimhOpcodeEntry("NEGC", 33072, SimhOperandClass.RR), // 0o0100460
            new SimhOpcodeEntry("NEGL", 33088, SimhOperandClass.RR), // 0o0100500
            new SimhOpcodeEntry("NEGZL", 33104, SimhOperandClass.RR), // 0o0100520
            new SimhOpcodeEntry("NEGOL", 33120, SimhOperandClass.RR), // 0o0100540
            new SimhOpcodeEntry("NEGCL", 33136, SimhOperandClass.RR), // 0o0100560
            new SimhOpcodeEntry("NEGR", 33152, SimhOperandClass.RR), // 0o0100600
            new SimhOpcodeEntry("NEGZR", 33168, SimhOperandClass.RR), // 0o0100620
            new SimhOpcodeEntry("NEGOR", 33184, SimhOperandClass.RR), // 0o0100640
            new SimhOpcodeEntry("NEGCR", 33200, SimhOperandClass.RR), // 0o0100660
            new SimhOpcodeEntry("NEGS", 33216, SimhOperandClass.RR), // 0o0100700
            new SimhOpcodeEntry("NEGZS", 33232, SimhOperandClass.RR), // 0o0100720
            new SimhOpcodeEntry("NEGOS", 33248, SimhOperandClass.RR), // 0o0100740
            new SimhOpcodeEntry("NEGCS", 33264, SimhOperandClass.RR), // 0o0100760
            new SimhOpcodeEntry("NEG#", 33032, SimhOperandClass.RR), // 0o0100410
            new SimhOpcodeEntry("NEGZ#", 33048, SimhOperandClass.RR), // 0o0100430
            new SimhOpcodeEntry("NEGO#", 33064, SimhOperandClass.RR), // 0o0100450
            new SimhOpcodeEntry("NEGC#", 33080, SimhOperandClass.RR), // 0o0100470
            new SimhOpcodeEntry("NEGL#", 33096, SimhOperandClass.RR), // 0o0100510
            new SimhOpcodeEntry("NEGZL#", 33112, SimhOperandClass.RR), // 0o0100530
            new SimhOpcodeEntry("NEGOL#", 33128, SimhOperandClass.RR), // 0o0100550
            new SimhOpcodeEntry("NEGCL#", 33144, SimhOperandClass.RR), // 0o0100570
            new SimhOpcodeEntry("NEGR#", 33160, SimhOperandClass.RR), // 0o0100610
            new SimhOpcodeEntry("NEGZR#", 33176, SimhOperandClass.RR), // 0o0100630
            new SimhOpcodeEntry("NEGOR#", 33192, SimhOperandClass.RR), // 0o0100650
            new SimhOpcodeEntry("NEGCR#", 33208, SimhOperandClass.RR), // 0o0100670
            new SimhOpcodeEntry("NEGS#", 33224, SimhOperandClass.RR), // 0o0100710
            new SimhOpcodeEntry("NEGZS#", 33240, SimhOperandClass.RR), // 0o0100730
            new SimhOpcodeEntry("NEGOS#", 33256, SimhOperandClass.RR), // 0o0100750
            new SimhOpcodeEntry("NEGCS#", 33272, SimhOperandClass.RR), // 0o0100770
            new SimhOpcodeEntry("MOV", 33280, SimhOperandClass.RR), // 0o0101000
            new SimhOpcodeEntry("MOVZ", 33296, SimhOperandClass.RR), // 0o0101020
            new SimhOpcodeEntry("MOVO", 33312, SimhOperandClass.RR), // 0o0101040
            new SimhOpcodeEntry("MOVC", 33328, SimhOperandClass.RR), // 0o0101060
            new SimhOpcodeEntry("MOVL", 33344, SimhOperandClass.RR), // 0o0101100
            new SimhOpcodeEntry("MOVZL", 33360, SimhOperandClass.RR), // 0o0101120
            new SimhOpcodeEntry("MOVOL", 33376, SimhOperandClass.RR), // 0o0101140
            new SimhOpcodeEntry("MOVCL", 33392, SimhOperandClass.RR), // 0o0101160
            new SimhOpcodeEntry("MOVR", 33408, SimhOperandClass.RR), // 0o0101200
            new SimhOpcodeEntry("MOVZR", 33424, SimhOperandClass.RR), // 0o0101220
            new SimhOpcodeEntry("MOVOR", 33440, SimhOperandClass.RR), // 0o0101240
            new SimhOpcodeEntry("MOVCR", 33456, SimhOperandClass.RR), // 0o0101260
            new SimhOpcodeEntry("MOVS", 33472, SimhOperandClass.RR), // 0o0101300
            new SimhOpcodeEntry("MOVZS", 33488, SimhOperandClass.RR), // 0o0101320
            new SimhOpcodeEntry("MOVOS", 33504, SimhOperandClass.RR), // 0o0101340
            new SimhOpcodeEntry("MOVCS", 33520, SimhOperandClass.RR), // 0o0101360
            new SimhOpcodeEntry("MOV#", 33288, SimhOperandClass.RR), // 0o0101010
            new SimhOpcodeEntry("MOVZ#", 33304, SimhOperandClass.RR), // 0o0101030
            new SimhOpcodeEntry("MOVO#", 33320, SimhOperandClass.RR), // 0o0101050
            new SimhOpcodeEntry("MOVC#", 33336, SimhOperandClass.RR), // 0o0101070
            new SimhOpcodeEntry("MOVL#", 33352, SimhOperandClass.RR), // 0o0101110
            new SimhOpcodeEntry("MOVZL#", 33368, SimhOperandClass.RR), // 0o0101130
            new SimhOpcodeEntry("MOVOL#", 33384, SimhOperandClass.RR), // 0o0101150
            new SimhOpcodeEntry("MOVCL#", 33400, SimhOperandClass.RR), // 0o0101170
            new SimhOpcodeEntry("MOVR#", 33416, SimhOperandClass.RR), // 0o0101210
            new SimhOpcodeEntry("MOVZR#", 33432, SimhOperandClass.RR), // 0o0101230
            new SimhOpcodeEntry("MOVOR#", 33448, SimhOperandClass.RR), // 0o0101250
            new SimhOpcodeEntry("MOVCR#", 33464, SimhOperandClass.RR), // 0o0101270
            new SimhOpcodeEntry("MOVS#", 33480, SimhOperandClass.RR), // 0o0101310
            new SimhOpcodeEntry("MOVZS#", 33496, SimhOperandClass.RR), // 0o0101330
            new SimhOpcodeEntry("MOVOS#", 33512, SimhOperandClass.RR), // 0o0101350
            new SimhOpcodeEntry("MOVCS#", 33528, SimhOperandClass.RR), // 0o0101370
            new SimhOpcodeEntry("INC", 33536, SimhOperandClass.RR), // 0o0101400
            new SimhOpcodeEntry("INCZ", 33552, SimhOperandClass.RR), // 0o0101420
            new SimhOpcodeEntry("INCO", 33568, SimhOperandClass.RR), // 0o0101440
            new SimhOpcodeEntry("INCC", 33584, SimhOperandClass.RR), // 0o0101460
            new SimhOpcodeEntry("INCL", 33600, SimhOperandClass.RR), // 0o0101500
            new SimhOpcodeEntry("INCZL", 33616, SimhOperandClass.RR), // 0o0101520
            new SimhOpcodeEntry("INCOL", 33632, SimhOperandClass.RR), // 0o0101540
            new SimhOpcodeEntry("INCCL", 33648, SimhOperandClass.RR), // 0o0101560
            new SimhOpcodeEntry("INCR", 33664, SimhOperandClass.RR), // 0o0101600
            new SimhOpcodeEntry("INCZR", 33680, SimhOperandClass.RR), // 0o0101620
            new SimhOpcodeEntry("INCOR", 33696, SimhOperandClass.RR), // 0o0101640
            new SimhOpcodeEntry("INCCR", 33712, SimhOperandClass.RR), // 0o0101660
            new SimhOpcodeEntry("INCS", 33728, SimhOperandClass.RR), // 0o0101700
            new SimhOpcodeEntry("INCZS", 33744, SimhOperandClass.RR), // 0o0101720
            new SimhOpcodeEntry("INCOS", 33760, SimhOperandClass.RR), // 0o0101740
            new SimhOpcodeEntry("INCCS", 33776, SimhOperandClass.RR), // 0o0101760
            new SimhOpcodeEntry("INC#", 33544, SimhOperandClass.RR), // 0o0101410
            new SimhOpcodeEntry("INCZ#", 33560, SimhOperandClass.RR), // 0o0101430
            new SimhOpcodeEntry("INCO#", 33576, SimhOperandClass.RR), // 0o0101450
            new SimhOpcodeEntry("INCC#", 33592, SimhOperandClass.RR), // 0o0101470
            new SimhOpcodeEntry("INCL#", 33608, SimhOperandClass.RR), // 0o0101510
            new SimhOpcodeEntry("INCZL#", 33624, SimhOperandClass.RR), // 0o0101530
            new SimhOpcodeEntry("INCOL#", 33640, SimhOperandClass.RR), // 0o0101550
            new SimhOpcodeEntry("INCCL#", 33656, SimhOperandClass.RR), // 0o0101570
            new SimhOpcodeEntry("INCR#", 33672, SimhOperandClass.RR), // 0o0101610
            new SimhOpcodeEntry("INCZR#", 33688, SimhOperandClass.RR), // 0o0101630
            new SimhOpcodeEntry("INCOR#", 33704, SimhOperandClass.RR), // 0o0101650
            new SimhOpcodeEntry("INCCR#", 33720, SimhOperandClass.RR), // 0o0101670
            new SimhOpcodeEntry("INCS#", 33736, SimhOperandClass.RR), // 0o0101710
            new SimhOpcodeEntry("INCZS#", 33752, SimhOperandClass.RR), // 0o0101730
            new SimhOpcodeEntry("INCOS#", 33768, SimhOperandClass.RR), // 0o0101750
            new SimhOpcodeEntry("INCCS#", 33784, SimhOperandClass.RR), // 0o0101770
            new SimhOpcodeEntry("ADC", 33792, SimhOperandClass.RR), // 0o0102000
            new SimhOpcodeEntry("ADCZ", 33808, SimhOperandClass.RR), // 0o0102020
            new SimhOpcodeEntry("ADCO", 33824, SimhOperandClass.RR), // 0o0102040
            new SimhOpcodeEntry("ADCC", 33840, SimhOperandClass.RR), // 0o0102060
            new SimhOpcodeEntry("ADCL", 33856, SimhOperandClass.RR), // 0o0102100
            new SimhOpcodeEntry("ADCZL", 33872, SimhOperandClass.RR), // 0o0102120
            new SimhOpcodeEntry("ADCOL", 33888, SimhOperandClass.RR), // 0o0102140
            new SimhOpcodeEntry("ADCCL", 33904, SimhOperandClass.RR), // 0o0102160
            new SimhOpcodeEntry("ADCR", 33920, SimhOperandClass.RR), // 0o0102200
            new SimhOpcodeEntry("ADCZR", 33936, SimhOperandClass.RR), // 0o0102220
            new SimhOpcodeEntry("ADCOR", 33952, SimhOperandClass.RR), // 0o0102240
            new SimhOpcodeEntry("ADCCR", 33968, SimhOperandClass.RR), // 0o0102260
            new SimhOpcodeEntry("ADCS", 33984, SimhOperandClass.RR), // 0o0102300
            new SimhOpcodeEntry("ADCZS", 34000, SimhOperandClass.RR), // 0o0102320
            new SimhOpcodeEntry("ADCOS", 34016, SimhOperandClass.RR), // 0o0102340
            new SimhOpcodeEntry("ADCCS", 34032, SimhOperandClass.RR), // 0o0102360
            new SimhOpcodeEntry("ADC#", 33800, SimhOperandClass.RR), // 0o0102010
            new SimhOpcodeEntry("ADCZ#", 33816, SimhOperandClass.RR), // 0o0102030
            new SimhOpcodeEntry("ADCO#", 33832, SimhOperandClass.RR), // 0o0102050
            new SimhOpcodeEntry("ADCC#", 33848, SimhOperandClass.RR), // 0o0102070
            new SimhOpcodeEntry("ADCL#", 33864, SimhOperandClass.RR), // 0o0102110
            new SimhOpcodeEntry("ADCZL#", 33880, SimhOperandClass.RR), // 0o0102130
            new SimhOpcodeEntry("ADCOL#", 33896, SimhOperandClass.RR), // 0o0102150
            new SimhOpcodeEntry("ADCCL#", 33912, SimhOperandClass.RR), // 0o0102170
            new SimhOpcodeEntry("ADCR#", 33928, SimhOperandClass.RR), // 0o0102210
            new SimhOpcodeEntry("ADCZR#", 33944, SimhOperandClass.RR), // 0o0102230
            new SimhOpcodeEntry("ADCOR#", 33960, SimhOperandClass.RR), // 0o0102250
            new SimhOpcodeEntry("ADCCR#", 33976, SimhOperandClass.RR), // 0o0102270
            new SimhOpcodeEntry("ADCS#", 33992, SimhOperandClass.RR), // 0o0102310
            new SimhOpcodeEntry("ADCZS#", 34008, SimhOperandClass.RR), // 0o0102330
            new SimhOpcodeEntry("ADCOS#", 34024, SimhOperandClass.RR), // 0o0102350
            new SimhOpcodeEntry("ADCCS#", 34040, SimhOperandClass.RR), // 0o0102370
            new SimhOpcodeEntry("SUB", 34048, SimhOperandClass.RR), // 0o0102400
            new SimhOpcodeEntry("SUBZ", 34064, SimhOperandClass.RR), // 0o0102420
            new SimhOpcodeEntry("SUBO", 34080, SimhOperandClass.RR), // 0o0102440
            new SimhOpcodeEntry("SUBC", 34096, SimhOperandClass.RR), // 0o0102460
            new SimhOpcodeEntry("SUBL", 34112, SimhOperandClass.RR), // 0o0102500
            new SimhOpcodeEntry("SUBZL", 34128, SimhOperandClass.RR), // 0o0102520
            new SimhOpcodeEntry("SUBOL", 34144, SimhOperandClass.RR), // 0o0102540
            new SimhOpcodeEntry("SUBCL", 34160, SimhOperandClass.RR), // 0o0102560
            new SimhOpcodeEntry("SUBR", 34176, SimhOperandClass.RR), // 0o0102600
            new SimhOpcodeEntry("SUBZR", 34192, SimhOperandClass.RR), // 0o0102620
            new SimhOpcodeEntry("SUBOR", 34208, SimhOperandClass.RR), // 0o0102640
            new SimhOpcodeEntry("SUBCR", 34224, SimhOperandClass.RR), // 0o0102660
            new SimhOpcodeEntry("SUBS", 34240, SimhOperandClass.RR), // 0o0102700
            new SimhOpcodeEntry("SUBZS", 34256, SimhOperandClass.RR), // 0o0102720
            new SimhOpcodeEntry("SUBOS", 34272, SimhOperandClass.RR), // 0o0102740
            new SimhOpcodeEntry("SUBCS", 34288, SimhOperandClass.RR), // 0o0102760
            new SimhOpcodeEntry("SUB#", 34056, SimhOperandClass.RR), // 0o0102410
            new SimhOpcodeEntry("SUBZ#", 34072, SimhOperandClass.RR), // 0o0102430
            new SimhOpcodeEntry("SUBO#", 34088, SimhOperandClass.RR), // 0o0102450
            new SimhOpcodeEntry("SUBC#", 34104, SimhOperandClass.RR), // 0o0102470
            new SimhOpcodeEntry("SUBL#", 34120, SimhOperandClass.RR), // 0o0102510
            new SimhOpcodeEntry("SUBZL#", 34136, SimhOperandClass.RR), // 0o0102530
            new SimhOpcodeEntry("SUBOL#", 34152, SimhOperandClass.RR), // 0o0102550
            new SimhOpcodeEntry("SUBCL#", 34168, SimhOperandClass.RR), // 0o0102570
            new SimhOpcodeEntry("SUBR#", 34184, SimhOperandClass.RR), // 0o0102610
            new SimhOpcodeEntry("SUBZR#", 34200, SimhOperandClass.RR), // 0o0102630
            new SimhOpcodeEntry("SUBOR#", 34216, SimhOperandClass.RR), // 0o0102650
            new SimhOpcodeEntry("SUBCR#", 34232, SimhOperandClass.RR), // 0o0102670
            new SimhOpcodeEntry("SUBS#", 34248, SimhOperandClass.RR), // 0o0102710
            new SimhOpcodeEntry("SUBZS#", 34264, SimhOperandClass.RR), // 0o0102730
            new SimhOpcodeEntry("SUBOS#", 34280, SimhOperandClass.RR), // 0o0102750
            new SimhOpcodeEntry("SUBCS#", 34296, SimhOperandClass.RR), // 0o0102770
            new SimhOpcodeEntry("ADD", 34304, SimhOperandClass.RR), // 0o0103000
            new SimhOpcodeEntry("ADDZ", 34320, SimhOperandClass.RR), // 0o0103020
            new SimhOpcodeEntry("ADDO", 34336, SimhOperandClass.RR), // 0o0103040
            new SimhOpcodeEntry("ADDC", 34352, SimhOperandClass.RR), // 0o0103060
            new SimhOpcodeEntry("ADDL", 34368, SimhOperandClass.RR), // 0o0103100
            new SimhOpcodeEntry("ADDZL", 34384, SimhOperandClass.RR), // 0o0103120
            new SimhOpcodeEntry("ADDOL", 34400, SimhOperandClass.RR), // 0o0103140
            new SimhOpcodeEntry("ADDCL", 34416, SimhOperandClass.RR), // 0o0103160
            new SimhOpcodeEntry("ADDR", 34432, SimhOperandClass.RR), // 0o0103200
            new SimhOpcodeEntry("ADDZR", 34448, SimhOperandClass.RR), // 0o0103220
            new SimhOpcodeEntry("ADDOR", 34464, SimhOperandClass.RR), // 0o0103240
            new SimhOpcodeEntry("ADDCR", 34480, SimhOperandClass.RR), // 0o0103260
            new SimhOpcodeEntry("ADDS", 34496, SimhOperandClass.RR), // 0o0103300
            new SimhOpcodeEntry("ADDZS", 34512, SimhOperandClass.RR), // 0o0103320
            new SimhOpcodeEntry("ADDOS", 34528, SimhOperandClass.RR), // 0o0103340
            new SimhOpcodeEntry("ADDCS", 34544, SimhOperandClass.RR), // 0o0103360
            new SimhOpcodeEntry("ADD#", 34312, SimhOperandClass.RR), // 0o0103010
            new SimhOpcodeEntry("ADDZ#", 34328, SimhOperandClass.RR), // 0o0103030
            new SimhOpcodeEntry("ADDO#", 34344, SimhOperandClass.RR), // 0o0103050
            new SimhOpcodeEntry("ADDC#", 34360, SimhOperandClass.RR), // 0o0103070
            new SimhOpcodeEntry("ADDL#", 34376, SimhOperandClass.RR), // 0o0103110
            new SimhOpcodeEntry("ADDZL#", 34392, SimhOperandClass.RR), // 0o0103130
            new SimhOpcodeEntry("ADDOL#", 34408, SimhOperandClass.RR), // 0o0103150
            new SimhOpcodeEntry("ADDCL#", 34424, SimhOperandClass.RR), // 0o0103170
            new SimhOpcodeEntry("ADDR#", 34440, SimhOperandClass.RR), // 0o0103210
            new SimhOpcodeEntry("ADDZR#", 34456, SimhOperandClass.RR), // 0o0103230
            new SimhOpcodeEntry("ADDOR#", 34472, SimhOperandClass.RR), // 0o0103250
            new SimhOpcodeEntry("ADDCR#", 34488, SimhOperandClass.RR), // 0o0103270
            new SimhOpcodeEntry("ADDS#", 34504, SimhOperandClass.RR), // 0o0103310
            new SimhOpcodeEntry("ADDZS#", 34520, SimhOperandClass.RR), // 0o0103330
            new SimhOpcodeEntry("ADDOS#", 34536, SimhOperandClass.RR), // 0o0103350
            new SimhOpcodeEntry("ADDCS#", 34552, SimhOperandClass.RR), // 0o0103370
            new SimhOpcodeEntry("AND", 34560, SimhOperandClass.RR), // 0o0103400
            new SimhOpcodeEntry("ANDZ", 34576, SimhOperandClass.RR), // 0o0103420
            new SimhOpcodeEntry("ANDO", 34592, SimhOperandClass.RR), // 0o0103440
            new SimhOpcodeEntry("ANDC", 34608, SimhOperandClass.RR), // 0o0103460
            new SimhOpcodeEntry("ANDL", 34624, SimhOperandClass.RR), // 0o0103500
            new SimhOpcodeEntry("ANDZL", 34640, SimhOperandClass.RR), // 0o0103520
            new SimhOpcodeEntry("ANDOL", 34656, SimhOperandClass.RR), // 0o0103540
            new SimhOpcodeEntry("ANDCL", 34672, SimhOperandClass.RR), // 0o0103560
            new SimhOpcodeEntry("ANDR", 34688, SimhOperandClass.RR), // 0o0103600
            new SimhOpcodeEntry("ANDZR", 34704, SimhOperandClass.RR), // 0o0103620
            new SimhOpcodeEntry("ANDOR", 34720, SimhOperandClass.RR), // 0o0103640
            new SimhOpcodeEntry("ANDCR", 34736, SimhOperandClass.RR), // 0o0103660
            new SimhOpcodeEntry("ANDS", 34752, SimhOperandClass.RR), // 0o0103700
            new SimhOpcodeEntry("ANDZS", 34768, SimhOperandClass.RR), // 0o0103720
            new SimhOpcodeEntry("ANDOS", 34784, SimhOperandClass.RR), // 0o0103740
            new SimhOpcodeEntry("ANDCS", 34800, SimhOperandClass.RR), // 0o0103760
            new SimhOpcodeEntry("AND#", 34568, SimhOperandClass.RR), // 0o0103410
            new SimhOpcodeEntry("ANDZ#", 34584, SimhOperandClass.RR), // 0o0103430
            new SimhOpcodeEntry("ANDO#", 34600, SimhOperandClass.RR), // 0o0103450
            new SimhOpcodeEntry("ANDC#", 34616, SimhOperandClass.RR), // 0o0103470
            new SimhOpcodeEntry("ANDL#", 34632, SimhOperandClass.RR), // 0o0103510
            new SimhOpcodeEntry("ANDZL#", 34648, SimhOperandClass.RR), // 0o0103530
            new SimhOpcodeEntry("ANDOL#", 34664, SimhOperandClass.RR), // 0o0103550
            new SimhOpcodeEntry("ANDCL#", 34680, SimhOperandClass.RR), // 0o0103570
            new SimhOpcodeEntry("ANDR#", 34696, SimhOperandClass.RR), // 0o0103610
            new SimhOpcodeEntry("ANDZR#", 34712, SimhOperandClass.RR), // 0o0103630
            new SimhOpcodeEntry("ANDOR#", 34728, SimhOperandClass.RR), // 0o0103650
            new SimhOpcodeEntry("ANDCR#", 34744, SimhOperandClass.RR), // 0o0103670
            new SimhOpcodeEntry("ANDS#", 34760, SimhOperandClass.RR), // 0o0103710
            new SimhOpcodeEntry("ANDZS#", 34776, SimhOperandClass.RR), // 0o0103730
            new SimhOpcodeEntry("ANDOS#", 34792, SimhOperandClass.RR), // 0o0103750
            new SimhOpcodeEntry("ANDCS#", 34808, SimhOperandClass.RR), // 0o0103770
            new SimhOpcodeEntry("INTEN", 24703, SimhOperandClass.NPN), // 0o0060177
            new SimhOpcodeEntry("INTDS", 24767, SimhOperandClass.NPN), // 0o0060277
            new SimhOpcodeEntry("READS", 24895, SimhOperandClass.R), // 0o0060477
            new SimhOpcodeEntry("INTA", 25407, SimhOperandClass.R), // 0o0061477
            new SimhOpcodeEntry("MSKO", 25663, SimhOperandClass.R), // 0o0062077
            new SimhOpcodeEntry("IORST", 26047, SimhOperandClass.NPN), // 0o0062677
            new SimhOpcodeEntry("HALT", 26175, SimhOperandClass.NPN), // 0o0063077
            new SimhOpcodeEntry("MUL", 30401, SimhOperandClass.NPN), // 0o0073301
            new SimhOpcodeEntry("DIV", 30273, SimhOperandClass.NPN), // 0o0073101
            new SimhOpcodeEntry("MULS", 32385, SimhOperandClass.NPN), // 0o0077201
            new SimhOpcodeEntry("DIVS", 32257, SimhOperandClass.NPN), // 0o0077001
            new SimhOpcodeEntry("PSHA", 25345, SimhOperandClass.R), // 0o0061401
            new SimhOpcodeEntry("POPA", 25473, SimhOperandClass.R), // 0o0061601
            new SimhOpcodeEntry("SAV", 25857, SimhOperandClass.NPN), // 0o0062401
            new SimhOpcodeEntry("RET", 25985, SimhOperandClass.NPN), // 0o0062601
            new SimhOpcodeEntry("MTSP", 25089, SimhOperandClass.R), // 0o0061001
            new SimhOpcodeEntry("MTFP", 24577, SimhOperandClass.R), // 0o0060001
            new SimhOpcodeEntry("MFSP", 25217, SimhOperandClass.R), // 0o0061201
            new SimhOpcodeEntry("MFFP", 24705, SimhOperandClass.R), // 0o0060201
            new SimhOpcodeEntry("LDB", 24833, SimhOperandClass.BY), // 0o0060401
            new SimhOpcodeEntry("STB", 25601, SimhOperandClass.BY), // 0o0062001
            new SimhOpcodeEntry("NIO", 24576, SimhOperandClass.RD), // 0o0060000
            new SimhOpcodeEntry("NIOS", 24640, SimhOperandClass.RD), // 0o0060100
            new SimhOpcodeEntry("NIOC", 24704, SimhOperandClass.RD), // 0o0060200
            new SimhOpcodeEntry("NIOP", 24768, SimhOperandClass.RD), // 0o0060300
            new SimhOpcodeEntry("DIA", 24832, SimhOperandClass.RD), // 0o0060400
            new SimhOpcodeEntry("DIAS", 24896, SimhOperandClass.RD), // 0o0060500
            new SimhOpcodeEntry("DIAC", 24960, SimhOperandClass.RD), // 0o0060600
            new SimhOpcodeEntry("DIAP", 25024, SimhOperandClass.RD), // 0o0060700
            new SimhOpcodeEntry("DOA", 25088, SimhOperandClass.RD), // 0o0061000
            new SimhOpcodeEntry("DOAS", 25152, SimhOperandClass.RD), // 0o0061100
            new SimhOpcodeEntry("DOAC", 25216, SimhOperandClass.RD), // 0o0061200
            new SimhOpcodeEntry("DOAP", 25280, SimhOperandClass.RD), // 0o0061300
            new SimhOpcodeEntry("DIB", 25344, SimhOperandClass.RD), // 0o0061400
            new SimhOpcodeEntry("DIBS", 25408, SimhOperandClass.RD), // 0o0061500
            new SimhOpcodeEntry("DIBC", 25472, SimhOperandClass.RD), // 0o0061600
            new SimhOpcodeEntry("DIBP", 25536, SimhOperandClass.RD), // 0o0061700
            new SimhOpcodeEntry("DOB", 25600, SimhOperandClass.RD), // 0o0062000
            new SimhOpcodeEntry("DOBS", 25664, SimhOperandClass.RD), // 0o0062100
            new SimhOpcodeEntry("DOBC", 25728, SimhOperandClass.RD), // 0o0062200
            new SimhOpcodeEntry("DOBP", 25792, SimhOperandClass.RD), // 0o0062300
            new SimhOpcodeEntry("DIC", 25856, SimhOperandClass.RD), // 0o0062400
            new SimhOpcodeEntry("DICS", 25920, SimhOperandClass.RD), // 0o0062500
            new SimhOpcodeEntry("DICC", 25984, SimhOperandClass.RD), // 0o0062600
            new SimhOpcodeEntry("DICP", 26048, SimhOperandClass.RD), // 0o0062700
            new SimhOpcodeEntry("DOC", 26112, SimhOperandClass.RD), // 0o0063000
            new SimhOpcodeEntry("DOCS", 26176, SimhOperandClass.RD), // 0o0063100
            new SimhOpcodeEntry("DOCC", 26240, SimhOperandClass.RD), // 0o0063200
            new SimhOpcodeEntry("DOCP", 26304, SimhOperandClass.RD), // 0o0063300
            new SimhOpcodeEntry("SKPBN", 26368, SimhOperandClass.D), // 0o0063400
            new SimhOpcodeEntry("SKPBZ", 26432, SimhOperandClass.D), // 0o0063500
            new SimhOpcodeEntry("SKPDN", 26496, SimhOperandClass.D), // 0o0063600
            new SimhOpcodeEntry("SKPDZ", 26560, SimhOperandClass.D), // 0o0063700
        };

        var map = new Dictionary<string, SimhOpcodeEntry>(StringComparer.OrdinalIgnoreCase);
        foreach (var entry in entries)
        {
            map[entry.Mnemonic] = entry;
        }

        return map;
    }
}

public sealed class AssemblerResult
{
    public List<AssemblerDiagnostic> Diagnostics { get; } = new();
    public List<AssembledWord> Words { get; } = new();
    public ushort? StartAddress { get; set; }
    public bool Success => Diagnostics.All(d => d.Severity != DiagnosticSeverity.Error);
}

public readonly record struct AssembledWord(ushort Address, ushort Value, int LineNumber);

public enum DiagnosticSeverity
{
    Warning,
    Error
}

public readonly record struct AssemblerDiagnostic(int LineNumber, DiagnosticSeverity Severity, string Message);

internal enum AsmItemKind
{
    Word,
    Text,
    Instruction
}

internal enum SimhOperandClass
{
    NPN,
    R,
    D,
    RD,
    M,
    RM,
    RR,
    BY,
    LI,
    RLI,
    LM,
    RLM,
    FRM,
    FST
}
