using System.IO;
using System.Text.Json;
using SystemTools.Desktop.Models;

namespace SystemTools.Desktop.Services;

/// <summary>
/// Reads the diagnostics-history.json file written by
/// system-diagnostics.ps1. Lives at %USERPROFILE%\diagnostics-history.json
/// by default.
/// </summary>
public sealed class HistoryReader
{
    private static readonly JsonSerializerOptions Options = new()
    {
        PropertyNameCaseInsensitive = true,
        ReadCommentHandling = JsonCommentHandling.Skip,
    };

    public string HistoryPath { get; }

    public HistoryReader(string? overridePath = null)
    {
        HistoryPath = overridePath ?? Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
            "diagnostics-history.json");
    }

    public IReadOnlyList<RunHistoryEntry> Load()
    {
        if (!File.Exists(HistoryPath)) return Array.Empty<RunHistoryEntry>();
        try
        {
            var json = File.ReadAllText(HistoryPath);
            var arr = JsonSerializer.Deserialize<RunHistoryEntry[]>(json, Options);
            return arr ?? Array.Empty<RunHistoryEntry>();
        }
        catch (JsonException)
        {
            return Array.Empty<RunHistoryEntry>();
        }
    }
}
