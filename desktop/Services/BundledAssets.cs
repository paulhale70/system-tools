using System.IO;
using System.Reflection;

namespace SystemTools.Desktop.Services;

/// <summary>
/// The diagnostics scripts and the web dashboard are compiled into the
/// .exe as embedded resources (see the csproj), so the single-file build
/// needs nothing next to it.
///   diagnostics/...  extracted to %LOCALAPPDATA%\SystemTools\diagnostics
///                    because powershell.exe needs real files.
///   web/...          served straight from memory to the Dashboard WebView2.
/// </summary>
public static class BundledAssets
{
    private const string DiagPrefix = "diagnostics/";
    private const string WebPrefix  = "web/";

    private static readonly Assembly Asm = typeof(BundledAssets).Assembly;

    public static string AppDataDir { get; } = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "SystemTools");

    public static string DiagnosticsDir => Path.Combine(AppDataDir, "diagnostics");

    /// <summary>
    /// Write the bundled scripts out and return the path of
    /// system-diagnostics.ps1. Core scripts are rewritten whenever they
    /// differ from the bundled copy, so an upgraded .exe brings its scripts
    /// with it. The plugins folder is only seeded the first time it is
    /// created; after that it belongs to the user.
    /// </summary>
    public static string ExtractDiagnostics()
    {
        var pluginsDir = Path.Combine(DiagnosticsDir, "plugins");
        bool seedPlugins = !Directory.Exists(pluginsDir);
        Directory.CreateDirectory(pluginsDir);

        foreach (var name in Asm.GetManifestResourceNames())
        {
            if (!name.StartsWith(DiagPrefix, StringComparison.Ordinal)) continue;
            var rel = name[DiagPrefix.Length..];
            bool isPlugin = rel.StartsWith("plugins/", StringComparison.Ordinal);
            if (isPlugin && !seedPlugins) continue;

            var target = Path.Combine(DiagnosticsDir, rel.Replace('/', Path.DirectorySeparatorChar));
            var bytes = ReadAll(name);
            if (File.Exists(target) && File.ReadAllBytes(target).AsSpan().SequenceEqual(bytes)) continue;
            File.WriteAllBytes(target, bytes);
        }

        var script = Path.Combine(DiagnosticsDir, "system-diagnostics.ps1");
        if (!File.Exists(script))
            throw new FileNotFoundException("system-diagnostics.ps1 is missing from the bundled resources.", script);
        return script;
    }

    /// <summary>Open a bundled web file ("index.html", "vendor/x.js"), or null.</summary>
    public static Stream? OpenWeb(string relativePath)
        => Asm.GetManifestResourceStream(WebPrefix + relativePath.TrimStart('/'));

    private static byte[] ReadAll(string resourceName)
    {
        using var s = Asm.GetManifestResourceStream(resourceName)!;
        using var ms = new MemoryStream();
        s.CopyTo(ms);
        return ms.ToArray();
    }
}
