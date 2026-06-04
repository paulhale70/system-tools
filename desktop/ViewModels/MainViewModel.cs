using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Globalization;
using System.Runtime.CompilerServices;
using System.Windows;
using System.Windows.Data;
using SystemTools.Desktop.Models;
using SystemTools.Desktop.Services;

namespace SystemTools.Desktop.ViewModels;

public sealed class MainViewModel : INotifyPropertyChanged
{
    private readonly HistoryReader _history = new();
    private readonly DiagnosticsRunner? _runner;
    private bool _canRun = true;
    private bool _sanitize;
    private bool _includeMiniDumps;
    private string _captureNetSeconds = "0";
    private string _statusMessage = "Ready.";
    private RunHistoryEntry? _selectedRun;

    public MainViewModel()
    {
        try { _runner = new DiagnosticsRunner(); }
        catch (FileNotFoundException ex) { _statusMessage = ex.Message; _canRun = false; }

        ReloadHistory();
        if (History.Count > 0) SelectedRun = History[0]; // newest first
    }

    public ObservableCollection<RunHistoryEntry> History { get; } = new();

    public RunHistoryEntry? SelectedRun
    {
        get => _selectedRun;
        set
        {
            if (_selectedRun == value) return;
            _selectedRun = value;
            OnPropertyChanged();
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

    public bool CanRun
    {
        get => _canRun;
        set { if (_canRun != value) { _canRun = value; OnPropertyChanged(); } }
    }

    public bool SanitizeEnabled
    {
        get => _sanitize;
        set { if (_sanitize != value) { _sanitize = value; OnPropertyChanged(); } }
    }

    public bool IncludeMiniDumpsEnabled
    {
        get => _includeMiniDumps;
        set { if (_includeMiniDumps != value) { _includeMiniDumps = value; OnPropertyChanged(); } }
    }

    public string CaptureNetSeconds
    {
        get => _captureNetSeconds;
        set { if (_captureNetSeconds != value) { _captureNetSeconds = value; OnPropertyChanged(); } }
    }

    public string StatusMessage
    {
        get => _statusMessage;
        set { if (_statusMessage != value) { _statusMessage = value; OnPropertyChanged(); } }
    }

    public async Task RunDiagnosticsAsync()
    {
        if (_runner is null) { StatusMessage = "system-diagnostics.ps1 not found."; return; }

        CanRun = false;
        StatusMessage = "Running diagnostics...";
        try
        {
            int seconds = int.TryParse(CaptureNetSeconds, NumberStyles.Integer, CultureInfo.InvariantCulture, out var s)
                ? Math.Max(0, s) : 0;
            var opts = new DiagnosticsRunner.Options(
                Sanitize: SanitizeEnabled,
                IncludeMiniDumps: IncludeMiniDumpsEnabled,
                CaptureNetSeconds: seconds);

            var exit = await _runner.RunAsync(opts, line =>
            {
                Application.Current.Dispatcher.BeginInvoke(() => StatusMessage = line);
            });

            StatusMessage = exit == 0 ? "Run complete." : $"Run finished with exit code {exit}.";
            ReloadHistory();
            if (History.Count > 0) SelectedRun = History[0];
        }
        catch (Exception ex)
        {
            StatusMessage = "Error: " + ex.Message;
        }
        finally
        {
            CanRun = true;
        }
    }

    private void ReloadHistory()
    {
        var entries = _history.Load();
        History.Clear();
        // newest first
        foreach (var e in entries.OrderByDescending(x => x.Timestamp))
            History.Add(e);
    }

    public event PropertyChangedEventHandler? PropertyChanged;
    private void OnPropertyChanged([CallerMemberName] string? name = null) =>
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
}

/// <summary>True -> Collapsed, False -> Visible. Used to show the "no
/// report selected" placeholder.</summary>
public sealed class InvertedBoolToVisibilityConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, CultureInfo culture)
        => (value is bool b && b) ? Visibility.Collapsed : Visibility.Visible;

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture)
        => throw new NotSupportedException();
}
