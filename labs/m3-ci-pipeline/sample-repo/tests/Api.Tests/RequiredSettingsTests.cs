using Microsoft.Extensions.Configuration;

namespace Keypasco.Demo.Tests;

public class RequiredSettingsTests
{
    private static IConfiguration Config(params (string Key, string Value)[] values) =>
        new ConfigurationBuilder()
            .AddInMemoryCollection(values.Select(v => new KeyValuePair<string, string?>(v.Key, v.Value)))
            .Build();

    [Fact]
    public void NothingMissing_WhenAllSet()
    {
        var config = Config(("DB_HOST", "db"), ("DB_PORT", "5432"), ("DB_NAME", "labdb"), ("DB_USER", "labuser"));
        Assert.Empty(RequiredSettings.Missing(config));
    }

    [Fact]
    public void ReportsDbHost_WhenMissing()
    {
        var config = Config(("DB_PORT", "5432"), ("DB_NAME", "labdb"), ("DB_USER", "labuser"));
        Assert.Equal(["DB_HOST"], RequiredSettings.Missing(config));
    }

    [Fact]
    public void TreatsBlankAsMissing()
    {
        var config = Config(("DB_HOST", " "), ("DB_PORT", "5432"), ("DB_NAME", "labdb"), ("DB_USER", "labuser"));
        Assert.Equal(["DB_HOST"], RequiredSettings.Missing(config));
    }
}
