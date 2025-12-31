using System.Globalization;

namespace Snova;

public static class AbsoluteTapeTool
{
    public const int NotHandled = -1;
    private const int DefaultLeaderBytes = 16;
    private const int MaxLoadBlockWords = 16; // 0o20

    public static int Run(string[] args)
    {
        if (args.Length == 0 || !args[0].Equals("abs", StringComparison.OrdinalIgnoreCase))
        {
            return NotHandled;
        }

        if (args.Length < 3)
        {
            PrintUsage();
            return 2;
        }

        var asmPath = args[1];
        var outPath = args[2];
        var leaderBytes = DefaultLeaderBytes;
        int? execAddressOverride = null;
        var format = AbsoluteFormat.SimhLoad;

        for (var i = 3; i < args.Length; i++)
        {
            if (args[i].Equals("--leader", StringComparison.OrdinalIgnoreCase))
            {
                if (i + 1 >= args.Length || !int.TryParse(args[i + 1], NumberStyles.Integer, CultureInfo.InvariantCulture, out leaderBytes))
                {
                    Console.WriteLine("abs: --leader expects an integer byte count.");
                    return 2;
                }

                i++;
                continue;
            }

            if (args[i].Equals("--start", StringComparison.OrdinalIgnoreCase))
            {
                if (i + 1 >= args.Length || !TryParseNumber(args[i + 1], out var start))
                {
                    Console.WriteLine("abs: --start expects an address (octal by default).");
                    return 2;
                }

                execAddressOverride = start;
                i++;
                continue;
            }

            if (args[i].Equals("--format", StringComparison.OrdinalIgnoreCase))
            {
                if (i + 1 >= args.Length)
                {
                    Console.WriteLine("abs: --format expects 'simh-load' or 'ptr'.");
                    return 2;
                }

                var parsedFormat = ParseFormat(args[i + 1]);
                if (parsedFormat is null)
                {
                    Console.WriteLine("abs: --format expects 'simh-load' or 'ptr'.");
                    return 2;
                }

                format = parsedFormat.Value;
                i++;
                continue;
            }

            if (execAddressOverride is null && TryParseNumber(args[i], out var addr))
            {
                execAddressOverride = addr;
                continue;
            }

            Console.WriteLine($"abs: unrecognized argument '{args[i]}'.");
            return 2;
        }

        if (!File.Exists(asmPath))
        {
            Console.WriteLine($"abs: file not found: {asmPath}");
            return 1;
        }

        var assembler = new NovaAssembler();
        AssemblerResult result;
        try
        {
            result = assembler.AssembleFile(asmPath);
        }
        catch (Exception ex)
        {
            Console.WriteLine($"abs: assembly failed: {ex.Message}");
            return 1;
        }

        if (!result.Success)
        {
            Console.WriteLine("abs: assembly failed:");
            foreach (var diag in result.Diagnostics)
            {
                Console.WriteLine($"  line {diag.LineNumber}: {diag.Message}");
            }

            return 1;
        }

        var words = result.Words.OrderBy(w => w.Address).ToList();
        if (words.Count == 0)
        {
            Console.WriteLine("abs: no output words.");
            return 1;
        }

        var execAddress = execAddressOverride ?? result.StartAddress ?? words[0].Address;
        using var stream = File.Create(outPath);
        using var writer = new BinaryWriter(stream);

        if (leaderBytes > 0)
        {
            for (var i = 0; i < leaderBytes; i++)
            {
                writer.Write((byte)0x00);
            }
        }

        var blocks = SplitBlocks(words, format == AbsoluteFormat.SimhLoad);
        foreach (var block in blocks)
        {
            if (format == AbsoluteFormat.SimhLoad)
            {
                WriteLoadBlock(writer, block.Address, block.Data);
            }
            else
            {
                WritePtrBlock(writer, block.Address, block.Data);
            }
        }

        if (format == AbsoluteFormat.SimhLoad)
        {
            WriteLoadStartBlock(writer, execAddress);
        }
        else
        {
            WritePtrBlock(writer, execAddress, Array.Empty<ushort>());
        }

        Console.WriteLine($"abs: wrote {blocks.Count} block(s) + terminal to {outPath} ({format})");
        return 0;
    }

    private static void PrintUsage()
    {
        Console.WriteLine("Usage:");
        Console.WriteLine("  abs <asmfile> <outbin> [start] [--leader N] [--start addr] [--format simh-load|ptr]");
    }

    private static List<AbsoluteBlock> SplitBlocks(List<AssembledWord> words, bool limitSize)
    {
        var blocks = new List<AbsoluteBlock>();
        var index = 0;

        while (index < words.Count)
        {
            var start = words[index].Address;
            var data = new List<ushort> { words[index].Value };
            var nextAddr = (ushort)((start + 1) & NovaCpu.AddressMask);
            index++;

            while (index < words.Count && words[index].Address == nextAddr)
            {
                if (limitSize && data.Count >= MaxLoadBlockWords)
                {
                    break;
                }

                data.Add(words[index].Value);
                nextAddr = (ushort)((nextAddr + 1) & NovaCpu.AddressMask);
                index++;
            }

            blocks.Add(new AbsoluteBlock(start, data.ToArray()));
        }

        return blocks;
    }

    private static void WritePtrBlock(BinaryWriter writer, int address, ushort[] data)
    {
        if (data.Length > ushort.MaxValue)
        {
            throw new InvalidOperationException("Block too large for absolute format.");
        }

        writer.Write((byte)0xFF);
        var countWord = (ushort)(0 - data.Length);
        WriteWordHighLow(writer, countWord);
        WriteWordHighLow(writer, (ushort)(address & NovaCpu.AddressMask));

        foreach (var word in data)
        {
            WriteWordHighLow(writer, word);
        }

        var checksum = ComputePtrChecksum(countWord, (ushort)(address & NovaCpu.AddressMask), data);
        WriteWordHighLow(writer, checksum);
    }

    private static void WriteLoadBlock(BinaryWriter writer, int address, ushort[] data)
    {
        if (data.Length > MaxLoadBlockWords)
        {
            throw new InvalidOperationException("Load block exceeds 16-word limit.");
        }

        var countWord = (ushort)(0 - data.Length);
        WriteWordLowHigh(writer, countWord);
        WriteWordLowHigh(writer, (ushort)(address & NovaCpu.AddressMask));

        var checksum = ComputeLoadChecksum(countWord, (ushort)(address & NovaCpu.AddressMask), data);
        WriteWordLowHigh(writer, checksum);

        foreach (var word in data)
        {
            WriteWordLowHigh(writer, word);
        }
    }

    private static void WriteLoadStartBlock(BinaryWriter writer, int address)
    {
        const ushort countWord = 1;
        var origin = (ushort)(address & NovaCpu.AddressMask);
        WriteWordLowHigh(writer, countWord);
        WriteWordLowHigh(writer, origin);

        var checksum = ComputeLoadChecksum(countWord, origin, Array.Empty<ushort>());
        WriteWordLowHigh(writer, checksum);
    }

    private static void WriteWordHighLow(BinaryWriter writer, ushort word)
    {
        writer.Write((byte)((word >> 8) & 0xFF));
        writer.Write((byte)(word & 0xFF));
    }

    private static void WriteWordLowHigh(BinaryWriter writer, ushort word)
    {
        writer.Write((byte)(word & 0xFF));
        writer.Write((byte)((word >> 8) & 0xFF));
    }

    private static ushort ComputePtrChecksum(ushort countWord, ushort address, ushort[] data)
    {
        ushort sum = 0;
        sum = AddEndAroundCarry(sum, countWord);
        sum = AddEndAroundCarry(sum, address);
        foreach (var word in data)
        {
            sum = AddEndAroundCarry(sum, word);
        }

        return sum;
    }

    private static ushort ComputeLoadChecksum(ushort countWord, ushort address, ushort[] data)
    {
        uint sum = 0;
        sum += countWord;
        sum += address;
        foreach (var word in data)
        {
            sum += word;
        }

        return (ushort)(0 - (sum & 0xFFFF));
    }

    private static ushort AddEndAroundCarry(ushort currentSum, ushort newValue)
    {
        var temp = currentSum + newValue;
        if (temp > 0xFFFF)
        {
            temp = (temp & 0xFFFF) + 1;
        }

        return (ushort)temp;
    }

    private static bool TryParseNumber(string text, out int value)
    {
        value = 0;
        if (string.IsNullOrWhiteSpace(text))
        {
            return false;
        }

        if (text.StartsWith("0x", StringComparison.OrdinalIgnoreCase))
        {
            return int.TryParse(text[2..], NumberStyles.HexNumber, CultureInfo.InvariantCulture, out value);
        }

        try
        {
            value = Convert.ToInt32(text, 8);
            return true;
        }
        catch (Exception)
        {
            return false;
        }
    }

    private static AbsoluteFormat? ParseFormat(string text)
    {
        if (text.Equals("simh-load", StringComparison.OrdinalIgnoreCase))
        {
            return AbsoluteFormat.SimhLoad;
        }

        if (text.Equals("ptr", StringComparison.OrdinalIgnoreCase))
        {
            return AbsoluteFormat.Ptr;
        }

        return null;
    }

    private sealed record AbsoluteBlock(ushort Address, ushort[] Data);

    private enum AbsoluteFormat
    {
        SimhLoad,
        Ptr
    }
}
