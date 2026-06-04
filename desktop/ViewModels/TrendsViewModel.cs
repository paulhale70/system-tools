using System.Collections.ObjectModel;
using SystemTools.Desktop.Models;

namespace SystemTools.Desktop.ViewModels;

public sealed class TrendsViewModel : ViewModelBase
{
    private int _totalRuns;
    private string _dateRange = "";
    private double[] _okSeries = Array.Empty<double>();
    private double[] _warnSeries = Array.Empty<double>();
    private double[] _failSeries = Array.Empty<double>();
    private string[] _xLabels = Array.Empty<string>();

    public ObservableCollection<RecurringRow> Recurring { get; } = new();

    public int TotalRuns { get => _totalRuns; set => Set(ref _totalRuns, value); }
    public string DateRange { get => _dateRange; set => Set(ref _dateRange, value); }
    public double[] OkSeries   { get => _okSeries;   set => Set(ref _okSeries, value); }
    public double[] WarnSeries { get => _warnSeries; set => Set(ref _warnSeries, value); }
    public double[] FailSeries { get => _failSeries; set => Set(ref _failSeries, value); }
    public string[] XLabels    { get => _xLabels;    set => Set(ref _xLabels, value); }

    public void Load(IReadOnlyList<RunHistoryEntry> all)
    {
        TotalRuns = all.Count;
        if (all.Count == 0)
        {
            DateRange = "(no runs yet)";
            OkSeries = WarnSeries = FailSeries = Array.Empty<double>();
            XLabels = Array.Empty<string>();
            Recurring.Clear();
            return;
        }

        var ordered = all.OrderBy(x => x.Timestamp).ToList();
        DateRange = $"{ordered[0].DisplayDate}  ->  {ordered[^1].DisplayDate}";

        // Last 20 runs for the line chart.
        var window = ordered.Skip(Math.Max(0, ordered.Count - 20)).ToList();
        OkSeries   = window.Select(r => (double)r.OkCount).ToArray();
        WarnSeries = window.Select(r => (double)r.WarnCount).ToArray();
        FailSeries = window.Select(r => (double)r.FailCount).ToArray();
        XLabels    = window.Select(r => r.DisplayDate).ToArray();

        // Recurring WARN/FAIL verdicts across all runs.
        var tally = new Dictionary<string, int>(StringComparer.Ordinal);
        foreach (var run in all)
            foreach (var v in run.Verdicts)
                if (v.StartsWith("[WARN]", StringComparison.Ordinal) || v.StartsWith("[FAIL]", StringComparison.Ordinal))
                    tally[v] = tally.GetValueOrDefault(v) + 1;

        Recurring.Clear();
        foreach (var kv in tally.OrderByDescending(p => p.Value).Take(15))
            Recurring.Add(new RecurringRow { Count = kv.Value, Verdict = kv.Key });
    }
}

public sealed class RecurringRow
{
    public int Count { get; init; }
    public string Verdict { get; init; } = "";
}
