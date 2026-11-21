using Snova;
using Xunit;

namespace Snova.Tests;

public sealed class DskBootTests
{
    [Fact]
    public void BootDskLoadsSectorZeroAndResetsControllerOnRepeatedBoot()
    {
        var path = Path.Combine(Path.GetTempPath(), $"snova-boot-{Guid.NewGuid():N}.img");
        try
        {
            using (var stream = new FileStream(path, FileMode.CreateNew))
            using (var writer = new BinaryWriter(stream))
            {
                stream.SetLength((long)DskImage.SectorsPerDrive * DskImage.BytesPerSector);
                stream.Position = 0x80 * 2;
                writer.Write((ushort)0x663F); // HALT (0o63077)
                stream.Position = 0xFF * 2;
                writer.Write((ushort)0x80); // JMP 0o200
            }
            var disk = new DskImage();
            Assert.True(disk.Attach(0, path, false, out var error), error);
            var cpu = new NovaCpu();
            var device = new NovaDskDevice(cpu, disk);
            cpu.RegisterDevice(device);
            var monitor = new NovaMonitor(cpu, dsk: disk, dskDevice: device);

            for (var i = 0; i < 2; i++)
            {
                ushort value = 7;
                device.ExecuteIo(new NovaIoOp(NovaIoOpKind.DOA, 16, 0, false, false, false), ref value, out _);
                device.ExecuteIo(new NovaIoOp(NovaIoOpKind.DOB, 16, 0, false, false, false), ref value, out _);
                var output = monitor.ExecuteCommandLine("boot dsk", allowExit: false);
                Assert.Contains("HALT=True", output);
                Assert.Equal((ushort)0x81, cpu.ProgramCounter);
                Assert.Equal((ushort)0x80, cpu.ReadMemory(0xFF));
            }
        }
        finally { File.Delete(path); }
    }

    [Fact]
    public void BootWithoutDiskDoesNotResetCpu()
    {
        var cpu = new NovaCpu();
        var disk = new DskImage();
        var device = new NovaDskDevice(cpu, disk);
        var monitor = new NovaMonitor(cpu, dsk: disk, dskDevice: device);
        cpu.WriteMemory(10, 123);
        var output = monitor.ExecuteCommandLine("boot dsk", allowExit: false);
        Assert.Contains("attached DSK0", output);
        Assert.Equal((ushort)123, cpu.ReadMemory(10));
    }
}
