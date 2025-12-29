namespace Snova;

public enum NovaIoOpKind
{
    DIA,
    DOA,
    DIB,
    DOB,
    DIC,
    DOC,
    NIO,
    SKPBN,
    SKPBZ,
    SKPDN,
    SKPDZ
}

public readonly struct NovaIoOp
{
    public NovaIoOp(NovaIoOpKind kind, int deviceCode, int ac, bool start, bool clear, bool pulse)
    {
        Kind = kind;
        DeviceCode = deviceCode;
        Ac = ac;
        Start = start;
        Clear = clear;
        Pulse = pulse;
    }

    public NovaIoOpKind Kind { get; }
    public int DeviceCode { get; }
    public int Ac { get; }
    public bool Start { get; }
    public bool Clear { get; }
    public bool Pulse { get; }
}

public interface INovaIoDevice
{
    int DeviceCode { get; }

    bool ExecuteIo(NovaIoOp op, ref ushort accumulator, out bool skip);
}

public sealed class NovaIoBus
{
    private readonly Dictionary<int, INovaIoDevice> _devices = new();

    public void RegisterDevice(INovaIoDevice device)
    {
        _devices[device.DeviceCode & 0x3F] = device;
    }

    public bool TryExecute(NovaIoOp op, ref ushort accumulator, out bool skip)
    {
        skip = false;
        if (_devices.TryGetValue(op.DeviceCode & 0x3F, out var device))
        {
            return device.ExecuteIo(op, ref accumulator, out skip);
        }

        return false;
    }
}
