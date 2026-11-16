using System.Drawing;
using System.IO;
using System.Windows;
using System.Windows.Input;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using MAFloater.Core;
using Media = System.Windows.Media;
using WinForms = System.Windows.Forms;

namespace MAFloater.App;

public partial class MainWindow : Window
{
    private readonly Icon brandIcon;
    private readonly WinForms.NotifyIcon trayIcon;
    private readonly DispatcherTimer refreshTimer;
    private readonly DispatcherTimer compactTimer;
    private readonly ArtworkClient artworkClient;
    private WinForms.ToolStripMenuItem startupMenuItem = null!;
    private MusicAssistantClient? musicAssistantClient;
    private ConnectionSettings? connectionSettings;
    private NowPlayingSnapshot? currentSnapshot;
    private string currentArtworkUrl = string.Empty;
    private bool refreshInProgress;
    private bool controlInProgress;
    private bool updatingVolume;
    private bool allowClose;
    private bool isCompact;
    private double expandedWidth = 390;
    private double expandedHeight = 150;

    public MainWindow()
    {
        InitializeComponent();
        brandIcon = LoadBrandIcon();
        trayIcon = CreateTrayIcon(brandIcon);
        artworkClient = new ArtworkClient();
        refreshTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(2) };
        refreshTimer.Tick += RefreshTimer_Tick;
        compactTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(15) };
        compactTimer.Tick += CompactTimer_Tick;
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
        startupMenuItem = new WinForms.ToolStripMenuItem("Start with Windows")
        {
            Checked = StartupRegistration.IsEnabled()
        };
        startupMenuItem.Click += (_, _) => Dispatcher.BeginInvoke(ToggleStartupRegistration);
        menu.Items.Add(startupMenuItem);
        menu.Items.Add(new WinForms.ToolStripSeparator());
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
        RestartCompactTimer();
        await InitializeConnectionAsync();
    }

    private void CompactTimer_Tick(object? sender, EventArgs e)
    {
        compactTimer.Stop();
        if (!IsMouseOver && WindowState == WindowState.Normal && IsEnabled)
        {
            SetCompactMode(true);
        }
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
        compactTimer.Stop();
        SetCompactMode(false);
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
            RestartCompactTimer();
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
        finally
        {
            RestartCompactTimer();
        }
    }

    private async Task ConnectFromSavedSettingsAsync()
    {
        connectionSettings = ConnectionSettingsStore.Load();
        var password = CredentialStore.LoadPassword();
        var client = new MusicAssistantClient(passwordProvider: () => CredentialStore.LoadPassword());
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
            currentSnapshot = snapshot;
            TrackTitle.Text = snapshot.Title;
            ArtistText.Text = snapshot.Artist;
            StatusText.Text = snapshot.HasQueue
                ? $"Music Assistant • {snapshot.QueueName} • {snapshot.State}"
                : "Music Assistant • Connected";
            Title = snapshot.HasQueue
                ? $"MA Floater - {snapshot.Title} - {snapshot.Artist}"
                : "MA Floater - Nothing queued";
            UpdateControlState(snapshot);
            await UpdateArtworkAsync(snapshot.ArtworkUrl);
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
        currentSnapshot = null;
        TrackTitle.Text = heading;
        ArtistText.Text = detail;
        StatusText.Text = "Music Assistant";
        Title = $"MA Floater - {heading}";
        UpdateControlState(NowPlayingSnapshot.NothingQueued);
        _ = UpdateArtworkAsync(string.Empty);
    }

    private void UpdateControlState(NowPlayingSnapshot snapshot)
    {
        var queueAvailable = snapshot.HasQueue && !controlInProgress;
        PreviousButton.IsEnabled = queueAvailable && snapshot.HasMultipleItems;
        NextButton.IsEnabled = queueAvailable && snapshot.HasMultipleItems;
        PlayPauseButton.IsEnabled = queueAvailable;
        ShuffleButton.IsEnabled = queueAvailable;
        RepeatButton.IsEnabled = queueAvailable;
        PlayPauseButton.Content = snapshot.State.Equals("playing", StringComparison.OrdinalIgnoreCase)
            ? (char)0xE769
            : (char)0xE768;
        PlayPauseButton.ToolTip = snapshot.State.Equals("playing", StringComparison.OrdinalIgnoreCase)
            ? "Pause"
            : "Play";

        ShuffleButton.Foreground = snapshot.ShuffleEnabled ? Media.Brushes.DeepSkyBlue : Media.Brushes.White;
        ShuffleButton.Background = snapshot.ShuffleEnabled
            ? new Media.SolidColorBrush(Media.Color.FromRgb(49, 91, 120))
            : new Media.SolidColorBrush(Media.Color.FromRgb(51, 54, 62));
        ShuffleButton.ToolTip = snapshot.ShuffleEnabled ? "Shuffle: on" : "Shuffle: off";

        RepeatButton.Content = snapshot.RepeatMode == "one" ? (char)0xE8ED : (char)0xE8EE;
        RepeatButton.Foreground = snapshot.RepeatMode == "off" ? Media.Brushes.White : Media.Brushes.DeepSkyBlue;
        RepeatButton.Background = snapshot.RepeatMode == "off"
            ? new Media.SolidColorBrush(Media.Color.FromRgb(51, 54, 62))
            : new Media.SolidColorBrush(Media.Color.FromRgb(49, 91, 120));
        RepeatButton.ToolTip = $"Repeat: {snapshot.RepeatMode}";

        updatingVolume = true;
        try
        {
            VolumeSlider.IsEnabled = queueAvailable && snapshot.SupportsVolume;
            VolumeSlider.Value = snapshot.SupportsVolume ? snapshot.VolumeLevel : 0;
            VolumeText.Text = snapshot.SupportsVolume ? $"{snapshot.VolumeLevel}%" : "--%";
            VolumeText.Foreground = snapshot.SupportsVolume ? Media.Brushes.LightGray : Media.Brushes.Gray;
        }
        finally
        {
            updatingVolume = false;
        }
    }

    private async Task UpdateArtworkAsync(string artworkUrl)
    {
        if (string.Equals(currentArtworkUrl, artworkUrl, StringComparison.Ordinal))
        {
            return;
        }

        currentArtworkUrl = artworkUrl;
        if (string.IsNullOrWhiteSpace(artworkUrl))
        {
            ArtworkImage.Source = new BitmapImage(new Uri("pack://application:,,,/Assets/ma-floater.png"));
            ArtworkImage.Margin = new Thickness(8);
            return;
        }

        try
        {
            var bytes = await artworkClient.DownloadAsync(artworkUrl);
            using var stream = new MemoryStream(bytes);
            var bitmap = new BitmapImage();
            bitmap.BeginInit();
            bitmap.CacheOption = BitmapCacheOption.OnLoad;
            bitmap.StreamSource = stream;
            bitmap.EndInit();
            bitmap.Freeze();
            ArtworkImage.Source = bitmap;
            ArtworkImage.Margin = new Thickness(0);
        }
        catch
        {
            ArtworkImage.Source = new BitmapImage(new Uri("pack://application:,,,/Assets/ma-floater.png"));
            ArtworkImage.Margin = new Thickness(8);
        }
    }

    private async Task ExecuteControlAsync(Func<MusicAssistantClient, NowPlayingSnapshot, Task> action)
    {
        if (controlInProgress || musicAssistantClient is null || currentSnapshot is not { HasQueue: true } snapshot)
        {
            return;
        }

        controlInProgress = true;
        UpdateControlState(snapshot);
        try
        {
            await action(musicAssistantClient, snapshot);
            await RefreshNowPlayingAsync();
        }
        catch (Exception exception)
        {
            StatusText.Text = "Control failed: " + exception.Message;
        }
        finally
        {
            controlInProgress = false;
            UpdateControlState(currentSnapshot ?? NowPlayingSnapshot.NothingQueued);
        }
    }

    private async void PreviousButton_Click(object sender, RoutedEventArgs e) =>
        await ExecuteControlAsync((client, snapshot) => client.PreviousAsync(snapshot.QueueId));

    private async void PlayPauseButton_Click(object sender, RoutedEventArgs e) =>
        await ExecuteControlAsync((client, snapshot) => client.PlayPauseAsync(snapshot.QueueId));

    private async void NextButton_Click(object sender, RoutedEventArgs e) =>
        await ExecuteControlAsync((client, snapshot) => client.NextAsync(snapshot.QueueId));

    private async void ShuffleButton_Click(object sender, RoutedEventArgs e) =>
        await ExecuteControlAsync((client, snapshot) =>
            client.SetShuffleAsync(snapshot.QueueId, !snapshot.ShuffleEnabled));

    private async void RepeatButton_Click(object sender, RoutedEventArgs e) =>
        await ExecuteControlAsync((client, snapshot) => client.SetRepeatAsync(
            snapshot.QueueId,
            snapshot.RepeatMode switch { "off" => "all", "all" => "one", _ => "off" }));

    private void VolumeSlider_ValueChanged(object sender, RoutedPropertyChangedEventArgs<double> e)
    {
        if (!updatingVolume)
        {
            VolumeText.Text = $"{(int)Math.Round(VolumeSlider.Value)}%";
        }
    }

    private async void VolumeSlider_PreviewMouseLeftButtonUp(object sender, MouseButtonEventArgs e)
    {
        await SetVolumeFromSliderAsync();
    }

    private async void VolumeSlider_PreviewKeyUp(object sender, System.Windows.Input.KeyEventArgs e)
    {
        await SetVolumeFromSliderAsync();
    }

    private async Task SetVolumeFromSliderAsync()
    {
        if (updatingVolume || currentSnapshot is not { SupportsVolume: true })
        {
            return;
        }

        var level = (int)Math.Round(VolumeSlider.Value);
        await ExecuteControlAsync((client, snapshot) => client.SetVolumeAsync(snapshot.QueueId, level));
    }

    private void RestoreWindow()
    {
        Show();
        WindowState = WindowState.Normal;
        SetCompactMode(false);
        Activate();
        RestartCompactTimer();
    }

    private void SetCompactMode(bool compact)
    {
        if (compact == isCompact)
        {
            return;
        }

        var right = Left + ActualWidth;
        var bottom = Top + ActualHeight;
        if (compact)
        {
            expandedWidth = Math.Max(330, ActualWidth);
            expandedHeight = Math.Max(136, ActualHeight);
            StatusText.Visibility = Visibility.Collapsed;
            ChromePanel.Visibility = Visibility.Collapsed;
            TransportPanel.Visibility = Visibility.Collapsed;
            VolumePanel.Visibility = Visibility.Collapsed;
            LayoutGrid.Margin = new Thickness(8);
            ArtworkColumn.Width = new GridLength(58);
            TransportRow.Height = new GridLength(0);
            VolumeRow.Height = new GridLength(0);
            ArtworkFrame.Width = 50;
            ArtworkFrame.Height = 50;
            InfoPanel.Margin = new Thickness(2, 5, 4, 0);
            TrackTitle.FontSize = 14;
            ArtistText.FontSize = 11;
            ResizeMode = ResizeMode.NoResize;
            MinWidth = 240;
            MinHeight = 68;
            Width = 280;
            Height = 74;
        }
        else
        {
            StatusText.Visibility = Visibility.Visible;
            ChromePanel.Visibility = Visibility.Visible;
            TransportPanel.Visibility = Visibility.Visible;
            VolumePanel.Visibility = Visibility.Visible;
            LayoutGrid.Margin = new Thickness(12);
            ArtworkColumn.Width = new GridLength(92);
            TransportRow.Height = new GridLength(34);
            VolumeRow.Height = new GridLength(24);
            ArtworkFrame.Width = 78;
            ArtworkFrame.Height = 78;
            InfoPanel.Margin = new Thickness(2, 7, 66, 0);
            TrackTitle.FontSize = 15;
            ArtistText.FontSize = 12;
            MinWidth = 330;
            MinHeight = 136;
            Width = expandedWidth;
            Height = expandedHeight;
            ResizeMode = ResizeMode.CanResizeWithGrip;
        }

        Left = right - Width;
        Top = bottom - Height;
        isCompact = compact;
        ClampToWorkArea();
    }

    private void ClampToWorkArea()
    {
        var workArea = SystemParameters.WorkArea;
        Left = Math.Min(Math.Max(Left, workArea.Left), Math.Max(workArea.Left, workArea.Right - Width));
        Top = Math.Min(Math.Max(Top, workArea.Top), Math.Max(workArea.Top, workArea.Bottom - Height));
    }

    private void RestartCompactTimer()
    {
        compactTimer.Stop();
        if (!IsMouseOver && WindowState == WindowState.Normal && IsEnabled)
        {
            compactTimer.Start();
        }
    }

    private void Window_MouseEnter(object sender, System.Windows.Input.MouseEventArgs e)
    {
        compactTimer.Stop();
        SetCompactMode(false);
    }

    private void Window_MouseLeave(object sender, System.Windows.Input.MouseEventArgs e) => RestartCompactTimer();

    private void Window_StateChanged(object? sender, EventArgs e)
    {
        if (WindowState == WindowState.Normal)
        {
            RestartCompactTimer();
        }
        else
        {
            compactTimer.Stop();
        }
    }

    private void ToggleStartupRegistration()
    {
        var enable = !StartupRegistration.IsEnabled();
        try
        {
            StartupRegistration.SetEnabled(enable);
            startupMenuItem.Checked = StartupRegistration.IsEnabled();
        }
        catch (Exception exception)
        {
            startupMenuItem.Checked = StartupRegistration.IsEnabled();
            System.Windows.MessageBox.Show(
                this,
                exception.Message,
                "MA Floater startup",
                MessageBoxButton.OK,
                MessageBoxImage.Error);
        }
    }

    private async Task DisconnectAsync()
    {
        var client = musicAssistantClient;
        musicAssistantClient = null;
        connectionSettings = null;
        currentSnapshot = null;
        if (client is not null)
        {
            await client.DisposeAsync();
        }
    }

    private async Task ExitApplicationAsync()
    {
        allowClose = true;
        refreshTimer.Stop();
        compactTimer.Stop();
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
        compactTimer.Stop();
        trayIcon.Visible = false;
        trayIcon.ContextMenuStrip?.Dispose();
        trayIcon.Dispose();
        brandIcon.Dispose();
        artworkClient.Dispose();
    }
}
