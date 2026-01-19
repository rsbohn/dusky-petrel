using System.Collections.Generic;
using System.IO;

namespace Snova;

public sealed class NovaPaperTape
{
    public const int ReaderDeviceCode = 10; // 0o12
    public const int PunchDeviceCode = 11; // 0o13

    private readonly Queue<byte> _input = new();
    private readonly object _sync = new();
    private readonly object _punchSync = new();
    private bool _punchBusy;
    private bool _punchDone = true;
    private string _punchPath;

    public NovaPaperTape(string? punchPath = null)
    {
        _punchPath = string.IsNullOrWhiteSpace(punchPath) ? "./media/punch.out" : punchPath;
        ReaderDevice = new PtrDevice(this);
        PunchDevice = new PtpDevice(this);
    }

    public INovaIoDevice ReaderDevice { get; }
    public INovaIoDevice PunchDevice { get; }

    public int PendingInput
    {
        get
        {
            lock (_sync)
            {
                return _input.Count;
            }
        }
    }

    public string PunchPath => _punchPath;

    public void SetPunchPath(string path)
    {
        if (string.IsNullOrWhiteSpace(path))
        {
            return;
        }

        _punchPath = path;
    }

    public void EnqueueInputBytes(byte[] data)
    {
        if (data.Length == 0)
        {
            return;
        }

        lock (_sync)
        {
            foreach (var b in data)
            {
                _input.Enqueue(b);
            }
        }
    }

    public void EnqueueInputFile(string path)
    {
        var bytes = File.ReadAllBytes(path);
        EnqueueInputBytes(bytes);
    }

    private bool HasInput
    {
        get
        {
            lock (_sync)
            {
                return _input.Count > 0;
            }
        }
    }

    private byte ReadInput()
    {
        lock (_sync)
        {
            if (_input.Count == 0)
            {
                return 0;
            }

            return _input.Dequeue();
        }
    }

    private void ClearInput()
    {
        lock (_sync)
        {
            _input.Clear();
        }
    }

    private bool PunchBusy => _punchBusy;

    private bool PunchDone => _punchDone;

    private void WritePunch(byte value)
    {
        lock (_punchSync)
        {
            _punchBusy = true;
            _punchDone = false;
            EnsureOutputDirectory(_punchPath);
            using var stream = new FileStream(_punchPath, FileMode.Append, FileAccess.Write, FileShare.Read);
            stream.WriteByte(value);
            _punchBusy = false;
            _punchDone = true;
        }
    }

    private void ClearPunch()
    {
        _punchBusy = false;
        _punchDone = true;
    }

    private static void EnsureOutputDirectory(string path)
    {
        var dir = Path.GetDirectoryName(path);
        if (!string.IsNullOrEmpty(dir))
        {
            Directory.CreateDirectory(dir);
        }
    }

    private sealed class PtrDevice : INovaIoDevice
    {
        private readonly NovaPaperTape _tape;

        public PtrDevice(NovaPaperTape tape)
        {
            _tape = tape;
        }

        public int DeviceCode => ReaderDeviceCode;

        public bool ExecuteIo(NovaIoOp op, ref ushort accumulator, out bool skip)
        {
            skip = false;
            switch (op.Kind)
            {
                case NovaIoOpKind.DIA:
                case NovaIoOpKind.DIB:
                case NovaIoOpKind.DIC:
                    accumulator = _tape.ReadInput();
                    return true;
                case NovaIoOpKind.NIO:
                    if (op.Clear)
                    {
                        _tape.ClearInput();
                    }
                    return true;
                case NovaIoOpKind.SKPBN:
                    skip = false;
                    return true;
                case NovaIoOpKind.SKPBZ:
                    skip = true;
                    return true;
                case NovaIoOpKind.SKPDN:
                    skip = _tape.HasInput;
                    return true;
                case NovaIoOpKind.SKPDZ:
                    skip = !_tape.HasInput;
                    return true;
                default:
                    return false;
            }
        }
    }

    private sealed class PtpDevice : INovaIoDevice
    {
        private readonly NovaPaperTape _tape;

        public PtpDevice(NovaPaperTape tape)
        {
            _tape = tape;
        }

        public int DeviceCode => PunchDeviceCode;

        public bool ExecuteIo(NovaIoOp op, ref ushort accumulator, out bool skip)
        {
            skip = false;
            switch (op.Kind)
            {
                case NovaIoOpKind.DOA:
                case NovaIoOpKind.DOB:
                case NovaIoOpKind.DOC:
                    _tape.WritePunch((byte)(accumulator & 0xFF));
                    return true;
                case NovaIoOpKind.NIO:
                    if (op.Clear)
                    {
                        _tape.ClearPunch();
                    }
                    return true;
                case NovaIoOpKind.SKPBN:
                    skip = _tape.PunchBusy;
                    return true;
                case NovaIoOpKind.SKPBZ:
                    skip = !_tape.PunchBusy;
                    return true;
                case NovaIoOpKind.SKPDN:
                    skip = _tape.PunchDone;
                    return true;
                case NovaIoOpKind.SKPDZ:
                    skip = !_tape.PunchDone;
                    return true;
                default:
                    return false;
            }
        }
    }
}
