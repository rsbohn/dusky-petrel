namespace Snova;

public sealed class NovaTc08Device : INovaIoDevice
{
    public const int DefaultDeviceCode = 16; // 0o20

    private const ushort ControlDriveMask = 0x0001;
    private const ushort ControlReadMask = 0x0002;
    private const ushort ControlWriteMask = 0x0004;

    private const ushort StatusDoneMask = 0x0001;
    private const ushort StatusBusyMask = 0x0002;
    private const ushort StatusErrorMask = 0x0004;

    private readonly NovaCpu _cpu;
    private readonly Tc08 _tc08;

    private ushort _transferAddress;
    private ushort _block;
    private ushort _control;
    private bool _busy;
    private bool _done;
    private bool _error;

    public NovaTc08Device(NovaCpu cpu, Tc08 tc08, int deviceCode = DefaultDeviceCode)
    {
        _cpu = cpu;
        _tc08 = tc08;
        DeviceCode = deviceCode & 0x3F;
    }

    public int DeviceCode { get; }

    public bool ExecuteIo(NovaIoOp op, ref ushort accumulator, out bool skip)
    {
        skip = false;
        switch (op.Kind)
        {
            case NovaIoOpKind.DIA:
                accumulator = _transferAddress;
                return true;
            case NovaIoOpKind.DOA:
                _transferAddress = accumulator;
                _done = false;
                _error = false;
                return true;
            case NovaIoOpKind.DIB:
                accumulator = _block;
                return true;
            case NovaIoOpKind.DOB:
                _block = accumulator;
                _done = false;
                _error = false;
                return true;
            case NovaIoOpKind.DIC:
                accumulator = GetStatusWord();
                return true;
            case NovaIoOpKind.DOC:
                _control = (ushort)(accumulator & (ControlDriveMask | ControlReadMask | ControlWriteMask));
                _done = false;
                _error = false;
                return true;
            case NovaIoOpKind.NIO:
                if (op.Clear)
                {
                    ClearState();
                }
                if (op.Start || op.Pulse)
                {
                    ExecuteTransfer();
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

    private ushort GetStatusWord()
    {
        var status = 0;
        if (_done)
        {
            status |= StatusDoneMask;
        }
        if (_busy)
        {
            status |= StatusBusyMask;
        }
        if (_error)
        {
            status |= StatusErrorMask;
        }

        return (ushort)status;
    }

    private void ClearState()
    {
        _transferAddress = 0;
        _block = 0;
        _control = 0;
        _busy = false;
        _done = false;
        _error = false;
    }

    private void ExecuteTransfer()
    {
        if (_busy)
        {
            return;
        }

        _busy = true;
        _done = false;
        _error = false;

        var drive = (_control & ControlDriveMask) != 0 ? 1 : 0;
        var read = (_control & ControlReadMask) != 0;
        var write = (_control & ControlWriteMask) != 0;
        if (read == write)
        {
            _error = true;
            _busy = false;
            _done = true;
            return;
        }

        Span<ushort> buffer = stackalloc ushort[Tc08.WordsPerBlock];
        if (read)
        {
            if (_tc08.TryReadBlock(drive, _block, buffer, out _))
            {
                for (var i = 0; i < Tc08.WordsPerBlock; i++)
                {
                    var addr = (ushort)(_transferAddress + i);
                    _cpu.WriteMemory(addr, buffer[i]);
                }
            }
            else
            {
                _error = true;
            }
        }
        else
        {
            for (var i = 0; i < Tc08.WordsPerBlock; i++)
            {
                var addr = (ushort)(_transferAddress + i);
                buffer[i] = _cpu.ReadMemory(addr);
            }

            if (!_tc08.TryWriteBlock(drive, _block, buffer, out _))
            {
                _error = true;
            }
        }

        _busy = false;
        _done = true;
    }
}
