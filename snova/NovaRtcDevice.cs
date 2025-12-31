namespace Snova;

public sealed class NovaRtcDevice : INovaIoDevice
{
    public const int DefaultDeviceCode = 17; // 0o21

    private static readonly DateTime Epoch = new(2000, 1, 1, 0, 0, 0, DateTimeKind.Utc);

    public NovaRtcDevice(int deviceCode = DefaultDeviceCode)
    {
        DeviceCode = deviceCode & 0x3F;
    }

    public int DeviceCode { get; }

    public ushort ReadMinutesSinceMidnight() => GetMinutesSinceMidnight();

    public long ReadEpochSeconds() => GetEpochSeconds();

    public bool ExecuteIo(NovaIoOp op, ref ushort accumulator, out bool skip)
    {
        skip = false;
        switch (op.Kind)
        {
            case NovaIoOpKind.DIA:
                accumulator = GetMinutesSinceMidnight();
                return true;
            case NovaIoOpKind.DIB:
                accumulator = GetEpochSecondsLow();
                return true;
            case NovaIoOpKind.DIC:
                accumulator = GetEpochSecondsHigh();
                return true;
            case NovaIoOpKind.NIO:
                return true;
            case NovaIoOpKind.SKPBN:
                skip = false;
                return true;
            case NovaIoOpKind.SKPBZ:
                skip = true;
                return true;
            case NovaIoOpKind.SKPDN:
                skip = true;
                return true;
            case NovaIoOpKind.SKPDZ:
                skip = false;
                return true;
            default:
                return false;
        }
    }

    private static ushort GetMinutesSinceMidnight()
    {
        var now = DateTime.UtcNow;
        var minutes = (int)now.TimeOfDay.TotalMinutes;
        return (ushort)(minutes & 0xFFFF);
    }

    private static long GetEpochSeconds()
    {
        var now = DateTime.UtcNow;
        var seconds = (long)(now - Epoch).TotalSeconds;
        return seconds;
    }

    private static ushort GetEpochSecondsLow()
    {
        var seconds = GetEpochSeconds();
        return (ushort)(seconds & 0xFFFF);
    }

    private static ushort GetEpochSecondsHigh()
    {
        var seconds = GetEpochSeconds();
        return (ushort)((seconds >> 16) & 0xFFFF);
    }
}
