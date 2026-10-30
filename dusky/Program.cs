using Snova;

var consoleMode = args.Length > 0 && args[0] == "--console";
var consoleImage = consoleMode && args.Length > 1 ? args[1] : null;
if (consoleMode && consoleImage is null)
{
    Console.Error.WriteLine("Usage: Snova --console <tc08-image>");
    return 2;
}

if (args.Length > 0 && !consoleMode)
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
var dsk = new DskImage();
var tc08Device = new NovaTc08Device(cpu, tc08, dsk: dsk);
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

var monitor = new NovaMonitor(cpu, tty, watchdog, tc08, rtc, paperTape, linePrinter, web, json, dsk);
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

if (consoleMode)
{
    var attach = monitor.ExecuteCommandLine($"tc0 attach {consoleImage}", allowExit: false);
    Console.Write(attach);
    var assemble = monitor.ExecuteCommandLine("asm sd/cvit-command.asm", allowExit: false);
    Console.Write(assemble);
    if (!assemble.StartsWith("Assembled ", StringComparison.Ordinal))
    {
        unixConsole?.Dispose();
        return 1;
    }

    cpu.SetProgramCounter(0x600); // 0o3000
    Console.WriteLine("CVIT console active. Enter sends CR; Ctrl+D sends EOT to halt.");
    var runner = Task.Run(() =>
    {
        while (!cpu.Halted)
            cpu.Step();
    });
    while (!cpu.Halted)
    {
        if (Console.KeyAvailable)
        {
            var key = Console.ReadKey(intercept: true);
            if (key.Key == ConsoleKey.Enter)
                tty.EnqueueInputBytes(new byte[] { 0x0D });
            else if (key.Key == ConsoleKey.D && key.Modifiers.HasFlag(ConsoleModifiers.Control))
                tty.EnqueueInputBytes(new byte[] { 0x04 });
            else if (key.Key == ConsoleKey.C && key.Modifiers.HasFlag(ConsoleModifiers.Control))
                cpu.Halt("Break");
            else if (!char.IsControl(key.KeyChar))
                tty.EnqueueInputBytes(System.Text.Encoding.ASCII.GetBytes(key.KeyChar.ToString()));
        }
        else
        {
            Thread.Sleep(10);
        }
    }
    await runner;
}
else
{
    monitor.Run();
}
unixConsole?.Dispose();
return 0;
