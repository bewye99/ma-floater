using System.Drawing;
using System.IO;
using System.Windows;
using System.Windows.Input;
using System.Windows.Interop;
using MAFloater.Core;
using WinForms = System.Windows.Forms;

namespace MAFloater.App;

public partial class MainWindow : Window
{
    private readonly Icon brandIcon;
    private readonly WinForms.NotifyIcon trayIcon;
    private bool allowClose;

    public MainWindow()
    {
        InitializeComponent();
        brandIcon = LoadBrandIcon();
        trayIcon = CreateTrayIcon(brandIcon);
        StatusText.Text = File.Exists(AppPaths.ConnectionSettingsPath)
            ? "Music Assistant • Existing settings detected"
            : "Music Assistant • Setup will follow";
    }

    private static Icon LoadBrandIcon()
    {
        var resource = System.Windows.Application.GetResourceStream(
            new Uri("pack://application:,,,/Assets/ma-floater.ico"));
        if (resource is null)
        {
            return (Icon)SystemIcons.Application.Clone();
        }

        using var source = new Icon(resource.Stream);
        return (Icon)source.Clone();
    }

    private WinForms.NotifyIcon CreateTrayIcon(Icon icon)
    {
        var menu = new WinForms.ContextMenuStrip();
        menu.Items.Add("Open player", null, (_, _) => RestoreWindow());
        menu.Items.Add("Exit", null, (_, _) => ExitApplication());

        var notifyIcon = new WinForms.NotifyIcon
        {
            Icon = icon,
            Text = "MA Floater (native foundation)",
            ContextMenuStrip = menu,
            Visible = true
        };
        notifyIcon.DoubleClick += (_, _) => RestoreWindow();
        return notifyIcon;
    }

    private void RestoreWindow()
    {
        Show();
        WindowState = WindowState.Normal;
        Activate();
    }

    private void ExitApplication()
    {
        allowClose = true;
        Close();
        System.Windows.Application.Current.Shutdown();
    }

    private void Window_MouseLeftButtonDown(object sender, MouseButtonEventArgs e)
    {
        if (e.ButtonState == MouseButtonState.Pressed)
        {
            DragMove();
        }
    }

    private void PinButton_Click(object sender, RoutedEventArgs e)
    {
        Topmost = !Topmost;
        PinButton.Foreground = Topmost
            ? System.Windows.Media.Brushes.DeepSkyBlue
            : System.Windows.Media.Brushes.LightGray;
    }

    private void MinimizeButton_Click(object sender, RoutedEventArgs e) =>
        WindowState = WindowState.Minimized;

    private void CloseButton_Click(object sender, RoutedEventArgs e) => ExitApplication();

    protected override void OnClosing(System.ComponentModel.CancelEventArgs e)
    {
        if (!allowClose)
        {
            e.Cancel = true;
            Hide();
            return;
        }

        base.OnClosing(e);
    }

    private void Window_Closed(object? sender, EventArgs e)
    {
        trayIcon.Visible = false;
        trayIcon.ContextMenuStrip?.Dispose();
        trayIcon.Dispose();
        brandIcon.Dispose();
    }
}
