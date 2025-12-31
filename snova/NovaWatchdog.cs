using System.Threading;

namespace Snova;

public enum NovaWatchdogAction
{
    None = 0,
    Interrupt = 1,
    Halt = 2,
    Reset = 3
}

public readonly record struct NovaWatchdogStatus(
    bool HostEnabled,
    bool Enabled,
    bool Active,
    bool Fired,
    bool Repeat,
    NovaWatchdogAction Action,
    int TimeoutMs,
    int DeviceCode);

public sealed class NovaWatchdogDevice : INovaIoDevice
{
    public const int DefaultDeviceCode = 56; // 0o70

    private readonly object _sync = new();
    private readonly NovaCpu _cpu;
    private readonly Timer _timer;
    private readonly int _defaultTimeoutMs;
    private readonly bool _defaultRepeat;
    private readonly NovaWatchdogAction _defaultAction;

    private bool _hostEnabled;
    private bool _enabled;
    private bool _repeat;
    private NovaWatchdogAction _action;
    private bool _active;
    private bool _fired;
    private int _timeoutMs;

    public NovaWatchdogDevice(
        NovaCpu cpu,
        int deviceCode = DefaultDeviceCode,
        int timeoutMs = 5000,
        bool repeat = false,
        NovaWatchdogAction action = NovaWatchdogAction.Interrupt,
        bool hostEnabled = false)
    {
        _cpu = cpu;
        DeviceCode = deviceCode & 0x3F;
        _defaultTimeoutMs = ClampTimeout(timeoutMs);
        _defaultRepeat = repeat;
        _defaultAction = action;
        _timeoutMs = _defaultTimeoutMs;
        _repeat = _defaultRepeat;
        _action = _defaultAction;
        _hostEnabled = hostEnabled;
        _timer = new Timer(OnTimer, null, Timeout.Infinite, Timeout.Infinite);
    }

    public int DeviceCode { get; }

    public bool ExecuteIo(NovaIoOp op, ref ushort accumulator, out bool skip)
    {
        skip = false;
        NovaWatchdogAction actionToTake = NovaWatchdogAction.None;
        bool fireAfterUnlock = false;

        lock (_sync)
        {
            if (!_hostEnabled)
            {
                return false;
            }

            switch (op.Kind)
            {
                case NovaIoOpKind.DIA:
                    accumulator = (ushort)(_timeoutMs & 0xFFFF);
                    return true;
                case NovaIoOpKind.DOA:
                    _timeoutMs = ClampTimeout(accumulator);
                    if (_active && _enabled)
                    {
                        _timer.Change(_timeoutMs, Timeout.Infinite);
                    }
                    return true;
                case NovaIoOpKind.DIB:
                    accumulator = GetControlWordLocked();
                    return true;
                case NovaIoOpKind.DOB:
                    ApplyControlWordLocked(accumulator);
                    return true;
                case NovaIoOpKind.DIC:
                    accumulator = GetStatusWordLocked();
                    return true;
                case NovaIoOpKind.DOC:
                    return true;
                case NovaIoOpKind.NIO:
                    if (op.Clear)
                    {
                        ClearLocked();
                    }
                    if (op.Pulse)
                    {
                        fireAfterUnlock = true;
                        actionToTake = _action;
                        ForceFireLocked();
                    }
                    if (op.Start)
                    {
                        ArmLocked();
                    }
                    break;
                case NovaIoOpKind.SKPBN:
                    skip = _active;
                    return true;
                case NovaIoOpKind.SKPBZ:
                    skip = !_active;
                    return true;
                case NovaIoOpKind.SKPDN:
                    skip = _fired;
                    return true;
                case NovaIoOpKind.SKPDZ:
                    skip = !_fired;
                    return true;
                default:
                    return false;
            }
        }

        if (fireAfterUnlock)
        {
            PerformAction(actionToTake);
        }

        return true;
    }

    public NovaWatchdogStatus GetStatus()
    {
        lock (_sync)
        {
            return new NovaWatchdogStatus(
                _hostEnabled,
                _enabled,
                _active,
                _fired,
                _repeat,
                _action,
                _timeoutMs,
                DeviceCode);
        }
    }

    public void SetHostEnabled(bool enabled)
    {
        lock (_sync)
        {
            _hostEnabled = enabled;
            if (!enabled)
            {
                _active = false;
                _timer.Change(Timeout.Infinite, Timeout.Infinite);
            }
        }
    }

    public void SetTimeoutMs(int timeoutMs)
    {
        lock (_sync)
        {
            _timeoutMs = ClampTimeout(timeoutMs);
            if (_active && _enabled)
            {
                _timer.Change(_timeoutMs, Timeout.Infinite);
            }
        }
    }

    public void SetEnabled(bool enabled)
    {
        lock (_sync)
        {
            _enabled = enabled;
            if (!enabled)
            {
                _active = false;
                _timer.Change(Timeout.Infinite, Timeout.Infinite);
            }
        }
    }

    public void SetRepeat(bool repeat)
    {
        lock (_sync)
        {
            _repeat = repeat;
        }
    }

    public void SetAction(NovaWatchdogAction action)
    {
        lock (_sync)
        {
            _action = action;
        }
    }

    public void Arm()
    {
        lock (_sync)
        {
            ArmLocked();
        }
    }

    public void Pet()
    {
        lock (_sync)
        {
            if (!_enabled || !_hostEnabled)
            {
                return;
            }
            ArmLocked();
        }
    }

    public void ClearFired()
    {
        lock (_sync)
        {
            _fired = false;
        }
    }

    public void Clear()
    {
        lock (_sync)
        {
            ClearLocked();
        }
    }

    public void ForceFire()
    {
        NovaWatchdogAction actionToTake;
        lock (_sync)
        {
            actionToTake = _action;
            ForceFireLocked();
        }
        PerformAction(actionToTake);
    }

    public void ResetDeviceState()
    {
        lock (_sync)
        {
            _enabled = false;
            _active = false;
            _fired = false;
            _repeat = _defaultRepeat;
            _action = _defaultAction;
            _timeoutMs = _defaultTimeoutMs;
            _timer.Change(Timeout.Infinite, Timeout.Infinite);
        }
    }

    private void ApplyControlWordLocked(ushort value)
    {
        var enable = (value & 0x1) != 0;
        var repeat = (value & 0x2) != 0;
        var actionBits = (value >> 2) & 0x3;
        var pet = (value & 0x10) != 0;
        var clearFired = (value & 0x20) != 0;

        _repeat = repeat;
        _action = (NovaWatchdogAction)actionBits;
        _enabled = enable;

        if (!enable)
        {
            _active = false;
            _timer.Change(Timeout.Infinite, Timeout.Infinite);
        }

        if (clearFired)
        {
            _fired = false;
        }

        if (pet && enable)
        {
            ArmLocked();
        }
    }

    private ushort GetControlWordLocked()
    {
        var value = 0;
        if (_enabled)
        {
            value |= 0x1;
        }
        if (_repeat)
        {
            value |= 0x2;
        }
        value |= ((int)_action & 0x3) << 2;
        return (ushort)value;
    }

    private ushort GetStatusWordLocked()
    {
        var value = 0;
        if (_fired)
        {
            value |= 0x1;
        }
        if (_active)
        {
            value |= 0x2;
        }
        if (_repeat)
        {
            value |= 0x4;
        }
        value |= ((int)_action & 0x3) << 3;
        return (ushort)value;
    }

    private void ArmLocked()
    {
        if (!_hostEnabled || !_enabled || _timeoutMs <= 0)
        {
            return;
        }

        _active = true;
        _timer.Change(_timeoutMs, Timeout.Infinite);
    }

    private void ClearLocked()
    {
        _active = false;
        _fired = false;
        _timer.Change(Timeout.Infinite, Timeout.Infinite);
    }

    private void ForceFireLocked()
    {
        _fired = true;
        _active = false;
        var shouldRepeat = _repeat && _enabled && _timeoutMs > 0 && _hostEnabled;
        if (shouldRepeat)
        {
            _active = true;
            _timer.Change(_timeoutMs, Timeout.Infinite);
        }
        else
        {
            _timer.Change(Timeout.Infinite, Timeout.Infinite);
        }
    }

    private void OnTimer(object? state)
    {
        NovaWatchdogAction actionToTake;
        lock (_sync)
        {
            if (!_active || !_hostEnabled || !_enabled)
            {
                return;
            }

            actionToTake = _action;
            ForceFireLocked();
        }

        PerformAction(actionToTake);
    }

    private void PerformAction(NovaWatchdogAction action)
    {
        switch (action)
        {
            case NovaWatchdogAction.Halt:
                _cpu.Halt("Watchdog");
                break;
            case NovaWatchdogAction.Reset:
                _cpu.Reset();
                break;
        }
    }

    private static int ClampTimeout(int timeoutMs)
    {
        if (timeoutMs < 0)
        {
            return 0;
        }

        return timeoutMs > 0xFFFF ? 0xFFFF : timeoutMs;
    }
}
