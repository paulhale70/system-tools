using System.Collections.ObjectModel;
using System.Diagnostics;
using System.IO;
using System.Windows;
using SystemTools.Desktop.Models;
using SystemTools.Desktop.Services;

namespace SystemTools.Desktop.ViewModels;

/// <summary>Crash dumps tab: list the dumps on this PC, analyze one, show the report.</summary>
public sealed class DumpsViewModel : ViewModelBase
{
    private readonly DumpService? _service;
    private readonly Action<string> _setStatus;
    private CancellationTokenSource? _cts;
    private DumpFileInfo? _selected;
    private bool _busy;
    private bool _loaded;
    private string? _note;
    private bool _elevated;
    private Uri? _reportUri;
    private string _message = "Pick a dump and click Analyze, or browse for a .dmp file.";

    public DumpsViewModel(string? systemDiagnosticsScriptPath, Action<string> setStatus)
    {
        _setStatus = setStatus;
        if (systemDiagnosticsScriptPath is not null)
        {
            try { _service = new DumpService(systemDiagnosticsScriptPath); }
            catch (FileNotFoundException ex) { _message = ex.Message; }
        }
    }

    public ObservableCollection<DumpFileInfo> Dumps { get; } = new();

    public DumpFileInfo? SelectedDump
    {
        get => _selected;
        set { if (Set(ref _selected, value)) OnPropertyChanged(nameof(CanAnalyze)); }
    }
    public bool IsBusy
    {
        get => _busy;
        set
        {
            if (!Set(ref _busy, value)) return;
            OnPropertyChanged(nameof(CanAnalyze));
            OnPropertyChanged(nameof(CanStart));
        }
    }
    public bool CanAnalyze => CanStart && _selected is not null;
    public bool CanStart => !_busy && _service is not null;

    /// <summary>Why blue-screen dumps may be missing (not elevated), or null.</summary>
    public string? Note { get => _note; private set { if (Set(ref _note, value)) OnPropertyChanged(nameof(HasNote)); } }
    public bool HasNote => !string.IsNullOrEmpty(_note);
    public bool IsElevated { get => _elevated; private set => Set(ref _elevated, value); }

    public Uri? ReportUri
    {
        get => _reportUri;
        private set { if (Set(ref _reportUri, value)) OnPropertyChanged(nameof(HasReport)); }
    }
    public bool HasReport => _reportUri is not null;
    public string Message { get => _message; private set => Set(ref _message, value); }

    /// <summary>Load the list the first time the tab opens.</summary>
    public async Task EnsureLoadedAsync()
    {
        if (_loaded) return;
        _loaded = true;
        await RefreshAsync();
    }

    public async Task RefreshAsync()
    {
        if (_service is null || IsBusy) return;
        IsBusy = true;
        _setStatus("Looking for crash dumps...");
        try
        {
            var list = await _service.ListAsync();
            Dumps.Clear();
            foreach (var d in list.Dumps) Dumps.Add(d);
            IsElevated = list.Elevated;
            Note = list.Note;
            SelectedDump ??= Dumps.FirstOrDefault();
            _setStatus(Dumps.Count == 0 ? "No crash dumps from the last 90 days." : $"Found {Dumps.Count} crash dump(s).");
        }
        catch (Exception ex) { _setStatus("Couldn't list dumps: " + ex.Message); }
        finally { IsBusy = false; }
    }

    public Task AnalyzeSelectedAsync() =>
        _selected is null ? Task.CompletedTask : AnalyzeAsync(_selected.Path);

    public async Task AnalyzeAsync(string path)
    {
        if (_service is null || IsBusy) return;
        IsBusy = true;
        _cts = new CancellationTokenSource();
        ReportUri = null;
        Message = $"Analyzing {Path.GetFileName(path)}. The first analysis downloads symbols from Microsoft and can take several minutes.";
        _setStatus(Message);
        try
        {
            var result = await _service.AnalyzeAsync(path,
                line => Application.Current.Dispatcher.BeginInvoke(() => _setStatus(line)), _cts.Token);
            if (result.Error is not null)
            {
                Message = result.Error;
                _setStatus(result.Error);
            }
            else if (result.Html is not null && File.Exists(result.Html))
            {
                ReportUri = new Uri(result.Html);
                var first = result.Results.FirstOrDefault();
                _setStatus(first?.Headline ?? "Analysis complete.");
            }
            else
            {
                Message = "The analysis finished but no report was written.";
                _setStatus(Message);
            }
        }
        catch (OperationCanceledException)
        {
            Message = "Analysis cancelled.";
            _setStatus(Message);
        }
        catch (Exception ex)
        {
            Message = "Error: " + ex.Message;
            _setStatus(Message);
        }
        finally
        {
            _cts.Dispose();
            _cts = null;
            IsBusy = false;
        }
    }

    public void Cancel() => _cts?.Cancel();

    /// <summary>Restart the app elevated so C:\Windows\Minidump and LiveKernelReports can be read.</summary>
    public static void RestartAsAdmin()
    {
        var exe = Environment.ProcessPath;
        if (exe is null) return;
        try
        {
            Process.Start(new ProcessStartInfo(exe) { UseShellExecute = true, Verb = "runas" });
            Application.Current.Shutdown();
        }
        catch (System.ComponentModel.Win32Exception)
        {
            // The UAC prompt was declined; stay as we are.
        }
    }
}
