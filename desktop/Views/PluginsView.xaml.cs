using System.Windows;
using System.Windows.Controls;
using Microsoft.Win32;
using SystemTools.Desktop.ViewModels;

namespace SystemTools.Desktop.Views;

public partial class PluginsView : UserControl
{
    public PluginsView() => InitializeComponent();

    private PluginsViewModel? Vm => (DataContext as MainViewModel)?.Plugins;

    private void OnImportClick(object sender, RoutedEventArgs e)
    {
        var dlg = new OpenFileDialog
        {
            Title = "Pick a .ps1 plugin to add",
            Filter = "PowerShell scripts (*.ps1)|*.ps1",
        };
        if (dlg.ShowDialog() == true && Vm is not null) Vm.Import(dlg.FileName);
    }

    private void OnEnableClick(object sender, RoutedEventArgs e)   => Vm?.ToggleSelected();
    private void OnDisableClick(object sender, RoutedEventArgs e)  => Vm?.ToggleSelected();
    private void OnDeleteClick(object sender, RoutedEventArgs e)
    {
        if (Vm?.SelectedPlugin is null) return;
        if (MessageBox.Show($"Delete plugin '{Vm.SelectedPlugin.Name}'?", "Confirm delete",
            MessageBoxButton.YesNo, MessageBoxImage.Question) == MessageBoxResult.Yes)
        {
            Vm.DeleteSelected();
        }
    }
    private void OnOpenClick(object sender, RoutedEventArgs e)     => Vm?.OpenFolder();
    private void OnReloadClick(object sender, RoutedEventArgs e)   => Vm?.Reload();
}
