using Snova;
using Xunit;

namespace Snova.Tests;

public class AssemblerForwardReferenceTests
{
    [Fact]
    public void WordForwardReferenceContainsAddressNotInstruction()
    {
        var result = new NovaAssembler().Assemble("""
            ORG 0o213
            TYOUTP: DW TYOUT
            ORG 0o3611
            TYOUT: STA AC3, 0o101
            """);

        Assert.True(result.Success, string.Join("\n", result.Diagnostics));
        Assert.Equal(Convert.ToUInt16("3611", 8), result.Words.Single(w => w.Address == Convert.ToUInt16("213", 8)).Value);
        Assert.NotEqual(result.Words.Single(w => w.Address == Convert.ToUInt16("3611", 8)).Value,
            result.Words.Single(w => w.Address == Convert.ToUInt16("213", 8)).Value);
    }
}
