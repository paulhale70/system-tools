using System.ComponentModel;
using System.Windows;
using System.Windows.Controls;
using SystemTools.Desktop.ViewModels;

namespace SystemTools.Desktop.Views;

public partial class TrendsView : UserControl
{
    public TrendsView() => InitializeComponent();

    private void OnLoaded(object sender, RoutedEventArgs e)
    {
        if (DataContext is MainViewModel m)
        {
            m.Trends.PropertyChanged += OnTrendsChanged;
            Redraw();
        }
    }

    private void OnTrendsChanged(object? sender, PropertyChangedEventArgs e) => Redraw();

    private void Redraw()
    {
        if (DataContext is not MainViewModel m) return;
        var vm = m.Trends;
        var plot = Plot.Plot;
        plot.Clear();

        if (vm.OkSeries.Length == 0)
        {
            plot.Title("No runs yet - run diagnostics to start collecting trends.");
            Plot.Refresh();
            return;
        }

        var ok   = plot.Add.Signal(vm.OkSeries);   ok.Color   = ScottPlot.Color.FromHex("#15803D");   ok.LegendText   = "OK";
        var warn = plot.Add.Signal(vm.WarnSeries); warn.Color = ScottPlot.Color.FromHex("#B45309"); warn.LegendText = "WARN";
        var fail = plot.Add.Signal(vm.FailSeries); fail.Color = ScottPlot.Color.FromHex("#B91C1C"); fail.LegendText = "FAIL";

        plot.Axes.Bottom.Label.Text = $"Last {vm.OkSeries.Length} runs";
        plot.Axes.Left.Label.Text   = "Verdict count";
        plot.ShowLegend();
        plot.Axes.AutoScale();
        Plot.Refresh();
    }
}
