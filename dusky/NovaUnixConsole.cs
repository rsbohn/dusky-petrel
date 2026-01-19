using System.IO;
using System.Net.Sockets;
using System.Text;
using System.Threading;
using System.Threading.Tasks;

namespace Snova;

public sealed class NovaUnixConsole : IDisposable
{
    private readonly string _path;
    private readonly NovaMonitor _monitor;
    private readonly Socket _listener;
    private readonly CancellationTokenSource _cts = new();
    private readonly Task _acceptLoop;

    public NovaUnixConsole(string path, NovaMonitor monitor)
    {
        _path = path;
        _monitor = monitor;

        if (File.Exists(_path))
        {
            File.Delete(_path);
        }

        _listener = new Socket(AddressFamily.Unix, SocketType.Stream, ProtocolType.Unspecified);
        _listener.Bind(new UnixDomainSocketEndPoint(_path));
        _listener.Listen(5);

        _acceptLoop = Task.Run(AcceptLoopAsync);
    }

    public string Path => _path;

    public void Dispose()
    {
        _cts.Cancel();
        try
        {
            _listener.Close();
        }
        catch
        {
            // Ignore shutdown errors.
        }

        try
        {
            if (File.Exists(_path))
            {
                File.Delete(_path);
            }
        }
        catch
        {
            // Ignore cleanup errors.
        }
    }

    private async Task AcceptLoopAsync()
    {
        while (!_cts.IsCancellationRequested)
        {
            Socket? client = null;
            try
            {
                client = await _listener.AcceptAsync(_cts.Token).ConfigureAwait(false);
            }
            catch (OperationCanceledException)
            {
                break;
            }
            catch
            {
                if (_cts.IsCancellationRequested)
                {
                    break;
                }

                continue;
            }

            _ = Task.Run(() => HandleClientAsync(client, _cts.Token));
        }
    }

    private async Task HandleClientAsync(Socket client, CancellationToken token)
    {
        await using var stream = new NetworkStream(client, ownsSocket: true);
        using var reader = new StreamReader(stream, Encoding.UTF8, detectEncodingFromByteOrderMarks: false, bufferSize: 1024, leaveOpen: true);
        await using var writer = new StreamWriter(stream, new UTF8Encoding(false))
        {
            AutoFlush = true,
            NewLine = "\n"
        };

        while (!token.IsCancellationRequested)
        {
            string? line;
            try
            {
                line = await reader.ReadLineAsync().ConfigureAwait(false);
            }
            catch
            {
                break;
            }

            if (line is null)
            {
                break;
            }

            string response;
            if (string.IsNullOrWhiteSpace(line))
            {
                response = "Empty command.\n";
            }
            else
            {
                response = _monitor.ExecuteCommandLine(line, allowExit: false);
            }

            await writer.WriteAsync(response).ConfigureAwait(false);
        }
    }
}
