using System;
using System.Collections.Generic;
using System.Text;
using System.Text.Json;

namespace Snova;

public sealed class NovaJsonDevice : INovaIoDevice
{
    public const int DefaultDeviceCode = 21; // 0o25

    private const ushort ControlModeMask = 0x0001;
    private const ushort ControlStrictMask = 0x0002;
    private const ushort ControlSourceMask = 0x0004;

    private readonly NovaWebDevice _web;
    private readonly List<byte> _queryBytes = new();
    private readonly object _sync = new();

    private ushort _control;
    private bool _busy;
    private bool _done;
    private bool _error;
    private bool _valueReady;
    private bool _eof;
    private int _typeCode;
    private int _errorCode;
    private int _metaIndex;
    private int _readIndex;
    private ushort[] _valueWords = Array.Empty<ushort>();

    public NovaJsonDevice(NovaWebDevice web, int deviceCode = DefaultDeviceCode)
    {
        _web = web ?? throw new ArgumentNullException(nameof(web));
        DeviceCode = deviceCode & 0x3F;
    }

    public int DeviceCode { get; }

    public readonly record struct JsonMetadata(
        int TypeCode,
        int ErrorCode,
        int ValueLength,
        bool Busy,
        bool Done,
        bool Error,
        bool ValueReady,
        bool Eof);

    public bool TryGetLastMetadata(out JsonMetadata metadata)
    {
        lock (_sync)
        {
            metadata = new JsonMetadata(
                _typeCode,
                _errorCode,
                _valueWords.Length,
                _busy,
                _done,
                _error,
                _valueReady,
                _eof);
            return _done || _busy || _error || _valueReady || _eof;
        }
    }

    public bool ExecuteIo(NovaIoOp op, ref ushort accumulator, out bool skip)
    {
        skip = false;
        lock (_sync)
        {
            switch (op.Kind)
            {
                case NovaIoOpKind.DOA:
                    _queryBytes.Add((byte)(accumulator & 0xFF));
                    return true;
                case NovaIoOpKind.DIA:
                    accumulator = ReadValueWord();
                    return true;
                case NovaIoOpKind.DIB:
                    accumulator = GetStatusWord();
                    return true;
                case NovaIoOpKind.DOB:
                    _metaIndex = accumulator & 0xFFFF;
                    return true;
                case NovaIoOpKind.DIC:
                    accumulator = GetMetadataWord(_metaIndex);
                    _metaIndex = (_metaIndex + 1) & 0xFFFF;
                    return true;
                case NovaIoOpKind.DOC:
                    _control = (ushort)(accumulator & (ControlModeMask | ControlStrictMask | ControlSourceMask));
                    return true;
                case NovaIoOpKind.NIO:
                    if (op.Clear)
                    {
                        ClearState();
                    }
                    if (op.Start)
                    {
                        ExecuteQuery();
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
    }

    private ushort GetStatusWord()
    {
        var status = 0;
        if (_busy)
        {
            status |= 1 << 0;
        }
        if (_done)
        {
            status |= 1 << 1;
        }
        if (_error)
        {
            status |= 1 << 2;
        }
        if (_valueReady)
        {
            status |= 1 << 3;
        }
        if (_eof)
        {
            status |= 1 << 4;
        }

        return (ushort)status;
    }

    private ushort GetMetadataWord(int index)
    {
        return index switch
        {
            0 => (ushort)(_typeCode & 0xFFFF),
            1 => (ushort)(_errorCode & 0xFFFF),
            2 => (ushort)(_valueWords.Length & 0xFFFF),
            3 => (ushort)((_valueWords.Length >> 16) & 0xFFFF),
            _ => 0
        };
    }

    private ushort ReadValueWord()
    {
        if (_readIndex >= _valueWords.Length)
        {
            _valueReady = false;
            _eof = true;
            return 0;
        }

        var value = _valueWords[_readIndex];
        _readIndex++;
        _valueReady = _readIndex < _valueWords.Length;
        _eof = !_valueReady;
        return value;
    }

    private void ExecuteQuery()
    {
        _busy = true;
        _done = false;
        _error = false;
        _valueReady = false;
        _eof = false;
        _typeCode = 0;
        _errorCode = 0;
        _metaIndex = 0;
        _readIndex = 0;
        _valueWords = Array.Empty<ushort>();

        if ((_control & ControlSourceMask) != 0)
        {
            SetError(JsonError.NoSource);
            return;
        }

        if (!_web.TryGetLastResponse(out var bytes, out var charset))
        {
            SetError(JsonError.NoSource);
            return;
        }

        var query = DecodeQuery(_queryBytes);
        if (!TryParseQueryPath(query, out var segments))
        {
            SetError(JsonError.BadPath);
            return;
        }

        try
        {
            var encoding = ResolveEncoding(bytes, charset);
            var jsonText = encoding.GetString(bytes);
            using var doc = JsonDocument.Parse(jsonText);
            if (!TryNavigate(doc.RootElement, segments, out var element, out var error))
            {
                SetError(error);
                return;
            }

            var strict = (_control & ControlStrictMask) != 0;
            if (element.ValueKind == JsonValueKind.Undefined)
            {
                if (strict)
                {
                    SetError(JsonError.BadPath);
                    return;
                }

                _typeCode = 0;
                _eof = true;
                _done = true;
                _busy = false;
                return;
            }

            var (typeCode, valueText) = FormatValue(element);
            _typeCode = typeCode;
            SetValueOutput(valueText);
            _done = true;
            _busy = false;
        }
        catch (JsonException)
        {
            SetError(JsonError.BadJson);
        }
        catch (Exception)
        {
            SetError(JsonError.Internal);
        }
    }

    private static string DecodeQuery(List<byte> queryBytes)
    {
        if (queryBytes.Count == 0)
        {
            return string.Empty;
        }

        var bytes = queryBytes.ToArray();
        var length = Array.IndexOf(bytes, (byte)0);
        if (length < 0)
        {
            length = bytes.Length;
        }

        return Encoding.UTF8.GetString(bytes, 0, length).Trim();
    }

    private static bool TryParseQueryPath(string query, out string[] segments)
    {
        if (string.IsNullOrEmpty(query))
        {
            segments = Array.Empty<string>();
            return true;
        }

        if (!query.StartsWith("/", StringComparison.Ordinal))
        {
            segments = Array.Empty<string>();
            return false;
        }

        segments = query.Split('/', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        return true;
    }

    private static bool TryNavigate(JsonElement root, string[] segments, out JsonElement element, out JsonError error)
    {
        element = root;
        error = JsonError.Ok;
        foreach (var segment in segments)
        {
            if (element.ValueKind == JsonValueKind.Object)
            {
                if (!element.TryGetProperty(segment, out element))
                {
                    element = default;
                    return true;
                }
                continue;
            }

            if (element.ValueKind == JsonValueKind.Array)
            {
                if (!int.TryParse(segment, out var index))
                {
                    error = JsonError.TypeMismatch;
                    return false;
                }

                if (index < 0 || index >= element.GetArrayLength())
                {
                    element = default;
                    return true;
                }

                element = element[index];
                continue;
            }

            error = JsonError.TypeMismatch;
            element = default;
            return false;
        }

        return true;
    }

    private static (int TypeCode, string ValueText) FormatValue(JsonElement element)
    {
        return element.ValueKind switch
        {
            JsonValueKind.String => (1, element.GetString() ?? string.Empty),
            JsonValueKind.Number => (2, element.GetRawText()),
            JsonValueKind.True => (3, "true"),
            JsonValueKind.False => (3, "false"),
            JsonValueKind.Null => (4, "null"),
            JsonValueKind.Object => (5, element.GetRawText()),
            JsonValueKind.Array => (6, element.GetRawText()),
            _ => (0, string.Empty)
        };
    }

    private void SetValueOutput(string value)
    {
        var utf16 = (_control & ControlModeMask) != 0;
        if (utf16)
        {
            _valueWords = new ushort[value.Length];
            for (var i = 0; i < value.Length; i++)
            {
                _valueWords[i] = value[i];
            }
        }
        else
        {
            var bytes = Encoding.UTF8.GetBytes(value);
            _valueWords = new ushort[bytes.Length];
            for (var i = 0; i < bytes.Length; i++)
            {
                _valueWords[i] = bytes[i];
            }
        }

        _valueReady = _valueWords.Length > 0;
        _eof = _valueWords.Length == 0;
    }

    private void ClearState()
    {
        _queryBytes.Clear();
        _control = 0;
        _busy = false;
        _done = false;
        _error = false;
        _valueReady = false;
        _eof = false;
        _typeCode = 0;
        _errorCode = 0;
        _metaIndex = 0;
        _readIndex = 0;
        _valueWords = Array.Empty<ushort>();
    }

    private void SetError(JsonError error)
    {
        _error = true;
        _busy = false;
        _done = true;
        _valueReady = false;
        _eof = true;
        _errorCode = (int)error;
    }

    private static Encoding ResolveEncoding(byte[] bytes, string? charset)
    {
        if (!string.IsNullOrWhiteSpace(charset))
        {
            try
            {
                return Encoding.GetEncoding(charset);
            }
            catch (ArgumentException)
            {
            }
        }

        if (bytes.Length >= 2)
        {
            if (bytes[0] == 0xFF && bytes[1] == 0xFE)
            {
                return Encoding.Unicode;
            }
            if (bytes[0] == 0xFE && bytes[1] == 0xFF)
            {
                return Encoding.BigEndianUnicode;
            }
        }

        return Encoding.UTF8;
    }

    private enum JsonError
    {
        Ok = 0,
        NoSource = 1,
        BadJson = 2,
        BadPath = 3,
        TypeMismatch = 4,
        Internal = 6
    }
}
