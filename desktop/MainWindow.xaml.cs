using System.Windows;
using SystemTools.Desktop.ViewModels;

namespace SystemTools.Desktop;

public partial class MainWindow : Window
{
    public MainWindow()
    {
        InitializeComponent();
    }

    private async void OnRunClick(object sender, RoutedEventArgs e)
    {
        if (DataContext is MainViewModel vm)
        {
            await vm.RunDiagnosticsAsync();
        }
    }
}
