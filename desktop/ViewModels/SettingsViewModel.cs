using System.Diagnostics;
using SystemTools.Desktop.Services;

namespace SystemTools.Desktop.ViewModels;

public sealed class SettingsViewModel : ViewModelBase
{
    private readonly ScheduledTaskService? _sched;
    private readonly UpdateChecker _updates = new();

    private bool _scheduleEnabled;
    private DayOfWeek _scheduleDay = DayOfWeek.Sunday;
    private string _scheduleTime = "08:00";
    private bool _scheduleSanitize;
    private string _scheduleStatus = "";
    private string _updateStatus = "";
    private string _currentVersion = "";
    private string _latestVersion = "";
    private string _releaseUrl = "";
    private bool _updateAvailable;

    public SettingsViewModel(string? systemDiagnosticsScriptPath)
    {
        if (systemDiagnosticsScriptPath is not null)
            _sched = new ScheduledTaskService(systemDiagnosticsScriptPath);

        CurrentVersion = _updates.CurrentVersion;
        ScheduleEnabled = _sched?.Exists() ?? false;
        ScheduleStatus = ScheduleEnabled ? "Scheduled task is active." : "No scheduled task registered.";
    }

    public bool ScheduleEnabled { get => _scheduleEnabled; set => Set(ref _scheduleEnabled, value); }
    public DayOfWeek ScheduleDay { get => _scheduleDay; set => Set(ref _scheduleDay, value); }
    public string ScheduleTime { get => _scheduleTime; set => Set(ref _scheduleTime, value); }
    public bool ScheduleSanitize { get => _scheduleSanitize; set => Set(ref _scheduleSanitize, value); }
    public string ScheduleStatus { get => _scheduleStatus; set => Set(ref _scheduleStatus, value); }

    public string CurrentVersion { get => _currentVersion; set => Set(ref _currentVersion, value); }
    public string LatestVersion  { get => _latestVersion;  set => Set(ref _latestVersion, value); }
    public string ReleaseUrl     { get => _releaseUrl;     set => Set(ref _releaseUrl, value); }
    public string UpdateStatus   { get => _updateStatus;   set => Set(ref _updateStatus, value); }
    public bool   UpdateAvailable { get => _updateAvailable; set => Set(ref _updateAvailable, value); }

    public IEnumerable<DayOfWeek> DaysOfWeek => Enum.GetValues<DayOfWeek>();

    public void ApplySchedule()
    {
        if (_sched is null) { ScheduleStatus = "Diagnostics script not found."; return; }
        try
        {
            if (!ScheduleEnabled)
            {
                _sched.Remove();
                ScheduleStatus = "Scheduled task removed.";
                return;
            }

            if (!TimeSpan.TryParse(ScheduleTime, out var t))
            {
                ScheduleStatus = "Time must be HH:MM (24-hour).";
                return;
            }

            var args = new List<string> { "-ProjectName", "ScheduledRun" };
            if (ScheduleSanitize) args.Add("-Sanitize");

            _sched.Register(ScheduleDay, t, args);
            ScheduleStatus = $"Scheduled weekly on {ScheduleDay} at {ScheduleTime}.";
        }
        catch (Exception ex)
        {
            ScheduleStatus = "Error: " + ex.Message;
        }
    }

    public async Task CheckUpdatesAsync()
    {
        UpdateStatus = "Checking github.com/paulhale70/System-tools for newer release...";
        UpdateAvailable = false;
        var info = await _updates.CheckAsync();
        if (info is null)
        {
            UpdateStatus = "Could not reach GitHub.";
            return;
        }
        LatestVersion = info.LatestVersion;
        ReleaseUrl    = info.HtmlUrl;
        if (info.IsNewer)
        {
            UpdateAvailable = true;
            UpdateStatus = $"Update available: v{info.LatestVersion} (you have v{info.CurrentVersion}).";
        }
        else
        {
            UpdateStatus = $"You are on the latest release (v{info.CurrentVersion}).";
        }
    }

    public void OpenReleasePage()
    {
        if (string.IsNullOrEmpty(ReleaseUrl)) return;
        Process.Start(new ProcessStartInfo(ReleaseUrl) { UseShellExecute = true });
    }
}
