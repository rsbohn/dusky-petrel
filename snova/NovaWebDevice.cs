using System;
using System.Collections.Generic;
using System.Net.Http;
using System.Net.Sockets;
using System.Security.Authentication;
using System.Text;
using System.Threading.Tasks;

namespace Snova;

public sealed class NovaWebDevice : INovaIoDevice
{
    public const int DefaultDeviceCode = 18; // 0o22

    private const int BlockWords = 128;
    private const ushort ControlMethodMask = 0x0001;
    private const ushort ControlModeMask = 0x0002;

    private readonly HttpClient _client;
    private readonly List<byte> _urlBytes = new();
    private readonly object _sync = new();

    private ushort _control;
    private bool _busy;
    private bool _done;
    private bool _error;
    private bool _blockReady;
    private bool _eof;
    private bool _head;
    private int _statusCode;
    private int _contentTypeCode;
    private int _errorCode;
    private int _payloadLength;
    private int _metaIndex;
    private int _currentBlock;
    private int _wordIndex;
    private ushort[] _dataWords = Array.Empty<ushort>();
    private byte[] _responseBytes = Array.Empty<byte>();
    private string? _responseCharset;
    private bool _hasResponse;

    public NovaWebDevice(HttpClient? client = null, int deviceCode = DefaultDeviceCode)
    {
        _client = client ?? new HttpClient
        {
            Timeout = TimeSpan.FromSeconds(30)
        };
        DeviceCode = deviceCode & 0x3F;
    }

    public int DeviceCode { get; }

    public readonly record struct WebMetadata(
        int StatusCode,
        int PayloadLength,
        int ContentTypeCode,
        int ErrorCode,
        bool HasResponse,
        bool Busy,
        bool Done,
        bool Error,
        bool BlockReady,
        bool Eof,
        bool Head,
        string? Charset);

    public bool TryGetLastMetadata(out WebMetadata metadata)
    {
        lock (_sync)
        {
            metadata = new WebMetadata(
                _statusCode,
                _payloadLength,
                _contentTypeCode,
                _errorCode,
                _hasResponse,
                _busy,
                _done,
                _error,
                _blockReady,
                _eof,
                _head,
                _responseCharset);
            return _done || _busy || _hasResponse || _error;
        }
    }

    public bool OpenUrl(string url, out string? error)
    {
        if (string.IsNullOrWhiteSpace(url))
        {
            error = "URL is empty.";
            return false;
        }

        lock (_sync)
        {
            _urlBytes.Clear();
            var bytes = Encoding.UTF8.GetBytes(url);
            for (var i = 0; i < bytes.Length; i++)
            {
                _urlBytes.Add(bytes[i]);
            }

            _control = 0;
            Refresh();
            if (_error)
            {
                error = $"WEB error {_errorCode}.";
                return false;
            }
        }

        error = null;
        return true;
    }

    public bool TryGetLastResponse(out byte[] bytes, out string? charset)
    {
        lock (_sync)
        {
            if (!_hasResponse)
            {
                bytes = Array.Empty<byte>();
                charset = null;
                return false;
            }

            bytes = _responseBytes.Length == 0 ? Array.Empty<byte>() : (byte[])_responseBytes.Clone();
            charset = _responseCharset;
            return true;
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
                    _urlBytes.Add((byte)(accumulator & 0xFF));
                    return true;
                case NovaIoOpKind.DIA:
                    accumulator = ReadDataWord();
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
                    _control = (ushort)(accumulator & (ControlMethodMask | ControlModeMask));
                    return true;
                case NovaIoOpKind.NIO:
                    if (op.Clear)
                    {
                        ClearState();
                    }
                    if (op.Start)
                    {
                        Refresh();
                    }
                    if (op.Pulse)
                    {
                        AdvanceBlock();
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
        if (_blockReady)
        {
            status |= 1 << 3;
        }
        if (_eof)
        {
            status |= 1 << 4;
        }
        if (_head)
        {
            status |= 1 << 5;
        }

        return (ushort)status;
    }

    private ushort GetMetadataWord(int index)
    {
        return index switch
        {
            0 => (ushort)(_statusCode & 0xFFFF),
            1 => (ushort)(_payloadLength & 0xFFFF),
            2 => (ushort)((_payloadLength >> 16) & 0xFFFF),
            3 => (ushort)(_contentTypeCode & 0xFFFF),
            4 => (ushort)(_errorCode & 0xFFFF),
            _ => 0
        };
    }

    private ushort ReadDataWord()
    {
        if (!_blockReady)
        {
            return 0;
        }

        var globalIndex = _currentBlock * BlockWords + _wordIndex;
        var value = globalIndex < _dataWords.Length ? _dataWords[globalIndex] : (ushort)0;
        _wordIndex++;

        if (globalIndex + 1 >= _dataWords.Length)
        {
            _eof = true;
        }

        if (_wordIndex >= BlockWords)
        {
            _wordIndex = 0;
            _blockReady = false;
            if ((_currentBlock + 1) * BlockWords >= _dataWords.Length)
            {
                _eof = true;
            }
        }

        return value;
    }

    private void AdvanceBlock()
    {
        if (_blockReady || _eof)
        {
            return;
        }

        _currentBlock++;
        _blockReady = _currentBlock * BlockWords < _dataWords.Length;
        if (!_blockReady)
        {
            _eof = true;
        }
    }

    private void Refresh()
    {
        _busy = true;
        _done = false;
        _error = false;
        _blockReady = false;
        _eof = false;
        _head = false;
        _statusCode = 0;
        _contentTypeCode = 0;
        _errorCode = 0;
        _payloadLength = 0;
        _metaIndex = 0;
        _currentBlock = 0;
        _wordIndex = 0;
        _dataWords = Array.Empty<ushort>();
        _responseBytes = Array.Empty<byte>();
        _responseCharset = null;
        _hasResponse = false;

        var urlText = Encoding.UTF8.GetString(_urlBytes.ToArray()).Trim();
        if (!Uri.TryCreate(urlText, UriKind.Absolute, out var uri))
        {
            SetError(WebError.BadUrl);
            return;
        }

        if (!string.Equals(uri.Scheme, Uri.UriSchemeHttp, StringComparison.OrdinalIgnoreCase) &&
            !string.Equals(uri.Scheme, Uri.UriSchemeHttps, StringComparison.OrdinalIgnoreCase))
        {
            SetError(WebError.UnsupportedScheme);
            return;
        }

        var method = (_control & ControlMethodMask) != 0 ? HttpMethod.Head : HttpMethod.Get;
        _head = method == HttpMethod.Head;

        try
        {
            using var request = new HttpRequestMessage(method, uri);
            using var response = _client.SendAsync(request).GetAwaiter().GetResult();
            _statusCode = (int)response.StatusCode;

            var mediaType = response.Content.Headers.ContentType?.MediaType;
            var charset = response.Content.Headers.ContentType?.CharSet;
            _contentTypeCode = MapContentType(mediaType);

            if (_head)
            {
                if (response.Content.Headers.ContentLength.HasValue)
                {
                    _payloadLength = (int)Math.Min(response.Content.Headers.ContentLength.Value, int.MaxValue);
                }
                _responseBytes = Array.Empty<byte>();
                _responseCharset = charset;
                _hasResponse = true;
                _eof = true;
                _done = true;
                _busy = false;
                return;
            }

            var bytes = response.Content.ReadAsByteArrayAsync().GetAwaiter().GetResult();
            _payloadLength = bytes.Length;
            _responseBytes = bytes;
            _responseCharset = charset;
            _hasResponse = true;

            var useUtf16 = (_control & ControlModeMask) != 0;
            if (useUtf16)
            {
                var encoding = ResolveEncoding(bytes, charset);
                var text = encoding.GetString(bytes);
                _dataWords = new ushort[text.Length];
                for (var i = 0; i < text.Length; i++)
                {
                    _dataWords[i] = text[i];
                }
            }
            else
            {
                _dataWords = new ushort[bytes.Length];
                for (var i = 0; i < bytes.Length; i++)
                {
                    _dataWords[i] = bytes[i];
                }
            }

            _blockReady = _dataWords.Length > 0;
            _eof = _dataWords.Length == 0;
            _done = true;
            _busy = false;
        }
        catch (TaskCanceledException)
        {
            SetError(WebError.Timeout);
        }
        catch (HttpRequestException ex)
        {
            SetError(MapHttpError(ex));
        }
        catch (Exception)
        {
            SetError(WebError.ReadFail);
        }
    }

    private void ClearState()
    {
        _urlBytes.Clear();
        _control = 0;
        _busy = false;
        _done = false;
        _error = false;
        _blockReady = false;
        _eof = false;
        _head = false;
        _statusCode = 0;
        _contentTypeCode = 0;
        _errorCode = 0;
        _payloadLength = 0;
        _metaIndex = 0;
        _currentBlock = 0;
        _wordIndex = 0;
        _dataWords = Array.Empty<ushort>();
        _responseBytes = Array.Empty<byte>();
        _responseCharset = null;
        _hasResponse = false;
    }

    private void SetError(WebError error)
    {
        _error = true;
        _busy = false;
        _done = true;
        _blockReady = false;
        _eof = true;
        _errorCode = (int)error;
        _hasResponse = false;
        _responseBytes = Array.Empty<byte>();
        _responseCharset = null;
    }

    private static int MapContentType(string? mediaType)
    {
        return mediaType?.ToLowerInvariant() switch
        {
            "text/plain" => 1,
            "text/html" => 2,
            "application/json" => 3,
            "application/octet-stream" => 4,
            _ => 0
        };
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

    private static WebError MapHttpError(HttpRequestException ex)
    {
        if (ex.InnerException is SocketException socket)
        {
            return socket.SocketErrorCode switch
            {
                SocketError.HostNotFound => WebError.ResolveFail,
                SocketError.TryAgain => WebError.ResolveFail,
                SocketError.NoData => WebError.ResolveFail,
                SocketError.NetworkUnreachable => WebError.ConnectFail,
                SocketError.ConnectionRefused => WebError.ConnectFail,
                SocketError.TimedOut => WebError.Timeout,
                _ => WebError.ConnectFail
            };
        }

        if (ex.InnerException is AuthenticationException)
        {
            return WebError.TlsFail;
        }

        return WebError.ConnectFail;
    }

    private enum WebError
    {
        Ok = 0,
        BadUrl = 1,
        ResolveFail = 2,
        ConnectFail = 3,
        TlsFail = 4,
        Timeout = 5,
        ReadFail = 6,
        UnsupportedScheme = 7,
        TooLarge = 8
    }
}
