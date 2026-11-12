namespace SystemTools.Desktop.Models;

/// <summary>One crash dump found on this PC (analyze-dump.ps1 -List).</summary>
public sealed class DumpFileInfo
{
    public string Kind { get; set; } = "";
    public string Name { get; set; } = "";
    public string Path { get; set; } = "";
    public double SizeMB { get; set; }
    public string Written { get; set; } = "";

    public string SizeText => SizeMB >= 1024 ? $"{SizeMB / 1024:0.0} GB" : $"{SizeMB:0.#} MB";
}

/// <summary>JSON written by analyze-dump.ps1 -List -JsonOut.</summary>
public sealed class DumpListResult
{
    public bool Elevated { get; set; }
    public string? Note { get; set; }
    public List<DumpFileInfo> Dumps { get; set; } = new();
}

/// <summary>One analyzed dump, as written by analyze-dump.ps1 -JsonOut.</summary>
public sealed class DumpAnalysisItem
{
    public string? Path { get; set; }
    public string? Name { get; set; }
    public string? Kind { get; set; }
    public string? Severity { get; set; }
    public string? Headline { get; set; }
    public string? Hint { get; set; }
    public string? Error { get; set; }
}

/// <summary>JSON written by analyze-dump.ps1 -Path ... -JsonOut.</summary>
public sealed class DumpAnalysisResult
{
    public string? Error { get; set; }
    public string? ReportDir { get; set; }
    public string? Html { get; set; }
    public string? Note { get; set; }
    public List<DumpAnalysisItem> Results { get; set; } = new();
}
