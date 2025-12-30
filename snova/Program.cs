using Snova;

var cpu = new NovaCpu();
var tty = new NovaConsoleTty();
var watchdog = new NovaWatchdogDevice(cpu);
var tc08 = new Tc08();
var tc08Device = new NovaTc08Device(cpu, tc08);
cpu.RegisterDevice(tty.InputDevice);
cpu.RegisterDevice(tty.OutputDevice);
cpu.RegisterDevice(watchdog);
cpu.RegisterDevice(tc08Device);

Console.CancelKeyPress += (_, e) =>
{
    e.Cancel = true;
    cpu.Halt("Break");
    Console.WriteLine();
    Console.WriteLine("Break: CPU halted.");
};

var monitor = new NovaMonitor(cpu, tty, watchdog, tc08);
monitor.Run();
