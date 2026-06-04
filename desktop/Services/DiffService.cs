using System.Diagnostics;
using System.IO;

namespace SystemTools.Desktop.Services;

/// <summary>
/// Invokes diff-diagnostics.ps1 between two report folders or zips
/// and returns the resulting text.
/// </summary>
public sealed class DiffService
{
    public string ScriptPath { get; }

    public DiffService(string systemDiagnosticsScriptPath)
    {
        var dir = Path.GetDirectoryName(systemDiagnosticsScriptPath)
                  ?? throw new ArgumentException("Cannot derive script dir", nameof(systemDiagnosticsScriptPath));
        ScriptPath = Path.Combine(dir, "diff-diagnostics.ps1");
        if (!File.Exists(ScriptPath))
            throw new FileNotFoundException("diff-diagnostics.ps1 not found next to system-diagnostics.ps1.", ScriptPath);
    }

    public async Task<string> RunAsync(string oldPath, string newPath, CancellationToken cancel = default)
    {
        var psi = new ProcessStartInfo("powershell.exe")
        {
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            CreateNoWindow = true,
        };
        psi.ArgumentList.Add("-NoProfile");
        psi.ArgumentList.Add("-ExecutionPolicy");
        psi.ArgumentList.Add("Bypass");
        psi.ArgumentList.Add("-File");
        psi.ArgumentList.Add(ScriptPath);
        psi.ArgumentList.Add("-Old");
        psi.ArgumentList.Add(oldPath);
        psi.ArgumentList.Add("-New");
        psi.ArgumentList.Add(newPath);

        using var p = Process.Start(psi)!;
        var outTask = p.StandardOutput.ReadToEndAsync(cancel);
        var errTask = p.StandardError.ReadToEndAsync(cancel);
        await p.WaitForExitAsync(cancel);
        var stdout = await outTask;
        var stderr = await errTask;
        return string.IsNullOrEmpty(stderr) ? stdout : stdout + "\n--- stderr ---\n" + stderr;
    }
}
