namespace Snova;

/// <summary>Raw SIMH-style DSK media: 1024 sectors of 256 little-endian words.</summary>
public sealed class DskImage
{
    public const int DriveCount = 2;
    public const int SectorsPerDrive = 1024;
    public const int WordsPerSector = 256;
    public const int BytesPerSector = WordsPerSector * sizeof(ushort);

    private readonly string?[] _paths = new string?[DriveCount];

    public bool Attach(int drive, string path, bool create, out string? error)
    {
        if (!ValidDrive(drive)) { error = "Invalid drive index."; return false; }
        var fullPath = Path.GetFullPath(path);
        try
        {
            if (!File.Exists(fullPath))
            {
                if (!create) { error = $"File not found: {fullPath}"; return false; }
                using var stream = new FileStream(fullPath, FileMode.CreateNew, FileAccess.ReadWrite, FileShare.Read);
                stream.SetLength((long)SectorsPerDrive * BytesPerSector);
            }
            var length = new FileInfo(fullPath).Length;
            if (length < (long)SectorsPerDrive * BytesPerSector)
            {
                error = $"DSK image too small: expected at least {(long)SectorsPerDrive * BytesPerSector} bytes.";
                return false;
            }
            _paths[drive] = fullPath;
            error = null;
            return true;
        }
        catch (Exception ex) { error = $"Attach failed: {ex.Message}"; return false; }
    }

    public string? GetPath(int drive) => ValidDrive(drive) ? _paths[drive] : null;

    public bool TryReadSector(int drive, int sector, Span<ushort> words, out string? error)
    {
        if (!Validate(drive, sector, words.Length, out var path, out error)) return false;
        try
        {
            using var stream = new FileStream(path!, FileMode.Open, FileAccess.Read, FileShare.ReadWrite);
            stream.Position = (long)sector * BytesPerSector;
            using var reader = new BinaryReader(stream);
            for (var i = 0; i < WordsPerSector; i++) words[i] = reader.ReadUInt16();
            error = null;
            return true;
        }
        catch (Exception ex) { error = $"Read failed: {ex.Message}"; return false; }
    }

    public bool TryWriteSector(int drive, int sector, ReadOnlySpan<ushort> words, out string? error)
    {
        if (!Validate(drive, sector, words.Length, out var path, out error)) return false;
        try
        {
            using var stream = new FileStream(path!, FileMode.Open, FileAccess.ReadWrite, FileShare.Read);
            stream.Position = (long)sector * BytesPerSector;
            using var writer = new BinaryWriter(stream);
            for (var i = 0; i < WordsPerSector; i++) writer.Write(words[i]);
            error = null;
            return true;
        }
        catch (Exception ex) { error = $"Write failed: {ex.Message}"; return false; }
    }

    private bool Validate(int drive, int sector, int wordCount, out string? path, out string? error)
    {
        path = ValidDrive(drive) ? _paths[drive] : null;
        if (path is null) { error = "DSK drive not attached."; return false; }
        if (sector < 0 || sector >= SectorsPerDrive) { error = "Invalid DSK sector."; return false; }
        if (wordCount < WordsPerSector) { error = "Buffer too small."; return false; }
        error = null;
        return true;
    }

    private static bool ValidDrive(int drive) => drive >= 0 && drive < DriveCount;
}
