using System.IO;

namespace SystemTools.Desktop.Services;

public sealed class PluginInfo
{
    public required string FilePath { get; init; }
    public required string Name { get; init; }
    public required bool Enabled { get; init; }
    public required long SizeBytes { get; init; }
    public required DateTime LastWriteTime { get; init; }

    public string DisplaySize => SizeBytes >= 1024
        ? $"{SizeBytes / 1024.0:0.#} KB"
        : $"{SizeBytes} B";
}

/// <summary>
/// Enumerates the diagnostics/plugins/ folder. Plugins ending in
/// .ps1 are active; .ps1.disabled are inactive but kept on disk.
/// </summary>
public sealed class PluginManager
{
    public string PluginsDir { get; }

    public PluginManager(string scriptPath)
    {
        var dir = Path.GetDirectoryName(scriptPath)
                  ?? throw new ArgumentException("Cannot derive script directory.", nameof(scriptPath));
        PluginsDir = Path.Combine(dir, "plugins");
        Directory.CreateDirectory(PluginsDir);
    }

    public IReadOnlyList<PluginInfo> List()
    {
        var result = new List<PluginInfo>();
        foreach (var f in Directory.EnumerateFiles(PluginsDir))
        {
            var name = Path.GetFileName(f);
            if (name.StartsWith("README", StringComparison.OrdinalIgnoreCase)) continue;
            bool enabled;
            if (name.EndsWith(".ps1", StringComparison.OrdinalIgnoreCase))           enabled = true;
            else if (name.EndsWith(".ps1.disabled", StringComparison.OrdinalIgnoreCase)) enabled = false;
            else continue;

            var info = new FileInfo(f);
            result.Add(new PluginInfo
            {
                FilePath = f,
                Name = enabled ? name : name[..^".disabled".Length],
                Enabled = enabled,
                SizeBytes = info.Length,
                LastWriteTime = info.LastWriteTime,
            });
        }
        return result.OrderBy(p => p.Name).ToList();
    }

    public void Enable(PluginInfo p)
    {
        if (p.Enabled) return;
        var target = p.FilePath[..^".disabled".Length];
        File.Move(p.FilePath, target, overwrite: false);
    }

    public void Disable(PluginInfo p)
    {
        if (!p.Enabled) return;
        var target = p.FilePath + ".disabled";
        File.Move(p.FilePath, target, overwrite: false);
    }

    public void Delete(PluginInfo p) => File.Delete(p.FilePath);

    /// <summary>Copy a user-selected .ps1 into the plugins folder.</summary>
    public PluginInfo Import(string sourceFile)
    {
        var name = Path.GetFileName(sourceFile);
        if (!name.EndsWith(".ps1", StringComparison.OrdinalIgnoreCase))
            throw new ArgumentException("Plugins must be .ps1 files.", nameof(sourceFile));
        var target = Path.Combine(PluginsDir, name);
        File.Copy(sourceFile, target, overwrite: true);
        var info = new FileInfo(target);
        return new PluginInfo
        {
            FilePath = target, Name = name, Enabled = true,
            SizeBytes = info.Length, LastWriteTime = info.LastWriteTime,
        };
    }
}
