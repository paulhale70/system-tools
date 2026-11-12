using System.Diagnostics;
using System.IO;
using System.Text.Json;
using SystemTools.Desktop.Models;

namespace SystemTools.Desktop.Services;

/// <summary>
/// Runs analyze-dump.ps1 (next to system-diagnostics.ps1) to list the
/// crash dumps on this PC and to analyze one. Results come back through a
/// temp JSON file (-JsonOut); stdout lines are progress for the status bar.
/// </summary>
public sealed class DumpService
{
    private static readonly JsonSerializerOptions Options = new() { PropertyNameCaseInsensitive = true };

    public string ScriptPath { get; }

    public DumpService(string systemDiagnosticsScriptPath)
    {
        var dir = Path.GetDirectoryName(systemDiagnosticsScriptPath)
                  ?? throw new ArgumentException("Cannot derive script dir", nameof(systemDiagnosticsScriptPath));
        ScriptPath = Path.Combine(dir, "analyze-dump.ps1");
        if (!File.Exists(ScriptPath))
            throw new FileNotFoundException("analyze-dump.ps1 not found next to system-diagnostics.ps1.", ScriptPath);
    }

    public async Task<DumpListResult> ListAsync(int days = 90, CancellationToken cancel = default)
    {
        var json = await RunAsync(new[] { "-List", "-Days", days.ToString() }, _ => { }, cancel);
        return Deserialize<DumpListResult>(json) ?? new DumpListResult();
    }

    public async Task<DumpAnalysisResult> AnalyzeAsync(string dumpPath, Action<string> onLine, CancellationToken cancel = default)
    {
        var json = await RunAsync(new[] { "-Path", dumpPath, "-NoOpen" }, onLine, cancel);
        return Deserialize<DumpAnalysisResult>(json)
               ?? new DumpAnalysisResult { Error = "The analysis didn't produce a result. See the status bar for the last message." };
    }

    private static T? Deserialize<T>(string? json) where T : class
    {
        if (string.IsNullOrWhiteSpace(json)) return null;
        try { return JsonSerializer.Deserialize<T>(json, Options); }
        catch (JsonException) { return null; }
    }

    /// <summary>Run the script with -JsonOut and return that file's text (or null).</summary>
    private async Task<string?> RunAsync(IEnumerable<string> args, Action<string> onLine, CancellationToken cancel)
    {
        var jsonPath = Path.Combine(Path.GetTempPath(), $"systemtools-dump-{Guid.NewGuid():N}.json");
        var psi = new ProcessStartInfo("powershell.exe")
        {
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            CreateNoWindow = true,
        };
        foreach (var a in new[] { "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", ScriptPath }) psi.ArgumentList.Add(a);
        foreach (var a in args) psi.ArgumentList.Add(a);
        psi.ArgumentList.Add("-JsonOut");
        psi.ArgumentList.Add(jsonPath);

        using var p = new Process { StartInfo = psi };
        p.OutputDataReceived += (_, e) => { if (!string.IsNullOrWhiteSpace(e.Data)) onLine(e.Data.Trim()); };
        p.ErrorDataReceived  += (_, e) => { if (!string.IsNullOrWhiteSpace(e.Data)) onLine(e.Data.Trim()); };
        p.Start();
        p.BeginOutputReadLine();
        p.BeginErrorReadLine();
        try
        {
            await p.WaitForExitAsync(cancel);
        }
        catch (OperationCanceledException)
        {
            // cdb.exe runs as a child; take it down too.
            try { p.Kill(entireProcessTree: true); } catch (InvalidOperationException) { }
            throw;
        }
        finally
        {
            if (cancel.IsCancellationRequested) TryDelete(jsonPath);
        }

        try { return File.Exists(jsonPath) ? await File.ReadAllTextAsync(jsonPath, CancellationToken.None) : null; }
        finally { TryDelete(jsonPath); }
    }

    private static void TryDelete(string path)
    {
        try { File.Delete(path); } catch (IOException) { } catch (UnauthorizedAccessException) { }
    }
}
