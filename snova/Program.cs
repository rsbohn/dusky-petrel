using Snova;

var cpu = new NovaCpu();
var tty = new NovaConsoleTty();
cpu.RegisterDevice(tty.InputDevice);
cpu.RegisterDevice(tty.OutputDevice);

var monitor = new NovaMonitor(cpu, tty);
monitor.Run();
