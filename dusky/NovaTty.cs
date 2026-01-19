using System.Collections.Generic;
using System.IO;
using System.Text;

namespace Snova;

public sealed class NovaConsoleTty
{
    private readonly Queue<byte> _input = new();
    private readonly object _sync = new();
    private bool _outputBusy;
    private bool _outputDone = true;

    public NovaConsoleTty()
    {
        InputDevice = new TtiDevice(this);
        OutputDevice = new TtoDevice(this);
    }

    public INovaIoDevice InputDevice { get; }
    public INovaIoDevice OutputDevice { get; }

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

    public void EnqueueInputText(string text)
    {
        if (string.IsNullOrEmpty(text))
        {
            return;
        }

        EnqueueInputBytes(Encoding.ASCII.GetBytes(text));
    }

    public void EnqueueInputFile(string path, bool appendEof = false)
    {
        var bytes = File.ReadAllBytes(path);
        EnqueueInputBytes(bytes);
        if (appendEof)
        {
            EnqueueInputBytes(new byte[] { 0x04 });
        }
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

    private bool OutputBusy => _outputBusy;

    private bool OutputDone => _outputDone;

    private void WriteOutput(byte value)
    {
        _outputBusy = true;
        _outputDone = false;
        Console.Write((char)value);
        _outputBusy = false;
        _outputDone = true;
    }

    private void ClearOutput()
    {
        _outputBusy = false;
        _outputDone = true;
    }

    private sealed class TtiDevice : INovaIoDevice
    {
        private readonly NovaConsoleTty _tty;

        public TtiDevice(NovaConsoleTty tty)
        {
            _tty = tty;
        }

        public int DeviceCode => 8;

        public bool ExecuteIo(NovaIoOp op, ref ushort accumulator, out bool skip)
        {
            skip = false;
            switch (op.Kind)
            {
                case NovaIoOpKind.DIA:
                case NovaIoOpKind.DIB:
                case NovaIoOpKind.DIC:
                    accumulator = _tty.ReadInput();
                    return true;
                case NovaIoOpKind.NIO:
                    if (op.Clear)
                    {
                        _tty.ClearInput();
                    }
                    return true;
                case NovaIoOpKind.SKPBN:
                    skip = false;
                    return true;
                case NovaIoOpKind.SKPBZ:
                    skip = true;
                    return true;
                case NovaIoOpKind.SKPDN:
                    skip = _tty.HasInput;
                    return true;
                case NovaIoOpKind.SKPDZ:
                    skip = !_tty.HasInput;
                    return true;
                default:
                    return false;
            }
        }
    }

    private sealed class TtoDevice : INovaIoDevice
    {
        private readonly NovaConsoleTty _tty;

        public TtoDevice(NovaConsoleTty tty)
        {
            _tty = tty;
        }

        public int DeviceCode => 9;

        public bool ExecuteIo(NovaIoOp op, ref ushort accumulator, out bool skip)
        {
            skip = false;
            switch (op.Kind)
            {
                case NovaIoOpKind.DOA:
                case NovaIoOpKind.DOB:
                case NovaIoOpKind.DOC:
                    _tty.WriteOutput((byte)(accumulator & 0xFF));
                    return true;
                case NovaIoOpKind.NIO:
                    if (op.Clear)
                    {
                        _tty.ClearOutput();
                    }
                    return true;
                case NovaIoOpKind.SKPBN:
                    skip = _tty.OutputBusy;
                    return true;
                case NovaIoOpKind.SKPBZ:
                    skip = !_tty.OutputBusy;
                    return true;
                case NovaIoOpKind.SKPDN:
                    skip = _tty.OutputDone;
                    return true;
                case NovaIoOpKind.SKPDZ:
                    skip = !_tty.OutputDone;
                    return true;
                default:
                    return false;
            }
        }
    }
}
