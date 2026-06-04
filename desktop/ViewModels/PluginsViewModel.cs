using System.Collections.ObjectModel;
using System.Diagnostics;
using System.IO;
using SystemTools.Desktop.Services;

namespace SystemTools.Desktop.ViewModels;

public sealed class PluginsViewModel : ViewModelBase
{
    private readonly PluginManager? _mgr;
    private PluginInfo? _selected;
    private string _status = "";

    public PluginsViewModel(string? systemDiagnosticsScriptPath)
    {
        if (systemDiagnosticsScriptPath is not null)
        {
            try { _mgr = new PluginManager(systemDiagnosticsScriptPath); } catch { }
            Reload();
        }
        else
        {
            Status = "Plugins folder not found.";
        }
    }

    public ObservableCollection<PluginInfo> Plugins { get; } = new();

    public PluginInfo? SelectedPlugin
    {
        get => _selected;
        set
        {
            if (Set(ref _selected, value))
            {
                OnPropertyChanged(nameof(CanEnable));
                OnPropertyChanged(nameof(CanDisable));
                OnPropertyChanged(nameof(HasSelection));
            }
        }
    }

    public string Status { get => _status; set => Set(ref _status, value); }
    public string? PluginsDir => _mgr?.PluginsDir;

    public bool HasSelection => _selected is not null;
    public bool CanEnable    => _selected is { Enabled: false };
    public bool CanDisable   => _selected is { Enabled: true };

    public void Reload()
    {
        if (_mgr is null) return;
        var sel = _selected?.FilePath;
        Plugins.Clear();
        foreach (var p in _mgr.List()) Plugins.Add(p);
        Status = $"{Plugins.Count} plugin(s) in {_mgr.PluginsDir}";
        SelectedPlugin = Plugins.FirstOrDefault(p => p.FilePath == sel);
    }

    public void ToggleSelected()
    {
        if (_selected is null || _mgr is null) return;
        try
        {
            if (_selected.Enabled) _mgr.Disable(_selected); else _mgr.Enable(_selected);
            Reload();
        }
        catch (Exception ex) { Status = "Error: " + ex.Message; }
    }

    public void DeleteSelected()
    {
        if (_selected is null || _mgr is null) return;
        try { _mgr.Delete(_selected); Reload(); }
        catch (Exception ex) { Status = "Error: " + ex.Message; }
    }

    public void Import(string sourceFile)
    {
        if (_mgr is null) return;
        try { _mgr.Import(sourceFile); Reload(); Status = $"Imported {Path.GetFileName(sourceFile)}."; }
        catch (Exception ex) { Status = "Error: " + ex.Message; }
    }

    public void OpenFolder()
    {
        if (_mgr is null) return;
        Process.Start(new ProcessStartInfo("explorer.exe", _mgr.PluginsDir) { UseShellExecute = true });
    }
}
