using System.Collections.ObjectModel;
using System.Globalization;
using System.IO;
using System.Windows;
using System.Windows.Data;
using SystemTools.Desktop.Models;
using SystemTools.Desktop.Services;

namespace SystemTools.Desktop.ViewModels;

public sealed class MainViewModel : ViewModelBase
{
    private readonly HistoryReader _history = new();
    private readonly DiagnosticsRunner? _runner;
    private bool _canRun = true;
    private bool _sanitize;
    private bool _includeMiniDumps;
    private string _captureNetSeconds = "0";
    private string _perfSampleSeconds = "5";
    private string _statusMessage = "Ready.";
    private RunHistoryEntry? _selectedRun;
    private NavTab _selectedTab = NavTab.Run;

    public MainViewModel()
    {
        try { _runner = new DiagnosticsRunner(); }
        catch (FileNotFoundException ex) { _statusMessage = ex.Message; _canRun = false; }

        var scriptPath = _runner?.ScriptPath;
        Diff     = new DiffViewModel(scriptPath);
        Trends   = new TrendsViewModel();
        Plugins  = new PluginsViewModel(scriptPath);
        Settings = new SettingsViewModel(scriptPath);

        ReloadHistory();
        if (History.Count > 0) SelectedRun = History[0];

        // Background update check on launch; never blocks the UI.
        _ = Task.Run(async () => await Settings.CheckUpdatesAsync());
    }

    // --- Sub-view-models ----------------------------------------------------
    public DiffViewModel     Diff     { get; }
    public TrendsViewModel   Trends   { get; }
    public PluginsViewModel  Plugins  { get; }
    public SettingsViewModel Settings { get; }

    // --- Run state ----------------------------------------------------------
    public ObservableCollection<RunHistoryEntry> History { get; } = new();

    public RunHistoryEntry? SelectedRun
    {
        get => _selectedRun;
        set
        {
            if (!Set(ref _selectedRun, value)) return;
            OnPropertyChanged(nameof(SelectedReportUri));
            OnPropertyChanged(nameof(HasSelectedReport));
        }
    }

    public Uri? SelectedReportUri
    {
        get
        {
            var p = _selectedRun?.ReportHtmlPath;
            return string.IsNullOrEmpty(p) ? null : new Uri(p);
        }
    }
    public bool HasSelectedReport => _selectedRun?.ReportHtmlPath is not null;
    public bool CanRun { get => _canRun; set => Set(ref _canRun, value); }
    public bool SanitizeEnabled         { get => _sanitize;         set => Set(ref _sanitize, value); }
    public bool IncludeMiniDumpsEnabled { get => _includeMiniDumps; set => Set(ref _includeMiniDumps, value); }
    public string CaptureNetSeconds     { get => _captureNetSeconds; set => Set(ref _captureNetSeconds, value); }
    public string PerfSampleSeconds     { get => _perfSampleSeconds; set => Set(ref _perfSampleSeconds, value); }
    public string StatusMessage         { get => _statusMessage;    set => Set(ref _statusMessage, value); }

    // --- Navigation ---------------------------------------------------------
    public NavTab SelectedTab
    {
        get => _selectedTab;
        set
        {
            if (!Set(ref _selectedTab, value)) return;
            OnPropertyChanged(nameof(IsRunTab));
            OnPropertyChanged(nameof(IsDiffTab));
            OnPropertyChanged(nameof(IsTrendsTab));
            OnPropertyChanged(nameof(IsPluginsTab));
            OnPropertyChanged(nameof(IsSettingsTab));

            // Re-populate the dependent view-models when their tab opens.
            if (value == NavTab.Diff)   Diff.SetRuns(History);
            if (value == NavTab.Trends) Trends.Load(History);
        }
    }
    public bool IsRunTab      => _selectedTab == NavTab.Run;
    public bool IsDiffTab     => _selectedTab == NavTab.Diff;
    public bool IsTrendsTab   => _selectedTab == NavTab.Trends;
    public bool IsPluginsTab  => _selectedTab == NavTab.Plugins;
    public bool IsSettingsTab => _selectedTab == NavTab.Settings;

    // --- Actions ------------------------------------------------------------
    public async Task RunDiagnosticsAsync()
    {
        if (_runner is null) { StatusMessage = "system-diagnostics.ps1 not found."; return; }

        CanRun = false;
        StatusMessage = "Running diagnostics...";
        try
        {
            int seconds = int.TryParse(CaptureNetSeconds, NumberStyles.Integer, CultureInfo.InvariantCulture, out var s)
                ? Math.Max(0, s) : 0;
            int perfSeconds = int.TryParse(PerfSampleSeconds, NumberStyles.Integer, CultureInfo.InvariantCulture, out var ps)
                ? Math.Max(0, ps) : 5;
            var opts = new DiagnosticsRunner.Options(
                Sanitize: SanitizeEnabled,
                IncludeMiniDumps: IncludeMiniDumpsEnabled,
                CaptureNetSeconds: seconds,
                PerfSampleSeconds: perfSeconds);

            var exit = await _runner.RunAsync(opts, line =>
            {
                Application.Current.Dispatcher.BeginInvoke(() => StatusMessage = line);
            });

            StatusMessage = exit == 0 ? "Run complete." : $"Run finished with exit code {exit}.";
            ReloadHistory();
            if (History.Count > 0) SelectedRun = History[0];
        }
        catch (Exception ex) { StatusMessage = "Error: " + ex.Message; }
        finally { CanRun = true; }
    }

    private void ReloadHistory()
    {
        var entries = _history.Load().OrderByDescending(x => x.Timestamp).ToList();
        History.Clear();
        foreach (var e in entries) History.Add(e);
    }
}

public enum NavTab { Run, Diff, Trends, Plugins, Settings }

/// <summary>True -> Collapsed, False -> Visible.</summary>
public sealed class InvertedBoolToVisibilityConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, CultureInfo culture)
        => (value is bool b && b) ? Visibility.Collapsed : Visibility.Visible;
    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture)
        => throw new NotSupportedException();
}

/// <summary>Compares a NavTab value against the converter parameter and
/// returns true if equal. Used to highlight the active sidebar item.</summary>
public sealed class EnumEqualsConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, CultureInfo culture)
        => value?.ToString() == parameter?.ToString();
    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture)
        => (value is bool b && b) ? Enum.Parse(typeof(NavTab), parameter?.ToString() ?? "Run") : Binding.DoNothing;
}
