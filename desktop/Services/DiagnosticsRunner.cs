using System.Diagnostics;
using System.IO;

namespace SystemTools.Desktop.Services;

/// <summary>
/// Spawns powershell.exe with the bundled system-diagnostics.ps1
/// script. Streams stdout/stderr back to the caller so the GUI can
/// surface progress.
/// </summary>
public sealed class DiagnosticsRunner
{
    public sealed record Options(
        bool Sanitize = false,
        bool IncludeMiniDumps = false,
        int CaptureNetSeconds = 0,
        int PerfSampleSeconds = 5,
        string ProjectName = "System");

    public string ScriptPath { get; }

    public DiagnosticsRunner(string? scriptPathOverride = null)
    {
        ScriptPath = scriptPathOverride ?? ResolveScriptPath();
    }

    /// <summary>
    /// Search order:
    ///   1. Caller override
    ///   2. ./diagnostics/system-diagnostics.ps1 alongside the .exe
    ///   3. ../diagnostics/system-diagnostics.ps1 (dev layout: bin/Debug -> repo root)
    ///   4. %USERPROFILE%\bin\system-diagnostics.ps1 (installed via install.ps1)
    /// </summary>
    private static string ResolveScriptPath()
    {
        var exeDir = AppContext.BaseDirectory;
        string[] candidates =
        {
            Path.Combine(exeDir, "diagnostics", "system-diagnostics.ps1"),
            Path.GetFullPath(Path.Combine(exeDir, "..", "..", "..", "..", "diagnostics", "system-diagnostics.ps1")),
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
                         "bin", "system-diagnostics.ps1"),
        };
        foreach (var c in candidates)
            if (File.Exists(c)) return c;

        throw new FileNotFoundException(
            "system-diagnostics.ps1 not found. Expected next to the .exe in 'diagnostics\\' or in %USERPROFILE%\\bin\\.");
    }

    /// <summary>
    /// Run the script and stream lines as they arrive. Returns the
    /// process exit code.
    /// </summary>
    public async Task<int> RunAsync(Options options, Action<string> onLine, CancellationToken cancel = default)
    {
        var args = new List<string>
        {
            "-NoProfile", "-ExecutionPolicy", "Bypass",
            "-File", $"\"{ScriptPath}\"",
            "-ProjectName", options.ProjectName,
        };
        if (options.Sanitize)         args.Add("-Sanitize");
        if (options.IncludeMiniDumps) args.Add("-IncludeMiniDumps");
        if (options.CaptureNetSeconds > 0)
        {
            args.Add("-CaptureNetSeconds");
            args.Add(options.CaptureNetSeconds.ToString());
        }
        args.Add("-PerfSampleSeconds");
        args.Add(options.PerfSampleSeconds.ToString());

        var psi = new ProcessStartInfo("powershell.exe", string.Join(' ', args))
        {
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            CreateNoWindow = true,
        };

        using var p = new Process { StartInfo = psi, EnableRaisingEvents = true };
        p.OutputDataReceived += (_, e) => { if (e.Data is not null) onLine(e.Data); };
        p.ErrorDataReceived  += (_, e) => { if (e.Data is not null) onLine("[stderr] " + e.Data); };

        p.Start();
        p.BeginOutputReadLine();
        p.BeginErrorReadLine();

        await p.WaitForExitAsync(cancel);
        return p.ExitCode;
    }
}
