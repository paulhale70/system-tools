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
        var json = ReadJsonArray();
        try
        {
            var arr = JsonSerializer.Deserialize<RunHistoryEntry[]>(json, Options);
            return arr ?? Array.Empty<RunHistoryEntry>();
        }
        catch (JsonException)
        {
            return Array.Empty<RunHistoryEntry>();
        }
    }

    /// <summary>
    /// The history file as a JSON array string ("[]" when missing or
    /// unreadable). Collectors before 1.4.0 wrote a bare object after the
    /// very first run; that is wrapped into a one-element array.
    /// </summary>
    public string ReadJsonArray()
    {
        if (!File.Exists(HistoryPath)) return "[]";
        try
        {
            var json = File.ReadAllText(HistoryPath);
            using var doc = JsonDocument.Parse(json, new JsonDocumentOptions { CommentHandling = JsonCommentHandling.Skip });
            return doc.RootElement.ValueKind switch
            {
                JsonValueKind.Array  => doc.RootElement.GetRawText(),
                JsonValueKind.Object => "[" + doc.RootElement.GetRawText() + "]",
                _ => "[]",
            };
        }
        catch (Exception ex) when (ex is JsonException or IOException)
        {
            return "[]";
        }
    }
}
