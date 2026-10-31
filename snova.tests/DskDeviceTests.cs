using Snova;
using Xunit;

namespace Snova.Tests;

public sealed class DskDeviceTests
{
    [Fact]
    public void Device_ReadsFull256WordSectorFromRawImage()
    {
        var path = TempPath();
        try
        {
            using (var stream = new FileStream(path, FileMode.CreateNew))
            using (var writer = new BinaryWriter(stream))
            {
                stream.SetLength((long)DskImage.SectorsPerDrive * DskImage.BytesPerSector);
                stream.Position = 7 * DskImage.BytesPerSector;
                for (var i = 0; i < DskImage.WordsPerSector; i++) writer.Write((ushort)(0x4000 + i));
            }

            var disk = new DskImage();
            Assert.True(disk.Attach(0, path, false, out var error), error);
            var cpu = new NovaCpu();
            var device = new NovaTc08Device(cpu, new Tc08(), dsk: disk);
            Execute(device, NovaIoOpKind.DOA, 0x1000);
            Execute(device, NovaIoOpKind.DOB, 7);
            Execute(device, NovaIoOpKind.DOC, 2); // read
            Execute(device, NovaIoOpKind.NIO, 0, start: true);

            for (var i = 0; i < DskImage.WordsPerSector; i++)
                Assert.Equal((ushort)(0x4000 + i), cpu.ReadMemory((ushort)(0x1000 + i)));
            Assert.Equal((ushort)1, (ushort)(Execute(device, NovaIoOpKind.DIC, 0) & 1));
        }
        finally { File.Delete(path); }
    }

    [Fact]
    public void Device_WritesSectorAndRejectsOutOfRangeSectors()
    {
        var path = TempPath();
        try
        {
            using (var stream = new FileStream(path, FileMode.CreateNew))
                stream.SetLength((long)DskImage.SectorsPerDrive * DskImage.BytesPerSector);
            var disk = new DskImage();
            Assert.True(disk.Attach(0, path, false, out var error), error);
            var cpu = new NovaCpu();
            var device = new NovaTc08Device(cpu, new Tc08(), dsk: disk);
            for (var i = 0; i < DskImage.WordsPerSector; i++)
                cpu.WriteMemory((ushort)(0x1200 + i), (ushort)(i ^ 0x55AA));
            Execute(device, NovaIoOpKind.DOA, 0x1200);
            Execute(device, NovaIoOpKind.DOB, 12);
            Execute(device, NovaIoOpKind.DOC, 4); // write
            Execute(device, NovaIoOpKind.NIO, 0, start: true);
            Span<ushort> words = stackalloc ushort[DskImage.WordsPerSector];
            Assert.True(disk.TryReadSector(0, 12, words, out error), error);
            for (var i = 0; i < words.Length; i++) Assert.Equal((ushort)(i ^ 0x55AA), words[i]);

            Execute(device, NovaIoOpKind.DOB, DskImage.SectorsPerDrive);
            Execute(device, NovaIoOpKind.NIO, 0, start: true);
            Assert.Equal((ushort)4, (ushort)(Execute(device, NovaIoOpKind.DIC, 0) & 4));
        }
        finally { File.Delete(path); }
    }

    [Fact]
    public void SimhProtocol_ReadsSectorByLinearAddress()
    {
        var path = TempPath();
        try
        {
            using (var stream = new FileStream(path, FileMode.CreateNew))
            using (var writer = new BinaryWriter(stream))
            {
                stream.SetLength((long)DskImage.SectorsPerDrive * DskImage.BytesPerSector);
                stream.Position = 5 * DskImage.BytesPerSector;
                for (var i = 0; i < DskImage.WordsPerSector; i++) writer.Write((ushort)(0x5000 + i));
            }

            var disk = new DskImage();
            Assert.True(disk.Attach(0, path, false, out var error), error);
            var cpu = new NovaCpu();
            var device = new NovaDskDevice(cpu, disk);
            // SIMH protocol: DOA = sector, DOB = mem addr, NIOS = read.
            Execute(device, NovaIoOpKind.DOA, 5);
            Execute(device, NovaIoOpKind.DOB, 0x1000);
            Execute(device, NovaIoOpKind.NIO, 0, start: true);

            for (var i = 0; i < DskImage.WordsPerSector; i++)
                Assert.Equal((ushort)(0x5000 + i), cpu.ReadMemory((ushort)(0x1000 + i)));
            Assert.Equal(0, Execute(device, NovaIoOpKind.DIA, 0)); // status ok
        }
        finally { File.Delete(path); }
    }

    [Fact]
    public void SimhProtocol_WritesSectorByLinearAddress()
    {
        var path = TempPath();
        try
        {
            using (var stream = new FileStream(path, FileMode.CreateNew))
                stream.SetLength((long)DskImage.SectorsPerDrive * DskImage.BytesPerSector);
            var disk = new DskImage();
            Assert.True(disk.Attach(0, path, false, out var error), error);
            var cpu = new NovaCpu();
            var device = new NovaDskDevice(cpu, disk);
            for (var i = 0; i < DskImage.WordsPerSector; i++)
                cpu.WriteMemory((ushort)(0x1200 + i), (ushort)(i ^ 0x33CC));
            // SIMH protocol: DOA = sector, DOB = mem addr, NIOP = write.
            Execute(device, NovaIoOpKind.DOA, 9);
            Execute(device, NovaIoOpKind.DOB, 0x1200);
            Execute(device, NovaIoOpKind.NIO, 0, pulse: true);

            Span<ushort> words = stackalloc ushort[DskImage.WordsPerSector];
            Assert.True(disk.TryReadSector(0, 9, words, out error), error);
            for (var i = 0; i < words.Length; i++) Assert.Equal((ushort)(i ^ 0x33CC), words[i]);
            Assert.Equal(0, Execute(device, NovaIoOpKind.DIA, 0)); // status ok
        }
        finally { File.Delete(path); }
    }

    private static ushort Execute(NovaTc08Device device, NovaIoOpKind kind, ushort value, bool start = false)
    {
        var ac = value;
        Assert.True(device.ExecuteIo(new NovaIoOp(kind, DskImageDeviceCode, 0, start, false, false), ref ac, out _));
        return ac;
    }

    private static ushort Execute(NovaDskDevice device, NovaIoOpKind kind, ushort value, bool start = false, bool pulse = false)
    {
        var ac = value;
        Assert.True(device.ExecuteIo(new NovaIoOp(kind, DskImageDeviceCode, 0, start, false, pulse), ref ac, out _));
        return ac;
    }

    private const int DskImageDeviceCode = NovaTc08Device.DefaultDeviceCode;
    private static string TempPath() => Path.Combine(Path.GetTempPath(), $"snova-dsk-{Guid.NewGuid():N}.img");
}
