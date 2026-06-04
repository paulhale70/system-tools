using System.Windows;
using System.Windows.Controls;
using SystemTools.Desktop.ViewModels;

namespace SystemTools.Desktop.Views;

public partial class SettingsView : UserControl
{
    public SettingsView() => InitializeComponent();

    private SettingsViewModel? Vm => (DataContext as MainViewModel)?.Settings;

    private void OnApplyScheduleClick(object sender, RoutedEventArgs e) => Vm?.ApplySchedule();
    private async void OnCheckUpdatesClick(object sender, RoutedEventArgs e)
    {
        if (Vm is not null) await Vm.CheckUpdatesAsync();
    }
    private void OnOpenReleaseClick(object sender, RoutedEventArgs e) => Vm?.OpenReleasePage();
}
