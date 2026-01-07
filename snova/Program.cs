using Snova;

if (args.Length > 0)
{
    var exitCode = AbsoluteTapeTool.Run(args);
    if (exitCode != AbsoluteTapeTool.NotHandled)
    {
        Environment.Exit(exitCode);
    }
}

var cpu = new NovaCpu();
var tty = new NovaConsoleTty();
var paperTape = new NovaPaperTape();
var linePrinter = new NovaLinePrinterDevice();
var unicodeTto = new NovaUnicodeTtoDevice();
var web = new NovaWebDevice();
var json = new NovaJsonDevice(web);
var watchdog = new NovaWatchdogDevice(cpu);
var tc08 = new Tc08();
var tc08Device = new NovaTc08Device(cpu, tc08);
var rtc = new NovaRtcDevice();
cpu.RegisterDevice(tty.InputDevice);
cpu.RegisterDevice(tty.OutputDevice);
cpu.RegisterDevice(paperTape.ReaderDevice);
cpu.RegisterDevice(paperTape.PunchDevice);
cpu.RegisterDevice(linePrinter);
cpu.RegisterDevice(unicodeTto);
cpu.RegisterDevice(web);
cpu.RegisterDevice(json);
cpu.RegisterDevice(watchdog);
cpu.RegisterDevice(tc08Device);
cpu.RegisterDevice(rtc);

Console.CancelKeyPress += (_, e) =>
{
    e.Cancel = true;
    cpu.Halt("Break");
    Console.WriteLine();
    Console.WriteLine("Break: CPU halted.");
};

var monitor = new NovaMonitor(cpu, tty, watchdog, tc08, rtc, paperTape, linePrinter, web, json);
NovaUnixConsole? unixConsole = null;
var unixConsolePath = Environment.GetEnvironmentVariable("SNOVA_UNIX_CONSOLE");
if (!string.IsNullOrWhiteSpace(unixConsolePath))
{
    if (OperatingSystem.IsWindows())
    {
        Console.WriteLine("Unix console disabled on Windows.");
    }
    else
    {
        try
        {
            unixConsole = new NovaUnixConsole(unixConsolePath, monitor);
            Console.WriteLine($"Unix console listening on {unixConsole.Path}.");
        }
        catch (Exception ex)
        {
            Console.WriteLine($"Unix console disabled: {ex.Message}");
        }
    }
}

monitor.Run();
unixConsole?.Dispose();
