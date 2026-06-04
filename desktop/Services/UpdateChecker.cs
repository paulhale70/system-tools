using System.Net.Http;
using System.Reflection;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace SystemTools.Desktop.Services;

/// <summary>
/// Queries the GitHub releases API for the latest release of
/// paulhale70/System-tools. Pure read; no auth needed for public repos.
/// </summary>
public sealed class UpdateChecker
{
    private const string LatestUrl = "https://api.github.com/repos/paulhale70/System-tools/releases/latest";
    private static readonly HttpClient Http = CreateClient();

    private static HttpClient CreateClient()
    {
        var c = new HttpClient { Timeout = TimeSpan.FromSeconds(10) };
        c.DefaultRequestHeaders.UserAgent.ParseAdd("SystemTools.Desktop/1.0");
        c.DefaultRequestHeaders.Accept.ParseAdd("application/vnd.github+json");
        return c;
    }

    public string CurrentVersion { get; }

    public UpdateChecker()
    {
        CurrentVersion = Assembly.GetExecutingAssembly().GetName().Version?.ToString(3) ?? "0.0.0";
    }

    public sealed class UpdateInfo
    {
        public required string CurrentVersion { get; init; }
        public required string LatestVersion { get; init; }
        public required string HtmlUrl { get; init; }
        public required string Body { get; init; }
        public bool IsNewer { get; init; }
    }

    public async Task<UpdateInfo?> CheckAsync(CancellationToken cancel = default)
    {
        try
        {
            using var resp = await Http.GetAsync(LatestUrl, cancel);
            if (!resp.IsSuccessStatusCode) return null;
            var json = await resp.Content.ReadAsStringAsync(cancel);
            var rel = JsonSerializer.Deserialize<GitHubRelease>(json);
            if (rel?.TagName is null) return null;

            var latest = rel.TagName.TrimStart('v');
            var current = CurrentVersion;
            return new UpdateInfo
            {
                CurrentVersion = current,
                LatestVersion  = latest,
                HtmlUrl        = rel.HtmlUrl ?? "",
                Body           = rel.Body ?? "",
                IsNewer        = CompareSemVer(latest, current) > 0,
            };
        }
        catch (HttpRequestException)    { return null; }
        catch (TaskCanceledException)   { return null; }
        catch (JsonException)           { return null; }
    }

    private static int CompareSemVer(string a, string b)
    {
        var pa = a.Split('.').Select(s => int.TryParse(s, out var n) ? n : 0).Concat(new[] { 0, 0, 0 }).Take(3).ToArray();
        var pb = b.Split('.').Select(s => int.TryParse(s, out var n) ? n : 0).Concat(new[] { 0, 0, 0 }).Take(3).ToArray();
        for (int i = 0; i < 3; i++)
            if (pa[i] != pb[i]) return pa[i].CompareTo(pb[i]);
        return 0;
    }

    private sealed class GitHubRelease
    {
        [JsonPropertyName("tag_name")] public string? TagName { get; set; }
        [JsonPropertyName("html_url")] public string? HtmlUrl { get; set; }
        [JsonPropertyName("body")]     public string? Body { get; set; }
    }
}
