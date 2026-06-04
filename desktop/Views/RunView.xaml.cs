using System.Windows;
using System.Windows.Controls;
using SystemTools.Desktop.ViewModels;

namespace SystemTools.Desktop.Views;

public partial class RunView : UserControl
{
    public RunView() => InitializeComponent();

    private async void OnRunClick(object sender, RoutedEventArgs e)
    {
        if (DataContext is MainViewModel vm) await vm.RunDiagnosticsAsync();
    }
}
