using System.Windows;
using SystemTools.Desktop.ViewModels;

namespace SystemTools.Desktop;

public partial class MainWindow : Window
{
    public MainWindow() => InitializeComponent();

    private MainViewModel? Vm => DataContext as MainViewModel;

    private void OnNavRun(object sender, RoutedEventArgs e)      { if (Vm is not null) Vm.SelectedTab = NavTab.Run; }
    private void OnNavDiff(object sender, RoutedEventArgs e)     { if (Vm is not null) Vm.SelectedTab = NavTab.Diff; }
    private void OnNavTrends(object sender, RoutedEventArgs e)   { if (Vm is not null) Vm.SelectedTab = NavTab.Trends; }
    private void OnNavPlugins(object sender, RoutedEventArgs e)  { if (Vm is not null) Vm.SelectedTab = NavTab.Plugins; }
    private void OnNavSettings(object sender, RoutedEventArgs e) { if (Vm is not null) Vm.SelectedTab = NavTab.Settings; }
}
