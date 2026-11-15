using System.Drawing;
using System.IO;
using System.Windows;
using System.Windows.Input;
using System.Windows.Threading;
using MAFloater.Core;
using WinForms = System.Windows.Forms;

namespace MAFloater.App;

public partial class MainWindow : Window
{
    private readonly Icon brandIcon;
    private readonly WinForms.NotifyIcon trayIcon;
    private readonly DispatcherTimer refreshTimer;
    private MusicAssistantClient? musicAssistantClient;
    private ConnectionSettings? connectionSettings;
    private bool refreshInProgress;
    private bool allowClose;

    public MainWindow()
    {
        InitializeComponent();
        brandIcon = LoadBrandIcon();
        trayIcon = CreateTrayIcon(brandIcon);
        refreshTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(2) };
        refreshTimer.Tick += RefreshTimer_Tick;
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
        menu.Items.Add("Open player", null, (_, _) => Dispatcher.BeginInvoke(RestoreWindow));
        menu.Items.Add("Connection settings…", null, (_, _) =>
            Dispatcher.BeginInvoke(new Action(async () => await ConfigureConnectionAsync())));
        menu.Items.Add("Exit", null, (_, _) =>
            Dispatcher.BeginInvoke(new Action(async () => await ExitApplicationAsync())));

        var notifyIcon = new WinForms.NotifyIcon
        {
            Icon = icon,
            Text = "MA Floater",
            ContextMenuStrip = menu,
            Visible = true
        };
        notifyIcon.DoubleClick += (_, _) => Dispatcher.BeginInvoke(RestoreWindow);
        return notifyIcon;
    }

    private async void Window_Loaded(object sender, RoutedEventArgs e)
    {
        await InitializeConnectionAsync();
    }

    private async Task InitializeConnectionAsync()
    {
        try
        {
            if (!File.Exists(AppPaths.ConnectionSettingsPath) || !CredentialStore.Exists())
            {
                await ConfigureConnectionAsync();
                return;
            }

            await ConnectFromSavedSettingsAsync();
            refreshTimer.Start();
            await RefreshNowPlayingAsync();
        }
        catch (Exception exception)
        {
            ShowUnavailable("Music Assistant setup needed", exception.Message);
        }
    }

    private async Task ConfigureConnectionAsync()
    {
        refreshTimer.Stop();
        await DisconnectAsync();

        ConnectionSettings? existing = null;
        try
        {
            existing = ConnectionSettingsStore.Load();
        }
        catch (FileNotFoundException)
        {
        }
        catch (InvalidDataException)
        {
        }

        var setup = new SetupWindow(existing) { Owner = this };
        if (setup.ShowDialog() != true)
        {
            ShowUnavailable("Music Assistant setup needed", "Open Connection settings from the tray menu.");
            return;
        }

        try
        {
            await ConnectFromSavedSettingsAsync();
            refreshTimer.Start();
            await RefreshNowPlayingAsync();
        }
        catch (Exception exception)
        {
            ShowUnavailable("Music Assistant sign-in required", exception.Message);
        }
    }

    private async Task ConnectFromSavedSettingsAsync()
    {
        connectionSettings = ConnectionSettingsStore.Load();
        var password = CredentialStore.LoadPassword();
        var client = new MusicAssistantClient();
        try
        {
            await client.LoginAsync(connectionSettings, password);
            musicAssistantClient = client;
        }
        catch
        {
            await client.DisposeAsync();
            throw;
        }
    }

    private async void RefreshTimer_Tick(object? sender, EventArgs e)
    {
        await RefreshNowPlayingAsync();
    }

    private async Task RefreshNowPlayingAsync()
    {
        if (refreshInProgress || musicAssistantClient is null || connectionSettings is null)
        {
            return;
        }

        refreshInProgress = true;
        try
        {
            var snapshot = await musicAssistantClient.GetNowPlayingAsync(connectionSettings.PreferredQueue);
            TrackTitle.Text = snapshot.Title;
            ArtistText.Text = snapshot.Artist;
            StatusText.Text = snapshot.HasQueue
                ? $"Music Assistant • {snapshot.QueueName} • {snapshot.State}"
                : "Music Assistant • Connected";
            Title = snapshot.HasQueue
                ? $"MA Floater - {snapshot.Title} - {snapshot.Artist}"
                : "MA Floater - Nothing queued";
        }
        catch (Exception exception)
        {
            ShowUnavailable("Music Assistant unavailable", exception.Message);
        }
        finally
        {
            refreshInProgress = false;
        }
    }

    private void ShowUnavailable(string heading, string detail)
    {
        TrackTitle.Text = heading;
        ArtistText.Text = detail;
        StatusText.Text = "Music Assistant";
        Title = $"MA Floater - {heading}";
    }

    private void RestoreWindow()
    {
        Show();
        WindowState = WindowState.Normal;
        Activate();
    }

    private async Task DisconnectAsync()
    {
        var client = musicAssistantClient;
        musicAssistantClient = null;
        connectionSettings = null;
        if (client is not null)
        {
            await client.DisposeAsync();
        }
    }

    private async Task ExitApplicationAsync()
    {
        allowClose = true;
        refreshTimer.Stop();
        await DisconnectAsync();
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

    private async void CloseButton_Click(object sender, RoutedEventArgs e) =>
        await ExitApplicationAsync();

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
