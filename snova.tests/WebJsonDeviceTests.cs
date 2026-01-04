using System;
using System.Collections.Generic;
using System.Net;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Text;
using Snova;
using Xunit;

namespace Snova.Tests;

public sealed class WebJsonDeviceTests
{
    private const ushort StatusDone = 1 << 1;
    private const ushort StatusError = 1 << 2;
    private const ushort StatusBlock = 1 << 3;
    private const ushort StatusEof = 1 << 4;
    private const ushort StatusHead = 1 << 5;

    [Fact]
    public void WebDevice_GetByteMode_ReturnsPayloadAndMetadata()
    {
        var handler = new TestHttpHandler(_ =>
        {
            var response = new HttpResponseMessage(HttpStatusCode.OK)
            {
                Content = new StringContent("Hello", Encoding.UTF8, "text/plain")
            };
            response.Content.Headers.ContentLength = 5;
            return response;
        });

        var web = new NovaWebDevice(new HttpClient(handler));
        SendBytes(web, "https://example.test/hello");
        Execute(web, NovaIoOpKind.DOC, 0);
        Execute(web, NovaIoOpKind.NIO, 0, start: true);

        var status = Execute(web, NovaIoOpKind.DIB, 0);
        Assert.True((status & StatusDone) != 0);
        Assert.True((status & StatusBlock) != 0);
        Assert.False((status & StatusError) != 0);

        Assert.Equal(200, ReadMeta(web, 0));
        Assert.Equal(5, ReadMeta(web, 1));
        Assert.Equal(0, ReadMeta(web, 2));
        Assert.Equal(1, ReadMeta(web, 3));
        Assert.Equal(0, ReadMeta(web, 4));

        var bytes = new List<byte>();
        for (var i = 0; i < 5; i++)
        {
            bytes.Add((byte)Execute(web, NovaIoOpKind.DIA, 0));
        }

        Assert.Equal("Hello", Encoding.ASCII.GetString(bytes.ToArray()));
        status = Execute(web, NovaIoOpKind.DIB, 0);
        Assert.True((status & StatusEof) != 0);
    }

    [Fact]
    public void WebDevice_Head_SetsHeadAndEof()
    {
        var handler = new TestHttpHandler(_ =>
        {
            var response = new HttpResponseMessage(HttpStatusCode.NoContent)
            {
                Content = new ByteArrayContent(Array.Empty<byte>())
            };
            response.Content.Headers.ContentType = new MediaTypeHeaderValue("text/plain");
            response.Content.Headers.ContentLength = 0;
            return response;
        });

        var web = new NovaWebDevice(new HttpClient(handler));
        SendBytes(web, "https://example.test/empty");
        Execute(web, NovaIoOpKind.DOC, 0x0001);
        Execute(web, NovaIoOpKind.NIO, 0, start: true);

        var status = Execute(web, NovaIoOpKind.DIB, 0);
        Assert.True((status & StatusDone) != 0);
        Assert.True((status & StatusHead) != 0);
        Assert.True((status & StatusEof) != 0);
        Assert.False((status & StatusBlock) != 0);
    }

    [Fact]
    public void JsonDevice_Query_ReturnsValue()
    {
        var handler = new TestHttpHandler(_ =>
        {
            var json = "{\"result\":[{\"t0\":\"2026-01-07T18:55:00Z\",\"name\":\"Starlink (6-96)\",\"launch_description\":\"Desc\"}]}";
            var response = new HttpResponseMessage(HttpStatusCode.OK)
            {
                Content = new StringContent(json, Encoding.UTF8, "application/json")
            };
            response.Content.Headers.ContentLength = Encoding.UTF8.GetByteCount(json);
            return response;
        });

        var web = new NovaWebDevice(new HttpClient(handler));
        SendBytes(web, "https://example.test/json");
        Execute(web, NovaIoOpKind.DOC, 0);
        Execute(web, NovaIoOpKind.NIO, 0, start: true);

        var jsonDevice = new NovaJsonDevice(web);
        SendQuery(jsonDevice, "/result/0/name");
        Execute(jsonDevice, NovaIoOpKind.DOC, 0);
        Execute(jsonDevice, NovaIoOpKind.NIO, 0, start: true);

        Assert.Equal(1, ReadMeta(jsonDevice, 0));
        var length = ReadMeta(jsonDevice, 2);
        var bytes = new byte[length];
        for (var i = 0; i < length; i++)
        {
            bytes[i] = (byte)Execute(jsonDevice, NovaIoOpKind.DIA, 0);
        }

        Assert.Equal("Starlink (6-96)", Encoding.UTF8.GetString(bytes));
    }

    [Fact]
    public void JsonDevice_StrictMissing_ReturnsError()
    {
        var handler = new TestHttpHandler(_ =>
        {
            var json = "{\"result\":[{\"name\":\"Starlink\"}]}";
            var response = new HttpResponseMessage(HttpStatusCode.OK)
            {
                Content = new StringContent(json, Encoding.UTF8, "application/json")
            };
            response.Content.Headers.ContentLength = Encoding.UTF8.GetByteCount(json);
            return response;
        });

        var web = new NovaWebDevice(new HttpClient(handler));
        SendBytes(web, "https://example.test/json");
        Execute(web, NovaIoOpKind.DOC, 0);
        Execute(web, NovaIoOpKind.NIO, 0, start: true);

        var jsonDevice = new NovaJsonDevice(web);
        SendQuery(jsonDevice, "/result/0/missing");
        Execute(jsonDevice, NovaIoOpKind.DOC, 0x0002);
        Execute(jsonDevice, NovaIoOpKind.NIO, 0, start: true);

        var status = Execute(jsonDevice, NovaIoOpKind.DIB, 0);
        Assert.True((status & StatusError) != 0);
        Assert.Equal(3, ReadMeta(jsonDevice, 1));
    }

    [Fact]
    public void JsonDevice_Utf16Mode_ReturnsUnicodeValue()
    {
        var handler = new TestHttpHandler(_ =>
        {
            var json = "{\"result\":[{\"time\":\"6:55\\u202fPM\"}]}";
            var response = new HttpResponseMessage(HttpStatusCode.OK)
            {
                Content = new StringContent(json, Encoding.UTF8, "application/json")
            };
            response.Content.Headers.ContentLength = Encoding.UTF8.GetByteCount(json);
            return response;
        });

        var web = new NovaWebDevice(new HttpClient(handler));
        SendBytes(web, "https://example.test/json");
        Execute(web, NovaIoOpKind.DOC, 0);
        Execute(web, NovaIoOpKind.NIO, 0, start: true);

        var jsonDevice = new NovaJsonDevice(web);
        SendQuery(jsonDevice, "/result/0/time");
        Execute(jsonDevice, NovaIoOpKind.DOC, 0x0001);
        Execute(jsonDevice, NovaIoOpKind.NIO, 0, start: true);

        Assert.Equal(1, ReadMeta(jsonDevice, 0));
        var length = ReadMeta(jsonDevice, 2);
        var chars = new char[length];
        for (var i = 0; i < length; i++)
        {
            chars[i] = (char)Execute(jsonDevice, NovaIoOpKind.DIA, 0);
        }

        Assert.Equal("6:55\u202fPM", new string(chars));
    }

    private static void SendBytes(NovaWebDevice web, string text)
    {
        foreach (var b in Encoding.UTF8.GetBytes(text))
        {
            Execute(web, NovaIoOpKind.DOA, b);
        }
    }

    private static void SendQuery(NovaJsonDevice jsonDevice, string query)
    {
        foreach (var b in Encoding.UTF8.GetBytes(query))
        {
            Execute(jsonDevice, NovaIoOpKind.DOA, b);
        }

        Execute(jsonDevice, NovaIoOpKind.DOA, 0);
    }

    private static ushort ReadMeta(INovaIoDevice device, ushort index)
    {
        Execute(device, NovaIoOpKind.DOB, index);
        return Execute(device, NovaIoOpKind.DIC, 0);
    }

    private static ushort Execute(INovaIoDevice device, NovaIoOpKind kind, ushort accumulator, bool start = false, bool clear = false, bool pulse = false)
    {
        var acc = accumulator;
        var op = new NovaIoOp(kind, device.DeviceCode, 0, start, clear, pulse);
        var handled = device.ExecuteIo(op, ref acc, out _);
        Assert.True(handled);
        return acc;
    }

    private sealed class TestHttpHandler : HttpMessageHandler
    {
        private readonly Func<HttpRequestMessage, HttpResponseMessage> _handler;

        public TestHttpHandler(Func<HttpRequestMessage, HttpResponseMessage> handler)
        {
            _handler = handler;
        }

        protected override System.Threading.Tasks.Task<HttpResponseMessage> SendAsync(
            HttpRequestMessage request,
            System.Threading.CancellationToken cancellationToken)
        {
            return System.Threading.Tasks.Task.FromResult(_handler(request));
        }
    }
}
