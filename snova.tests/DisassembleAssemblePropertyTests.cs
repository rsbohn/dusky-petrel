using Snova;
using Xunit;

namespace Snova.Tests;

public class DisassembleAssemblePropertyTests
{
    [Fact]
    public void DisassembleAssembleRoundTripMatchesCanonicalForm()
    {
        var assembler = new NovaAssembler();
        const ushort address = 0x80;

        for (var word = 0; word <= 0xFFFF; word++)
        {
            var instruction = (ushort)word;
            var text = NovaDisassembler.DisassembleInstruction(address, instruction);
            var source = $"ORG {Convert.ToString(address, 8)}\n{text}\n";
            var result = assembler.Assemble(source);

            Assert.True(result.Success, $"Failed to assemble: {text}");

            var assembledWord = result.Words.First(w => w.Address == address).Value;
            var roundTrip = NovaDisassembler.DisassembleInstruction(address, assembledWord);
            Assert.Equal(text, roundTrip);
        }
    }
}
