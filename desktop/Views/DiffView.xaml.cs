using System.Windows;
using System.Windows.Controls;
using SystemTools.Desktop.ViewModels;

namespace SystemTools.Desktop.Views;

public partial class DiffView : UserControl
{
    public DiffView() => InitializeComponent();

    private async void OnCompareClick(object sender, RoutedEventArgs e)
    {
        if (DataContext is MainViewModel m) await m.Diff.CompareAsync();
    }
}
