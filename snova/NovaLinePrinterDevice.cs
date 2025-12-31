using System.IO;

namespace Snova;

public sealed class NovaLinePrinterDevice : INovaIoDevice
{
    public const int DefaultDeviceCode = 12; // 0o14

    private readonly object _sync = new();
    private bool _busy;
    private bool _done = true;
    private string _outputPath;

    public NovaLinePrinterDevice(string? outputPath = null, int deviceCode = DefaultDeviceCode)
    {
        DeviceCode = deviceCode & 0x3F;
        _outputPath = string.IsNullOrWhiteSpace(outputPath) ? "./media/print.out" : outputPath;
    }

    public int DeviceCode { get; }

    public string OutputPath => _outputPath;

    public void SetOutputPath(string path)
    {
        if (string.IsNullOrWhiteSpace(path))
        {
            return;
        }

        _outputPath = path;
    }

    public bool ExecuteIo(NovaIoOp op, ref ushort accumulator, out bool skip)
    {
        skip = false;
        switch (op.Kind)
        {
            case NovaIoOpKind.DOA:
            case NovaIoOpKind.DOB:
            case NovaIoOpKind.DOC:
                WriteOutput((byte)(accumulator & 0xFF));
                return true;
            case NovaIoOpKind.NIO:
                if (op.Clear)
                {
                    ClearOutput();
                }
                return true;
            case NovaIoOpKind.SKPBN:
                skip = _busy;
                return true;
            case NovaIoOpKind.SKPBZ:
                skip = !_busy;
                return true;
            case NovaIoOpKind.SKPDN:
                skip = _done;
                return true;
            case NovaIoOpKind.SKPDZ:
                skip = !_done;
                return true;
            default:
                return false;
        }
    }

    private void WriteOutput(byte value)
    {
        lock (_sync)
        {
            _busy = true;
            _done = false;
            EnsureOutputDirectory(_outputPath);
            using var stream = new FileStream(_outputPath, FileMode.Append, FileAccess.Write, FileShare.Read);
            stream.WriteByte(value);
            _busy = false;
            _done = true;
        }
    }

    private void ClearOutput()
    {
        _busy = false;
        _done = true;
    }

    private static void EnsureOutputDirectory(string path)
    {
        var dir = Path.GetDirectoryName(path);
        if (!string.IsNullOrEmpty(dir))
        {
            Directory.CreateDirectory(dir);
        }
    }
}
