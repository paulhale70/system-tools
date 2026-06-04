using System.IO;
using System.Text.Json.Serialization;

namespace SystemTools.Desktop.Models;

/// <summary>
/// One entry as stored in %USERPROFILE%\diagnostics-history.json by
/// system-diagnostics.ps1. Verdict lines are kept as raw strings
/// ("[OK] python -> ...").
/// </summary>
public sealed class RunHistoryEntry
{
    [JsonPropertyName("ts")]        public string Timestamp { get; set; } = "";
    [JsonPropertyName("host")]      public string Host { get; set; } = "";
    [JsonPropertyName("project")]   public string Project { get; set; } = "";
    [JsonPropertyName("version")]   public string Version { get; set; } = "";
    [JsonPropertyName("reportDir")] public string ReportDir { get; set; } = "";
    [JsonPropertyName("counts")]    public RunCounts Counts { get; set; } = new();
    [JsonPropertyName("verdicts")]  public string[] Verdicts { get; set; } = System.Array.Empty<string>();

    // ---- Derived view-model bits used by the history list template. ----

    [JsonIgnore]
    public string DisplayDate
    {
        get
        {
            if (System.DateTime.TryParse(Timestamp, out var dt))
                return dt.ToString("yyyy-MM-dd HH:mm");
            return Timestamp;
        }
    }

    [JsonIgnore] public string ProjectAndHost => $"{Project} | {Host}";
    [JsonIgnore] public int OkCount   => Counts.OK;
    [JsonIgnore] public int WarnCount => Counts.WARN;
    [JsonIgnore] public int FailCount => Counts.FAIL;

    [JsonIgnore]
    public string? ReportHtmlPath
    {
        get
        {
            if (string.IsNullOrEmpty(ReportDir)) return null;
            var p = Path.Combine(ReportDir, "00-summary.html");
            return File.Exists(p) ? p : null;
        }
    }
}

public sealed class RunCounts
{
    [JsonPropertyName("OK")]   public int OK { get; set; }
    [JsonPropertyName("WARN")] public int WARN { get; set; }
    [JsonPropertyName("FAIL")] public int FAIL { get; set; }
}
