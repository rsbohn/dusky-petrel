using System;

namespace Snova;

public sealed class NovaUnicodeTtoDevice : INovaIoDevice
{
    public const int DefaultDeviceCode = 19; // 0o23

    private bool _outputBusy;
    private bool _outputDone = true;
    private bool _seenOutput;
    private ushort? _pendingHighSurrogate;

    public NovaUnicodeTtoDevice(int deviceCode = DefaultDeviceCode)
    {
        DeviceCode = deviceCode & 0x3F;
    }

    public int DeviceCode { get; }

    public bool ExecuteIo(NovaIoOp op, ref ushort accumulator, out bool skip)
    {
        skip = false;
        switch (op.Kind)
        {
            case NovaIoOpKind.DOA:
            case NovaIoOpKind.DOB:
            case NovaIoOpKind.DOC:
                WriteOutput(accumulator);
                return true;
            case NovaIoOpKind.NIO:
                if (op.Clear)
                {
                    ClearOutput();
                }
                return true;
            case NovaIoOpKind.SKPBN:
                skip = _outputBusy;
                return true;
            case NovaIoOpKind.SKPBZ:
                skip = !_outputBusy;
                return true;
            case NovaIoOpKind.SKPDN:
                skip = _outputDone;
                return true;
            case NovaIoOpKind.SKPDZ:
                skip = !_outputDone;
                return true;
            default:
                return false;
        }
    }

    private void WriteOutput(ushort value)
    {
        _outputBusy = true;
        _outputDone = false;

        if (!_seenOutput)
        {
            _seenOutput = true;
            if (value == 0xFEFF)
            {
                _outputBusy = false;
                _outputDone = true;
                return;
            }
        }

        if (_pendingHighSurrogate.HasValue)
        {
            var high = (char)_pendingHighSurrogate.Value;
            _pendingHighSurrogate = null;
            var low = (char)value;
            if (char.IsLowSurrogate(low))
            {
                var codePoint = char.ConvertToUtf32(high, low);
                Console.Write(char.ConvertFromUtf32(codePoint));
            }
            else
            {
                Console.Write('\uFFFD');
                if (char.IsHighSurrogate((char)value))
                {
                    _pendingHighSurrogate = value;
                }
                else if (char.IsLowSurrogate((char)value))
                {
                    Console.Write('\uFFFD');
                }
                else
                {
                    Console.Write((char)value);
                }
            }
        }
        else if (char.IsHighSurrogate((char)value))
        {
            _pendingHighSurrogate = value;
        }
        else if (char.IsLowSurrogate((char)value))
        {
            Console.Write('\uFFFD');
        }
        else
        {
            Console.Write((char)value);
        }

        _outputBusy = false;
        _outputDone = true;
    }

    private void ClearOutput()
    {
        _outputBusy = false;
        _outputDone = true;
        _seenOutput = false;
        _pendingHighSurrogate = null;
    }
}
