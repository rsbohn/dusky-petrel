namespace Snova;

public static class NovaDisassembler
{
    public static string DisassembleWord(ushort address, ushort instruction)
    {
        var text = DisassembleInstruction(address, instruction);
        return $"{NovaCpu.FormatWord(address)}: {NovaCpu.FormatWord(instruction)} {text}";
    }

    public static string DisassembleInstruction(ushort address, ushort instruction)
    {
        if ((instruction & 0xE000) == 0x6000)
        {
            return DisassembleIo(instruction);
        }

        if ((instruction & 0x8000) != 0)
        {
            return DisassembleOperate(instruction);
        }

        return DisassembleMrf(address, instruction);
    }

    public static string DisassembleInstructionListing(ushort address, ushort instruction)
    {
        if ((instruction & 0xE000) == 0x6000)
        {
            return DisassembleIo(instruction);
        }

        if ((instruction & 0x8000) != 0)
        {
            return DisassembleOperate(instruction);
        }

        return DisassembleMrfListing(address, instruction);
    }

    private static string DisassembleIo(ushort instruction)
    {
        var ac = (instruction >> 11) & 0x3;
        var function = (instruction >> 8) & 0x7;
        var pulse = (instruction >> 6) & 0x3;
        var device = instruction & 0x3F;
        var deviceText = Convert.ToString(device, 8).PadLeft(2, '0');
        var pulseSuffix = pulse switch
        {
            1 => "S",
            2 => "C",
            3 => "P",
            _ => string.Empty
        };
        return function switch
        {
            0 => $"NIO{pulseSuffix} AC{ac}, {deviceText}",
            1 => $"DIA{pulseSuffix} AC{ac}, {deviceText}",
            2 => $"DOA{pulseSuffix} AC{ac}, {deviceText}",
            3 => $"DIB{pulseSuffix} AC{ac}, {deviceText}",
            4 => $"DOB{pulseSuffix} AC{ac}, {deviceText}",
            5 => $"DIC{pulseSuffix} AC{ac}, {deviceText}",
            6 => $"DOC{pulseSuffix} AC{ac}, {deviceText}",
            _ => pulse switch
            {
                0 => $"SKPBN {deviceText}",
                1 => $"SKPBZ {deviceText}",
                2 => $"SKPDN {deviceText}",
                _ => $"SKPDZ {deviceText}"
            }
        };
    }

    private static string DisassembleOperate(ushort instruction)
    {
        var src = (instruction >> 13) & 0x3;
        var dst = (instruction >> 11) & 0x3;
        var alu = (instruction >> 8) & 0x7;
        var shift = (instruction >> 6) & 0x3;
        var carry = (instruction >> 4) & 0x3;
        var noLoad = (instruction & 0x8) != 0;
        var skip = instruction & 0x7;

        var aluNames = new[] { "COM", "NEG", "MOV", "INC", "ADC", "SUB", "ADD", "AND" };
        var carryNames = new[] { string.Empty, "Z", "O", "C" };
        var shiftNames = new[] { string.Empty, "L", "R", "S" };
        var skipNames = new[] { string.Empty, "SKP", "SZC", "SNC", "SZR", "SNR", "SEZ", "SBN" };

        var mnemonic = aluNames[alu] + carryNames[carry] + shiftNames[shift];
        if (noLoad)
        {
            mnemonic += "#";
        }

        var text = $"{mnemonic} AC{src}, AC{dst}";
        if (skip != 0)
        {
            text += $" {skipNames[skip]}";
        }

        return text;
    }

    private static string DisassembleMrf(ushort address, ushort instruction)
    {
        var opac = (instruction >> 11) & 0x1F;
        var indirect = (instruction & 0x0400) != 0;
        var mode = (instruction >> 8) & 0x3;
        var displacement = instruction & 0xFF;
        var operand = FormatSimhOperand(address, indirect, mode, displacement);

        return opac switch
        {
            0 => $"JMP {operand}",
            1 => $"JSR {operand}",
            2 => $"ISZ {operand}",
            3 => $"DSZ {operand}",
            4 => $"LDA AC0, {operand}",
            5 => $"LDA AC1, {operand}",
            6 => $"LDA AC2, {operand}",
            7 => $"LDA AC3, {operand}",
            8 => $"STA AC0, {operand}",
            9 => $"STA AC1, {operand}",
            10 => $"STA AC2, {operand}",
            11 => $"STA AC3, {operand}",
            _ => $"DW {NovaCpu.FormatWord(instruction)}"
        };
    }

    private static string DisassembleMrfListing(ushort address, ushort instruction)
    {
        var opac = (instruction >> 11) & 0x1F;
        var indirect = (instruction & 0x0400) != 0;
        var mode = (instruction >> 8) & 0x3;
        var displacement = instruction & 0xFF;
        var operand = FormatSimhOperandListing(address, indirect, mode, displacement);

        return opac switch
        {
            0 => $"JMP {operand}",
            1 => $"JSR {operand}",
            2 => $"ISZ {operand}",
            3 => $"DSZ {operand}",
            4 => $"LDA AC0, {operand}",
            5 => $"LDA AC1, {operand}",
            6 => $"LDA AC2, {operand}",
            7 => $"LDA AC3, {operand}",
            8 => $"STA AC0, {operand}",
            9 => $"STA AC1, {operand}",
            10 => $"STA AC2, {operand}",
            11 => $"STA AC3, {operand}",
            _ => $"DW {NovaCpu.FormatWord(instruction)}"
        };
    }

    private static string FormatSimhOperand(ushort pc, bool indirect, int mode, int displacement)
    {
        string text;
        switch (mode)
        {
            case 0:
                text = NovaCpu.FormatWord((ushort)displacement);
                break;
            case 1:
                {
                    var ea = (ushort)((pc + SignExtend8(displacement)) & NovaCpu.AddressMask);
                    text = NovaCpu.FormatWord(ea);
                    break;
                }
            case 2:
                text = $"{FormatSignedDisplacement(displacement)},AC2";
                break;
            default:
                text = $"{FormatSignedDisplacement(displacement)},AC3";
                break;
        }

        return indirect ? $"@{text}" : text;
    }

    private static string FormatSimhOperandListing(ushort pc, bool indirect, int mode, int displacement)
    {
        string text;
        switch (mode)
        {
            case 0:
                text = FormatListingAddress((ushort)displacement);
                break;
            case 1:
                {
                    var ea = (ushort)((pc + SignExtend8(displacement)) & NovaCpu.AddressMask);
                    text = FormatListingAddress(ea);
                    break;
                }
            case 2:
                text = $"{FormatSignedDisplacement(displacement)},AC2";
                break;
            default:
                text = $"{FormatSignedDisplacement(displacement)},AC3";
                break;
        }

        return indirect ? $"@{text}" : text;
    }

    private static string FormatListingAddress(ushort value)
    {
        var octal = Convert.ToString(value & NovaCpu.AddressMask, 8);
        return octal.Length < 4 ? octal.PadLeft(4, '0') : octal;
    }

    private static string FormatSignedDisplacement(int displacement)
    {
        var signed = (sbyte)(displacement & 0xFF);
        if (signed < 0)
        {
            return $"-0o{Convert.ToString(-signed, 8)}";
        }

        if (signed == 0)
        {
            return "0";
        }

        return $"0o{Convert.ToString(signed, 8)}";
    }

    private static short SignExtend8(int value)
    {
        var masked = value & 0xFF;
        if ((masked & 0x80) != 0)
        {
            return (short)(masked | 0xFF00);
        }

        return (short)masked;
    }
}
