using System.Collections.ObjectModel;
using SystemTools.Desktop.Models;
using SystemTools.Desktop.Services;

namespace SystemTools.Desktop.ViewModels;

public sealed class DiffViewModel : ViewModelBase
{
    private readonly DiffService? _service;
    private RunHistoryEntry? _oldRun;
    private RunHistoryEntry? _newRun;
    private string _output = "Pick two runs from the dropdowns and click Compare.";
    private bool _busy;

    public DiffViewModel(string? systemDiagnosticsScriptPath)
    {
        if (systemDiagnosticsScriptPath is not null)
        {
            try { _service = new DiffService(systemDiagnosticsScriptPath); } catch { }
        }
    }

    public ObservableCollection<RunHistoryEntry> Runs { get; } = new();

    public RunHistoryEntry? OldRun { get => _oldRun; set { if (Set(ref _oldRun, value)) OnPropertyChanged(nameof(CanCompare)); } }
    public RunHistoryEntry? NewRun { get => _newRun; set { if (Set(ref _newRun, value)) OnPropertyChanged(nameof(CanCompare)); } }
    public string Output { get => _output; set => Set(ref _output, value); }
    public bool IsBusy { get => _busy; set { if (Set(ref _busy, value)) OnPropertyChanged(nameof(CanCompare)); } }

    public bool CanCompare =>
        !IsBusy && _service is not null
        && _oldRun?.ReportDir is { Length: > 0 }
        && _newRun?.ReportDir is { Length: > 0 }
        && _oldRun != _newRun;

    public void SetRuns(IEnumerable<RunHistoryEntry> entries)
    {
        Runs.Clear();
        foreach (var e in entries) Runs.Add(e);
        if (Runs.Count >= 2)
        {
            NewRun = Runs[0];           // newest
            OldRun = Runs[Math.Min(Runs.Count - 1, 1)];
        }
    }

    public async Task CompareAsync()
    {
        if (!CanCompare || _service is null || _oldRun is null || _newRun is null) return;
        IsBusy = true;
        Output = "Running diff...";
        try
        {
            Output = await _service.RunAsync(_oldRun.ReportDir, _newRun.ReportDir);
        }
        catch (Exception ex)
        {
            Output = "Error: " + ex.Message;
        }
        finally
        {
            IsBusy = false;
        }
    }
}
