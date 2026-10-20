using System.IO;
using System.Text.Json;
using System.Windows;
using System.Windows.Controls;
using Microsoft.Web.WebView2.Core;
using SystemTools.Desktop.Services;
using SystemTools.Desktop.ViewModels;

namespace SystemTools.Desktop.Views;

/// <summary>
/// Hosts web/index.html (the same file that works standalone in a browser).
/// The page and its libraries are served from the .exe's embedded
/// resources, so it works offline, and the run history is pushed in with
/// PostWebMessageAsJson instead of being dragged in by hand.
/// </summary>
public partial class DashboardView : UserControl
{
    private const string Host = "systemtools.example";
    private const string PageUrl = "https://" + Host + "/index.html";

    // The page references these CDN URLs so it still works on its own.
    // Inside the app they are answered from the vendored copies instead.
    private static readonly Dictionary<string, string> CdnToVendor = new(StringComparer.OrdinalIgnoreCase)
    {
        ["https://cdn.tailwindcss.com/3.4.16"] = "vendor/tailwindcss-3.4.16.js",
        ["https://cdn.jsdelivr.net/npm/alpinejs@3.13.5/dist/cdn.min.js"] = "vendor/alpinejs-3.13.5.min.js",
        ["https://cdn.jsdelivr.net/npm/chart.js@4.4.1/dist/chart.umd.min.js"] = "vendor/chartjs-4.4.1.umd.min.js",
    };

    private MainViewModel? _vm;
    private bool _initStarted;
    private bool _pageReady;

    public DashboardView()
    {
        InitializeComponent();
        IsVisibleChanged += OnIsVisibleChanged;
        DataContextChanged += OnDataContextChanged;
    }

    private void OnDataContextChanged(object sender, DependencyPropertyChangedEventArgs e)
    {
        if (_vm is not null) _vm.HistoryReloaded -= OnHistoryReloaded;
        _vm = DataContext as MainViewModel;
        if (_vm is not null) _vm.HistoryReloaded += OnHistoryReloaded;
    }

    // WebView2 is only started the first time the tab is shown; after that,
    // showing the tab re-sends the history in case a scheduled run added to it.
    private async void OnIsVisibleChanged(object sender, DependencyPropertyChangedEventArgs e)
    {
        if (!IsVisible) return;
        if (_initStarted) { PushHistory(); return; }
        _initStarted = true;
        try
        {
            await Web.EnsureCoreWebView2Async();
            var core = Web.CoreWebView2;
            core.AddWebResourceRequestedFilter($"https://{Host}/*", CoreWebView2WebResourceContext.All);
            foreach (var url in CdnToVendor.Keys)
                core.AddWebResourceRequestedFilter(url, CoreWebView2WebResourceContext.All);
            core.WebResourceRequested += OnWebResourceRequested;
            core.WebMessageReceived += OnWebMessageReceived;
            core.Navigate(PageUrl);
        }
        catch (Exception ex)
        {
            ErrorText.Text = ex.Message + "\n\nThe dashboard needs the Microsoft Edge WebView2 Runtime.";
            ErrorPanel.Visibility = Visibility.Visible;
            Web.Visibility = Visibility.Collapsed;
        }
    }

    private void OnWebResourceRequested(object? sender, CoreWebView2WebResourceRequestedEventArgs e)
    {
        var uri = e.Request.Uri;
        string? rel = CdnToVendor.TryGetValue(uri, out var vendored) ? vendored
            : uri.StartsWith($"https://{Host}/", StringComparison.OrdinalIgnoreCase) ? new Uri(uri).AbsolutePath.TrimStart('/')
            : null;
        if (rel is null) return;

        var env = Web.CoreWebView2.Environment;
        var stream = BundledAssets.OpenWeb(rel);
        e.Response = stream is null
            ? env.CreateWebResourceResponse(null, 404, "Not Found", "")
            : env.CreateWebResourceResponse(stream, 200, "OK", "Content-Type: " + ContentType(rel));
    }

    private void OnWebMessageReceived(object? sender, CoreWebView2WebMessageReceivedEventArgs e)
    {
        using var doc = JsonDocument.Parse(e.WebMessageAsJson);
        if (doc.RootElement.ValueKind == JsonValueKind.Object
            && doc.RootElement.TryGetProperty("type", out var t) && t.GetString() == "ready")
        {
            _pageReady = true;
            PushHistory();
        }
    }

    private void OnHistoryReloaded(object? sender, EventArgs e) => Dispatcher.Invoke(PushHistory);

    private void PushHistory()
    {
        if (!_pageReady || _vm is null) return;
        var json = $"{{\"type\":\"history\",\"source\":{JsonSerializer.Serialize(_vm.HistoryPath)},\"runs\":{_vm.ReadHistoryJson()}}}";
        Web.CoreWebView2.PostWebMessageAsJson(json);
    }

    private static string ContentType(string path) => Path.GetExtension(path).ToLowerInvariant() switch
    {
        ".html" => "text/html; charset=utf-8",
        ".js"   => "text/javascript; charset=utf-8",
        ".css"  => "text/css; charset=utf-8",
        ".json" => "application/json",
        _       => "application/octet-stream",
    };
}
