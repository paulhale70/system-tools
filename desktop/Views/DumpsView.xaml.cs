using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using Microsoft.Win32;
using SystemTools.Desktop.ViewModels;

namespace SystemTools.Desktop.Views;

public partial class DumpsView : UserControl
{
    public DumpsView()
    {
        InitializeComponent();
        IsVisibleChanged += async (_, e) =>
        {
            if (e.NewValue is true && Vm is not null) await Vm.EnsureLoadedAsync();
        };
    }

    private DumpsViewModel? Vm => (DataContext as MainViewModel)?.Dumps ?? DataContext as DumpsViewModel;

    private async void OnAnalyzeClick(object sender, RoutedEventArgs e)
    {
        if (Vm is not null) await Vm.AnalyzeSelectedAsync();
    }

    private async void OnListDoubleClick(object sender, MouseButtonEventArgs e)
    {
        if (Vm is { CanAnalyze: true }) await Vm.AnalyzeSelectedAsync();
    }

    private async void OnRefreshClick(object sender, RoutedEventArgs e)
    {
        if (Vm is not null) await Vm.RefreshAsync();
    }

    private void OnCancelClick(object sender, RoutedEventArgs e) => Vm?.Cancel();

    private void OnElevateClick(object sender, RoutedEventArgs e) => DumpsViewModel.RestartAsAdmin();

    private async void OnBrowseClick(object sender, RoutedEventArgs e)
    {
        if (Vm is null) return;
        var dlg = new OpenFileDialog
        {
            Title = "Pick a crash dump to analyze",
            Filter = "Crash dumps (*.dmp;*.mdmp;*.hdmp)|*.dmp;*.mdmp;*.hdmp|All files (*.*)|*.*",
        };
        if (dlg.ShowDialog(Window.GetWindow(this)) == true) await Vm.AnalyzeAsync(dlg.FileName);
    }
}
