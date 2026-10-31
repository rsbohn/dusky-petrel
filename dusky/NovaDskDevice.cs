namespace Snova;

/// <summary>
/// SIMH-compatible DSK fixed-head disk, device 0o20.
///
/// Implements the observable protocol of SIMH nova_dsk.c so Dusky runs
/// the same DSK images as SIMH (the preferred CVIT/Nova media).
/// </summary>
public sealed class NovaDskDevice : INovaIoDevice
{
    public const int DefaultDeviceCode = 16; // 0o20

    private const ushort StatusError = 0x0001;
    private const ushort StatusNsd = 0x0004;
    private const ushort StatusAllErrors = 0x003F;
    private const int SectorAddressMask = 0x1FFF;
    private const int MemoryAddressMask = 0x7FFF;

    private readonly NovaCpu _cpu;
    private readonly DskImage _dsk;
    private ushort _sector;
    private ushort _memAddr;
    private ushort _status;
    private bool _busy;
    private bool _done;

    public NovaDskDevice(NovaCpu cpu, DskImage dsk, int deviceCode = DefaultDeviceCode)
    {
        _cpu = cpu;
        _dsk = dsk;
        DeviceCode = deviceCode & 0x3F;
    }

    public int DeviceCode { get; }

    public bool ExecuteIo(NovaIoOp op, ref ushort accumulator, out bool skip)
    {
        skip = false;
        switch (op.Kind)
        {
            case NovaIoOpKind.DIA:
                accumulator = (ushort)(_status & StatusAllErrors);
                return true;
            case NovaIoOpKind.DOA:
                _sector = (ushort)(accumulator & SectorAddressMask);
                return true;
            case NovaIoOpKind.DIB:
                accumulator = _memAddr;
                return true;
            case NovaIoOpKind.DOB:
                _memAddr = (ushort)(accumulator & MemoryAddressMask);
                return true;
            case NovaIoOpKind.DIC:
                accumulator = DskImage.WordsPerSector;
                return true;
            case NovaIoOpKind.NIO:
                _busy = false;
                _done = false;
                _status = 0;
                if (op.Start)
                    DoTransfer(read: true);
                else if (op.Pulse)
                    DoTransfer(read: false);
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

    private void DoTransfer(bool read)
    {
        _busy = true;
        _done = false;
        _status = 0;
        Span<ushort> buffer = stackalloc ushort[DskImage.WordsPerSector];
        bool ok;
        if (read)
        {
            ok = _dsk.TryReadSector(0, _sector, buffer, out _);
            if (ok)
            {
                for (var i = 0; i < DskImage.WordsPerSector; i++)
                    _cpu.WriteMemory((ushort)((_memAddr + i) & MemoryAddressMask), buffer[i]);
                _memAddr = (ushort)((_memAddr + DskImage.WordsPerSector) & MemoryAddressMask);
            }
        }
        else
        {
            for (var i = 0; i < DskImage.WordsPerSector; i++)
                buffer[i] = _cpu.ReadMemory((ushort)((_memAddr + i) & MemoryAddressMask));
            ok = _dsk.TryWriteSector(0, _sector, buffer, out _);
            if (ok)
                _memAddr = (ushort)((_memAddr + DskImage.WordsPerSector) & MemoryAddressMask);
        }
        if (!ok)
            _status = (ushort)(StatusError | StatusNsd);
        _busy = false;
        _done = true;
    }
}
