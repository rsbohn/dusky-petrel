using Snova;

var cpu = new NovaCpu();
var tty = new NovaConsoleTty();
var watchdog = new NovaWatchdogDevice(cpu);
cpu.RegisterDevice(tty.InputDevice);
cpu.RegisterDevice(tty.OutputDevice);
cpu.RegisterDevice(watchdog);

Console.CancelKeyPress += (_, e) =>
{
    e.Cancel = true;
    cpu.Halt("Break");
    Console.WriteLine();
    Console.WriteLine("Break: CPU halted.");
};

var monitor = new NovaMonitor(cpu, tty, watchdog);
monitor.Run();
