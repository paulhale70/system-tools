using System.Diagnostics;
using System.Globalization;

namespace SystemTools.Desktop.Services;

/// <summary>
/// Thin wrapper around schtasks.exe for registering / removing /
/// querying a Windows Scheduled Task that runs system-diagnostics.ps1
/// on a recurring schedule. Avoids the more permissions-sensitive
/// TaskScheduler COM API.
/// </summary>
public sealed class ScheduledTaskService
{
    public const string TaskName = @"SystemTools\WeeklyDiagnostics";

    private readonly string _scriptPath;

    public ScheduledTaskService(string scriptPath) => _scriptPath = scriptPath;

    public bool Exists() => Query() is not null;

    public string? Query()
    {
        var res = Run("/Query", "/TN", TaskName, "/FO", "LIST");
        return res.ExitCode == 0 ? res.StdOut : null;
    }

    public void Register(DayOfWeek day, TimeSpan timeOfDay, IEnumerable<string>? scriptArgs = null)
    {
        Remove(); // idempotent

        var sb = new System.Text.StringBuilder();
        sb.Append("powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File \"")
          .Append(_scriptPath).Append('"');
        if (scriptArgs is not null)
            foreach (var a in scriptArgs) sb.Append(' ').Append(a);

        var args = new List<string>
        {
            "/Create",
            "/SC", "WEEKLY",
            "/D",  DayString(day),
            "/ST", timeOfDay.ToString(@"hh\:mm", CultureInfo.InvariantCulture),
            "/TN", TaskName,
            "/TR", $"\"{sb}\"",
            "/RL", "LIMITED",   // run as current user, non-elevated by default
            "/F",
        };
        var res = Run(args.ToArray());
        if (res.ExitCode != 0)
            throw new InvalidOperationException($"schtasks /Create failed: {res.StdErr.Trim()} {res.StdOut.Trim()}");
    }

    public void Remove()
    {
        var res = Run("/Delete", "/TN", TaskName, "/F");
        // exit 1 just means "task did not exist"; treat as success.
        if (res.ExitCode != 0 && res.ExitCode != 1
            && !res.StdErr.Contains("cannot find", StringComparison.OrdinalIgnoreCase))
        {
            throw new InvalidOperationException($"schtasks /Delete failed: {res.StdErr.Trim()}");
        }
    }

    private static string DayString(DayOfWeek d) => d switch
    {
        DayOfWeek.Sunday    => "SUN",
        DayOfWeek.Monday    => "MON",
        DayOfWeek.Tuesday   => "TUE",
        DayOfWeek.Wednesday => "WED",
        DayOfWeek.Thursday  => "THU",
        DayOfWeek.Friday    => "FRI",
        DayOfWeek.Saturday  => "SAT",
        _ => "MON",
    };

    private sealed record Result(int ExitCode, string StdOut, string StdErr);

    private static Result Run(params string[] args)
    {
        var psi = new ProcessStartInfo("schtasks.exe")
        {
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            CreateNoWindow = true,
        };
        foreach (var a in args) psi.ArgumentList.Add(a);

        using var p = Process.Start(psi)!;
        var stdout = p.StandardOutput.ReadToEnd();
        var stderr = p.StandardError.ReadToEnd();
        p.WaitForExit();
        return new Result(p.ExitCode, stdout, stderr);
    }
}
