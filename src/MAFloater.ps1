$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Net.Http
Add-Type -AssemblyName System.Security
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

if (-not ('MAFloater.ShellIdentity' -as [type])) {
    Add-Type -TypeDefinition @'
using System.Runtime.InteropServices;

namespace MAFloater
{
    public static class ShellIdentity
    {
        [DllImport("shell32.dll", CharSet = CharSet.Unicode, PreserveSig = true)]
        public static extern int SetCurrentProcessExplicitAppUserModelID(string appId);

        [DllImport("user32.dll", PreserveSig = true)]
        private static extern System.IntPtr SendMessage(
            System.IntPtr windowHandle,
            uint message,
            System.IntPtr parameter,
            System.IntPtr value);

        [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern System.IntPtr LoadImage(
            System.IntPtr instance,
            string name,
            uint type,
            int width,
            int height,
            uint flags);

        public static System.IntPtr LoadSharedIcon(string path, int size)
        {
            const uint ImageIcon = 1;
            const uint LoadFromFile = 0x10;
            const uint LoadShared = 0x8000;
            System.IntPtr iconHandle = LoadImage(
                System.IntPtr.Zero,
                path,
                ImageIcon,
                size,
                size,
                LoadFromFile | LoadShared);
            if (iconHandle == System.IntPtr.Zero)
            {
                throw new System.ComponentModel.Win32Exception();
            }
            return iconHandle;
        }

        public static void SetWindowIcons(System.IntPtr windowHandle, System.IntPtr iconHandle)
        {
            const uint SetIcon = 0x80;
            SendMessage(windowHandle, SetIcon, new System.IntPtr(0), iconHandle);
            SendMessage(windowHandle, SetIcon, new System.IntPtr(1), iconHandle);
            SendMessage(windowHandle, SetIcon, new System.IntPtr(2), iconHandle);
        }
    }
}
'@
}

$shellIdentityResult = [MAFloater.ShellIdentity]::SetCurrentProcessExplicitAppUserModelID('MAFloater.Desktop')
if ($shellIdentityResult -ne 0) {
    throw "Could not set the MA Floater taskbar identity (HRESULT 0x$('{0:X8}' -f $shellIdentityResult))."
}

$createdNew = $false
$singleInstance = New-Object System.Threading.Mutex($true, 'Local\MAFloater', [ref]$createdNew)
if (-not $createdNew) { exit 0 }

[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="MA Floater" Width="390" Height="150"
        MinWidth="330" MinHeight="136" WindowStyle="None"
        AllowsTransparency="True" Background="Transparent"
        ResizeMode="CanResizeWithGrip" ShowInTaskbar="True" Topmost="True"
        UseLayoutRounding="True" SnapsToDevicePixels="True">
    <Window.Resources>
        <Style x:Key="ChromeButton" TargetType="Button">
            <Setter Property="FontFamily" Value="Segoe MDL2 Assets"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="Foreground" Value="#D2D5DC"/>
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Width" Value="30"/>
            <Setter Property="Height" Value="28"/>
            <Setter Property="Cursor" Value="Hand"/>
        </Style>
        <Style x:Key="TransportButton" TargetType="Button">
            <Setter Property="FontFamily" Value="Segoe MDL2 Assets"/>
            <Setter Property="FontSize" Value="17"/>
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="Background" Value="#33363E"/>
            <Setter Property="BorderBrush" Value="#4B4E58"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Width" Value="42"/>
            <Setter Property="Height" Value="30"/>
            <Setter Property="Margin" Value="0,0,7,0"/>
            <Setter Property="Cursor" Value="Hand"/>
        </Style>
        <Style x:Key="VolumeSliderStyle" TargetType="Slider">
            <Setter Property="Height" Value="20"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Slider">
                        <Grid VerticalAlignment="Center">
                            <Border Height="4" Background="#4B4E58" CornerRadius="2"/>
                            <Track x:Name="PART_Track" Orientation="Horizontal">
                                <Track.DecreaseRepeatButton>
                                    <RepeatButton Command="Slider.DecreaseLarge" Background="#5CBFFF"
                                                  BorderThickness="0" Focusable="False">
                                        <RepeatButton.Template>
                                            <ControlTemplate TargetType="RepeatButton">
                                                <Border Height="4" Background="{TemplateBinding Background}"
                                                        CornerRadius="2"/>
                                            </ControlTemplate>
                                        </RepeatButton.Template>
                                    </RepeatButton>
                                </Track.DecreaseRepeatButton>
                                <Track.Thumb>
                                    <Thumb Width="14" Height="14">
                                        <Thumb.Template>
                                            <ControlTemplate TargetType="Thumb">
                                                <Ellipse Fill="#F4F8FF" Stroke="#5CBFFF" StrokeThickness="2"/>
                                            </ControlTemplate>
                                        </Thumb.Template>
                                    </Thumb>
                                </Track.Thumb>
                                <Track.IncreaseRepeatButton>
                                    <RepeatButton Command="Slider.IncreaseLarge" Background="Transparent"
                                                  BorderThickness="0" Focusable="False">
                                        <RepeatButton.Template>
                                            <ControlTemplate TargetType="RepeatButton">
                                                <Border Height="4" Background="{TemplateBinding Background}"
                                                        CornerRadius="2"/>
                                            </ControlTemplate>
                                        </RepeatButton.Template>
                                    </RepeatButton>
                                </Track.IncreaseRepeatButton>
                            </Track>
                        </Grid>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
    </Window.Resources>
    <Border x:Name="DragSurface" Background="#F6181A1E" BorderBrush="#78FFFFFF"
            BorderThickness="1" CornerRadius="16" Padding="12">
        <Border.Effect>
            <DropShadowEffect BlurRadius="22" ShadowDepth="5" Opacity="0.45" Color="Black"/>
        </Border.Effect>
        <Grid x:Name="LayoutGrid">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="92"/>
                <ColumnDefinition Width="*"/>
            </Grid.ColumnDefinitions>
            <Grid.RowDefinitions>
                <RowDefinition Height="*"/>
                <RowDefinition Height="32"/>
                <RowDefinition Height="24"/>
            </Grid.RowDefinitions>
            <Border x:Name="ArtworkFrame" Grid.RowSpan="3" Width="78" Height="78" HorizontalAlignment="Left"
                    VerticalAlignment="Center" CornerRadius="10" Background="#2F323A"
                    ClipToBounds="True">
                <Grid>
                    <TextBlock x:Name="ArtworkFallback" Text="&#xE8D6;" FontFamily="Segoe MDL2 Assets"
                               FontSize="38" Foreground="#9EA6B8" HorizontalAlignment="Center"
                               VerticalAlignment="Center"/>
                    <Image x:Name="Artwork" Stretch="UniformToFill"/>
                </Grid>
            </Border>
            <StackPanel x:Name="InfoPanel" Grid.Column="1" Margin="2,7,66,0" VerticalAlignment="Top">
                <TextBlock x:Name="TrackTitle" Text="Connecting to Music Assistant" Foreground="White"
                           FontSize="15" FontWeight="SemiBold" TextTrimming="CharacterEllipsis"/>
                <TextBlock x:Name="Artist" Text="Waiting for current playback"
                           Foreground="#BEC1C9" FontSize="12" Margin="0,4,0,0"
                           TextTrimming="CharacterEllipsis"/>
                <TextBlock x:Name="Source" Text="Music Assistant" Foreground="#80C7FF"
                           FontSize="10" Margin="0,5,0,0" TextTrimming="CharacterEllipsis"/>
            </StackPanel>
            <StackPanel x:Name="ChromePanel" Grid.Column="1" Orientation="Horizontal" HorizontalAlignment="Right"
                        VerticalAlignment="Top" Margin="0,-6,-6,0">
                <Button x:Name="PinButton" Content="&#xE840;" ToolTip="Always on top: on"
                        Style="{StaticResource ChromeButton}"/>
                <Button x:Name="MinimizeButton" Content="&#xE921;" ToolTip="Minimize"
                        Style="{StaticResource ChromeButton}"/>
                <Button x:Name="CloseButton" Content="&#xE8BB;" ToolTip="Close"
                        Style="{StaticResource ChromeButton}"/>
            </StackPanel>
            <StackPanel x:Name="TransportPanel" Grid.Column="1" Grid.Row="1" Orientation="Horizontal"
                        HorizontalAlignment="Left" VerticalAlignment="Center">
                <Button x:Name="PreviousButton" Content="&#xE892;" ToolTip="Previous"
                        Style="{StaticResource TransportButton}"/>
                <Button x:Name="PlayPauseButton" Content="&#xE768;" ToolTip="Play or pause"
                        Style="{StaticResource TransportButton}"/>
                <Button x:Name="NextButton" Content="&#xE893;" ToolTip="Next"
                        Style="{StaticResource TransportButton}"/>
                <Button x:Name="ShuffleButton" Content="&#xE8B1;" ToolTip="Shuffle: off"
                        Style="{StaticResource TransportButton}"/>
                <Button x:Name="RepeatButton" Content="&#xE8EE;" ToolTip="Repeat: off"
                        Style="{StaticResource TransportButton}"/>
            </StackPanel>
            <Grid x:Name="VolumePanel" Grid.Column="1" Grid.Row="2" Margin="1,0,18,0"
                  VerticalAlignment="Center">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="20"/>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="34"/>
                </Grid.ColumnDefinitions>
                <TextBlock Text="&#xE767;" FontFamily="Segoe MDL2 Assets" FontSize="13"
                           Foreground="#BEC1C9" VerticalAlignment="Center"/>
                <Slider x:Name="VolumeSlider" Grid.Column="1" Minimum="0" Maximum="100"
                        TickFrequency="1" IsSnapToTickEnabled="True" VerticalAlignment="Center"
                        ToolTip="Volume" Style="{StaticResource VolumeSliderStyle}"/>
                <TextBlock x:Name="VolumeText" Grid.Column="2" Text="--%" Foreground="#BEC1C9"
                           FontSize="10" TextAlignment="Right" VerticalAlignment="Center"/>
            </Grid>
        </Grid>
    </Border>
</Window>
'@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)
$dragSurface = $window.FindName('DragSurface')
$layoutGrid = $window.FindName('LayoutGrid')
$artworkFrame = $window.FindName('ArtworkFrame')
$infoPanel = $window.FindName('InfoPanel')
$chromePanel = $window.FindName('ChromePanel')
$transportPanel = $window.FindName('TransportPanel')
$volumePanel = $window.FindName('VolumePanel')
$volumeSlider = $window.FindName('VolumeSlider')
$volumeText = $window.FindName('VolumeText')
$artwork = $window.FindName('Artwork')
$artworkFallback = $window.FindName('ArtworkFallback')
$trackTitle = $window.FindName('TrackTitle')
$artist = $window.FindName('Artist')
$source = $window.FindName('Source')
$previousButton = $window.FindName('PreviousButton')
$playPauseButton = $window.FindName('PlayPauseButton')
$nextButton = $window.FindName('NextButton')
$shuffleButton = $window.FindName('ShuffleButton')
$repeatButton = $window.FindName('RepeatButton')
$pinButton = $window.FindName('PinButton')
$minimizeButton = $window.FindName('MinimizeButton')
$closeButton = $window.FindName('CloseButton')

$trayMenu = New-Object Windows.Forms.ContextMenuStrip
$trayOpenItem = New-Object Windows.Forms.ToolStripMenuItem('Open player')
$trayExitItem = New-Object Windows.Forms.ToolStripMenuItem('Exit')
[void]$trayMenu.Items.Add($trayOpenItem)
[void]$trayMenu.Items.Add($trayExitItem)
$notifyIcon = New-Object Windows.Forms.NotifyIcon
$iconPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'assets\ma-floater.ico'
$brandIcon = $null
$taskbarIconHandle = [IntPtr]::Zero
$ownsBrandIcon = $false
if (Test-Path -LiteralPath $iconPath) {
    try {
        $brandIcon = New-Object Drawing.Icon($iconPath)
        $taskbarIconHandle = [MAFloater.ShellIdentity]::LoadSharedIcon($iconPath, 40)
        $ownsBrandIcon = $true
        $window.Icon = [Windows.Interop.Imaging]::CreateBitmapSourceFromHIcon(
            $brandIcon.Handle,
            [Windows.Int32Rect]::Empty,
            [Windows.Media.Imaging.BitmapSizeOptions]::FromEmptyOptions()
        )
    }
    catch { $brandIcon = $null }
}
if ($null -eq $brandIcon) { $brandIcon = [Drawing.SystemIcons]::Application }
if ($taskbarIconHandle -eq [IntPtr]::Zero) { $taskbarIconHandle = $brandIcon.Handle }
$notifyIcon.Icon = $brandIcon
$notifyIcon.Text = 'MA Floater'
$notifyIcon.ContextMenuStrip = $trayMenu
$notifyIcon.Visible = $true

$settingsDirectory = Join-Path $env:LOCALAPPDATA 'MAFloater'
$settingsPath = Join-Path $settingsDirectory 'settings.txt'
$connectionPath = Join-Path $settingsDirectory 'connection.json'
$credentialPath = Join-Path $settingsDirectory 'credential.dat'
$script:httpClient = $null
$script:artworkHttpClient = $null
$script:serverUrl = $null
$script:preferredQueue = $null
$script:username = $null
$script:currentQueueId = $null
$script:currentPlayerId = $null
$script:mediaKey = ''
$script:refreshing = $false
$script:shuffleEnabled = $false
$script:repeatMode = 'off'
$script:isCompact = $false
$script:expandedWidth = 390.0
$script:expandedHeight = 150.0
$script:updatingVolume = $false
$script:volumeInteracting = $false

function Set-CompactMode {
    param([bool]$Compact)
    if ($Compact -eq $script:isCompact) { return }

    $right = $window.Left + $window.ActualWidth
    $bottom = $window.Top + $window.ActualHeight
    if ($Compact) {
        $script:expandedWidth = [Math]::Max(330, $window.ActualWidth)
        $script:expandedHeight = [Math]::Max(136, $window.ActualHeight)
        $source.Visibility = [Windows.Visibility]::Collapsed
        $chromePanel.Visibility = [Windows.Visibility]::Collapsed
        $transportPanel.Visibility = [Windows.Visibility]::Collapsed
        $volumePanel.Visibility = [Windows.Visibility]::Collapsed
        $dragSurface.Padding = [Windows.Thickness]::new(8)
        $layoutGrid.ColumnDefinitions[0].Width = [Windows.GridLength]::new(58)
        $layoutGrid.RowDefinitions[1].Height = [Windows.GridLength]::new(0)
        $layoutGrid.RowDefinitions[2].Height = [Windows.GridLength]::new(0)
        $artworkFrame.Width = 50
        $artworkFrame.Height = 50
        $infoPanel.Margin = [Windows.Thickness]::new(2, 5, 4, 0)
        $trackTitle.FontSize = 14
        $artist.FontSize = 11
        $window.ResizeMode = [Windows.ResizeMode]::NoResize
        $window.MinWidth = 240
        $window.MinHeight = 68
        $window.Width = 280
        $window.Height = 74
        $window.Left = $right - $window.Width
        $window.Top = $bottom - $window.Height
        $script:isCompact = $true
    }
    else {
        $source.Visibility = [Windows.Visibility]::Visible
        $chromePanel.Visibility = [Windows.Visibility]::Visible
        $transportPanel.Visibility = [Windows.Visibility]::Visible
        $volumePanel.Visibility = [Windows.Visibility]::Visible
        $dragSurface.Padding = [Windows.Thickness]::new(12)
        $layoutGrid.ColumnDefinitions[0].Width = [Windows.GridLength]::new(92)
        $layoutGrid.RowDefinitions[1].Height = [Windows.GridLength]::new(32)
        $layoutGrid.RowDefinitions[2].Height = [Windows.GridLength]::new(24)
        $artworkFrame.Width = 78
        $artworkFrame.Height = 78
        $infoPanel.Margin = [Windows.Thickness]::new(2, 7, 66, 0)
        $trackTitle.FontSize = 15
        $artist.FontSize = 12
        $window.MinWidth = 330
        $window.MinHeight = 136
        $window.Width = $script:expandedWidth
        $window.Height = $script:expandedHeight
        $window.ResizeMode = [Windows.ResizeMode]::CanResizeWithGrip
        $window.Left = $right - $window.Width
        $window.Top = $bottom - $window.Height
        $script:isCompact = $false
    }
    Clamp-ToVisibleDesktop
}

function Set-ControlState {
    param([bool]$Enabled)
    $previousButton.IsEnabled = $Enabled
    $playPauseButton.IsEnabled = $Enabled
    $nextButton.IsEnabled = $Enabled
    $shuffleButton.IsEnabled = $Enabled
    $repeatButton.IsEnabled = $Enabled
    $volumeSlider.IsEnabled = $false
}

function Update-PlayerVolume {
    param($Queue)
    try {
        $players = @(Invoke-MusicAssistantCommand 'players/all')
        $player = $players |
            Where-Object { $_.player_id -eq $Queue.queue_id } |
            Select-Object -First 1
        $supportsVolume = $null -ne $player -and
            $player.available -and
            @($player.supported_features) -contains 'volume_set' -and
            $null -ne $player.volume_level
        $volumeSlider.IsEnabled = $supportsVolume
        $volumePanel.Opacity = if ($supportsVolume) { 1.0 } else { 0.45 }
        if (-not $supportsVolume) {
            $volumeText.Text = '--%'
            return
        }
        $script:currentPlayerId = [string]$player.player_id
        if (-not $script:volumeInteracting) {
            $script:updatingVolume = $true
            try {
                $volumeSlider.Value = [Math]::Max(0, [Math]::Min(100, [double]$player.volume_level))
                $volumeText.Text = ([int][Math]::Round($volumeSlider.Value)).ToString() + '%'
            }
            finally { $script:updatingVolume = $false }
        }
    }
    catch {
        $volumeSlider.IsEnabled = $false
        $volumePanel.Opacity = 0.45
        $volumeText.Text = '--%'
    }
}

function Set-PlayerVolume {
    if ([string]::IsNullOrWhiteSpace($script:currentPlayerId) -or -not $volumeSlider.IsEnabled) { return }
    $level = [int][Math]::Round($volumeSlider.Value)
    try {
        [void](Invoke-MusicAssistantCommand 'players/cmd/volume_set' @{
            player_id = $script:currentPlayerId
            volume_level = $level
        })
        $volumeText.Text = $level.ToString() + '%'
    }
    catch { $source.Text = 'Volume failed: ' + $_.Exception.Message }
}

function Update-QueueModeAppearance {
    $shuffleButton.Foreground = if ($script:shuffleEnabled) { '#5CBFFF' } else { 'White' }
    $shuffleButton.Background = if ($script:shuffleEnabled) { '#315B78' } else { '#33363E' }
    $shuffleButton.ToolTip = if ($script:shuffleEnabled) { 'Shuffle: on' } else { 'Shuffle: off' }

    $repeatButton.Content = if ($script:repeatMode -eq 'one') { [char]0xE8ED } else { [char]0xE8EE }
    $repeatButton.Foreground = if ($script:repeatMode -eq 'off') { 'White' } else { '#5CBFFF' }
    $repeatButton.Background = if ($script:repeatMode -eq 'off') { '#33363E' } else { '#315B78' }
    $repeatButton.ToolTip = 'Repeat: ' + $script:repeatMode
}

function Set-FallbackArtwork {
    $artwork.Source = $null
    $artworkFallback.Visibility = [Windows.Visibility]::Visible
}

function Show-Unavailable {
    param([string]$Heading, [string]$Detail)
    $trackTitle.Text = $Heading
    $artist.Text = $Detail
    $window.Title = 'MA Floater - ' + $Heading
    $source.Text = 'Music Assistant'
    $script:currentQueueId = $null
    $script:currentPlayerId = $null
    $script:mediaKey = ''
    $script:shuffleEnabled = $false
    $script:repeatMode = 'off'
    Update-QueueModeAppearance
    Set-ControlState $false
    Set-FallbackArtwork
}

function Get-ProtectedPassword {
    if (-not (Test-Path -LiteralPath $credentialPath)) { return $null }
    $protectedBytes = [IO.File]::ReadAllBytes($credentialPath)
    $plainBytes = [Security.Cryptography.ProtectedData]::Unprotect(
        $protectedBytes, $null, [Security.Cryptography.DataProtectionScope]::CurrentUser
    )
    try { return [Text.Encoding]::UTF8.GetString($plainBytes) }
    finally { [Array]::Clear($plainBytes, 0, $plainBytes.Length) }
}

function Connect-MusicAssistant {
    $password = Get-ProtectedPassword
    if ([string]::IsNullOrWhiteSpace($password)) {
        throw 'Run Set-MusicAssistantConnection.ps1 first.'
    }
    $payload = @{
        provider_id = 'builtin'
        credentials = @{
            username = $script:username
            password = $password
        }
        device_name = 'MA Floater for Windows'
    } | ConvertTo-Json -Depth 6 -Compress
    $password = $null
    $content = New-Object Net.Http.StringContent($payload, [Text.Encoding]::UTF8, 'application/json')
    try {
        $script:httpClient.DefaultRequestHeaders.Authorization = $null
        $response = $script:httpClient.PostAsync($script:serverUrl + '/auth/login', $content).GetAwaiter().GetResult()
        try {
            $body = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
            if (-not $response.IsSuccessStatusCode) {
                throw "Music Assistant sign-in failed (HTTP $([int]$response.StatusCode))."
            }
            $login = $body | ConvertFrom-Json
            $accessToken = if ($login.token) { [string]$login.token } else { [string]$login.access_token }
            if (-not $login.success -or [string]::IsNullOrWhiteSpace($accessToken)) {
                $detail = if ($login.error) { [string]$login.error } else { 'Music Assistant rejected the sign-in.' }
                throw $detail
            }
            $script:httpClient.DefaultRequestHeaders.Authorization =
                New-Object Net.Http.Headers.AuthenticationHeaderValue('Bearer', $accessToken)
            $accessToken = $null
            if ([string]$login.user.role -ne 'guest') {
                Disconnect-MusicAssistant
                throw 'The configured account is not a Guest account; refusing broader access.'
            }
        }
        finally { $response.Dispose() }
    }
    finally {
        $payload = $null
        $content.Dispose()
    }
}

function Disconnect-MusicAssistant {
    if ($null -eq $script:httpClient -or $null -eq $script:httpClient.DefaultRequestHeaders.Authorization) { return }
    $payload = @{
        command = 'auth/logout'
        message_id = [guid]::NewGuid().ToString('N')
        args = @{}
    } | ConvertTo-Json -Compress
    $content = New-Object Net.Http.StringContent($payload, [Text.Encoding]::UTF8, 'application/json')
    try {
        $response = $script:httpClient.PostAsync($script:serverUrl + '/api', $content).GetAwaiter().GetResult()
        $response.Dispose()
    }
    catch {}
    finally {
        $content.Dispose()
        $script:httpClient.DefaultRequestHeaders.Authorization = $null
    }
}

function Initialize-MusicAssistantConnection {
    if (-not (Test-Path -LiteralPath $connectionPath)) {
        throw 'Run Set-MusicAssistantConnection.ps1 first.'
    }
    $config = Get-Content -LiteralPath $connectionPath -Raw | ConvertFrom-Json
    if ([string]::IsNullOrWhiteSpace($config.server_url)) {
        throw 'The Music Assistant server URL is missing.'
    }
    if ([string]::IsNullOrWhiteSpace($config.username)) {
        throw 'The Music Assistant username is missing.'
    }
    $script:serverUrl = $config.server_url.TrimEnd('/')
    $script:preferredQueue = [string]$config.preferred_queue
    $script:username = [string]$config.username
    $handler = New-Object Net.Http.HttpClientHandler
    $script:httpClient = New-Object Net.Http.HttpClient($handler)
    $script:httpClient.Timeout = [TimeSpan]::FromSeconds(3)
    $script:httpClient.DefaultRequestHeaders.UserAgent.ParseAdd('MAFloater/0.1.1')
    $script:artworkHttpClient = New-Object Net.Http.HttpClient
    $script:artworkHttpClient.Timeout = [TimeSpan]::FromSeconds(3)
    $script:artworkHttpClient.DefaultRequestHeaders.UserAgent.ParseAdd('MAFloater/0.1.1')
    Connect-MusicAssistant
}

function Invoke-MusicAssistantCommand {
    param(
        [Parameter(Mandatory = $true)] [string]$Command,
        [hashtable]$Arguments = @{}
    )
    if ($null -eq $script:httpClient) { throw 'Music Assistant is not configured.' }
    for ($attempt = 0; $attempt -lt 2; $attempt++) {
        $payload = @{
            command = $Command
            message_id = [guid]::NewGuid().ToString('N')
            args = $Arguments
        } | ConvertTo-Json -Depth 12 -Compress
        $content = New-Object Net.Http.StringContent($payload, [Text.Encoding]::UTF8, 'application/json')
        try {
            $response = $script:httpClient.PostAsync($script:serverUrl + '/api', $content).GetAwaiter().GetResult()
            try {
                $body = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
                if ([int]$response.StatusCode -eq 401 -and $attempt -eq 0) {
                    Connect-MusicAssistant
                    continue
                }
                if (-not $response.IsSuccessStatusCode) {
                    throw "HTTP $([int]$response.StatusCode): $body"
                }
                $message = $body | ConvertFrom-Json
                $propertyNames = @($message.PSObject.Properties.Name)
                if ($propertyNames -contains 'error_code') {
                    $detail = if ($message.details) { [string]$message.details } else { 'Music Assistant rejected the request.' }
                    throw $detail
                }
                if ($propertyNames -contains 'result') { return $message.result }
                return $message
            }
            finally { $response.Dispose() }
        }
        finally { $content.Dispose() }
    }
    throw 'Music Assistant sign-in could not be refreshed.'
}

function Get-ArtistText {
    param($QueueItem)
    $streamArtist = $QueueItem.streamdetails.stream_metadata.artist
    if (-not [string]::IsNullOrWhiteSpace($streamArtist)) { return $streamArtist }
    $mediaItem = $QueueItem.media_item
    if ($null -ne $mediaItem.artists) {
        $names = @($mediaItem.artists | ForEach-Object { $_.name } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        if ($names.Count -gt 0) { return $names -join ', ' }
    }
    if (-not [string]::IsNullOrWhiteSpace($mediaItem.publisher)) { return $mediaItem.publisher }
    return 'Unknown artist'
}

function Get-TitleText {
    param($QueueItem)
    $streamTitle = $QueueItem.streamdetails.stream_metadata.title
    if (-not [string]::IsNullOrWhiteSpace($streamTitle)) { return $streamTitle }
    if (-not [string]::IsNullOrWhiteSpace($QueueItem.media_item.name)) { return $QueueItem.media_item.name }
    if (-not [string]::IsNullOrWhiteSpace($QueueItem.name)) { return $QueueItem.name }
    return 'Unknown track'
}

function Get-ArtworkUrl {
    param($QueueItem)
    $streamUrl = $QueueItem.streamdetails.stream_metadata.image_url
    if (-not [string]::IsNullOrWhiteSpace($streamUrl)) {
        if ([uri]::IsWellFormedUriString($streamUrl, [UriKind]::Absolute)) { return $streamUrl }
        return $script:serverUrl + '/' + $streamUrl.TrimStart('/')
    }
    if ($null -ne $QueueItem.image -and -not [string]::IsNullOrWhiteSpace($QueueItem.image.proxy_id)) {
        return $script:serverUrl + '/imageproxy/' + [uri]::EscapeDataString($QueueItem.image.proxy_id)
    }
    return $null
}

function Update-Artwork {
    param([string]$Url)
    if ([string]::IsNullOrWhiteSpace($Url)) { Set-FallbackArtwork; return }
    try {
        $artworkUri = $null
        if (-not [uri]::TryCreate($Url, [UriKind]::Absolute, [ref]$artworkUri) -or
            $artworkUri.Scheme -notin @('http', 'https')) {
            throw 'Artwork URL must use HTTP or HTTPS.'
        }
        if ($null -eq $script:artworkHttpClient -or
            $null -ne $script:artworkHttpClient.DefaultRequestHeaders.Authorization) {
            throw 'The unauthenticated artwork client is unavailable.'
        }
        $bytes = $script:artworkHttpClient.GetByteArrayAsync($artworkUri).GetAwaiter().GetResult()
        $stream = New-Object IO.MemoryStream(,$bytes)
        try {
            $bitmap = New-Object Windows.Media.Imaging.BitmapImage
            $bitmap.BeginInit()
            $bitmap.CacheOption = [Windows.Media.Imaging.BitmapCacheOption]::OnLoad
            $bitmap.StreamSource = $stream
            $bitmap.EndInit()
            $bitmap.Freeze()
            $artwork.Source = $bitmap
            $artworkFallback.Visibility = [Windows.Visibility]::Collapsed
        }
        finally { $stream.Dispose() }
    }
    catch { Set-FallbackArtwork }
}

function Select-CurrentQueue {
    param([object[]]$Queues)
    $withItems = @($Queues | Where-Object { $_.available -and $null -ne $_.current_item })
    if ($withItems.Count -eq 0) { return $null }

    $playing = @($withItems | Where-Object { $_.state -eq 'playing' })
    if (-not [string]::IsNullOrWhiteSpace($script:currentQueueId)) {
        $currentPlaying = $playing |
            Where-Object { $_.queue_id -eq $script:currentQueueId } |
            Select-Object -First 1
        if ($null -ne $currentPlaying) { return $currentPlaying }
    }

    if (-not [string]::IsNullOrWhiteSpace($script:preferredQueue)) {
        $preferredPlaying = $playing |
            Where-Object { $_.display_name -eq $script:preferredQueue } |
            Select-Object -First 1
        if ($null -ne $preferredPlaying) { return $preferredPlaying }
    }

    $anyPlaying = $playing | Select-Object -First 1
    if ($null -ne $anyPlaying) { return $anyPlaying }

    if (-not [string]::IsNullOrWhiteSpace($script:currentQueueId)) {
        $currentQueue = $withItems |
            Where-Object { $_.queue_id -eq $script:currentQueueId } |
            Select-Object -First 1
        if ($null -ne $currentQueue) { return $currentQueue }
    }

    if ([string]::IsNullOrWhiteSpace($script:preferredQueue)) { return $null }
    return $withItems |
        Where-Object { $_.display_name -eq $script:preferredQueue } |
        Select-Object -First 1
}

function Update-MusicAssistant {
    if ($script:refreshing -or $null -eq $script:httpClient) { return }
    $script:refreshing = $true
    try {
        $queues = @(Invoke-MusicAssistantCommand 'player_queues/all')
        $queue = Select-CurrentQueue $queues
        if ($null -eq $queue) {
            Show-Unavailable 'Nothing queued' 'Start playback in Music Assistant'
            return
        }
        $item = $queue.current_item
        $currentTitle = Get-TitleText $item
        $currentArtist = Get-ArtistText $item
        $trackTitle.Text = $currentTitle
        $artist.Text = $currentArtist
        $window.Title = 'MA Floater - ' + $currentTitle + ' - ' + $currentArtist
        $source.Text = 'Music Assistant ' + [char]0x2022 + ' ' + $queue.display_name
        $script:currentQueueId = $queue.queue_id
        $script:shuffleEnabled = [bool]$queue.shuffle_enabled
        $script:repeatMode = if ([string]::IsNullOrWhiteSpace([string]$queue.repeat_mode)) {
            'off'
        }
        else { [string]$queue.repeat_mode }
        Update-QueueModeAppearance
        $playPauseButton.Content = if ($queue.state -eq 'playing') { [char]0xE769 } else { [char]0xE768 }
        $previousButton.IsEnabled = $queue.items -gt 1
        $nextButton.IsEnabled = $queue.items -gt 1
        $playPauseButton.IsEnabled = $queue.available
        $shuffleButton.IsEnabled = $queue.available
        $repeatButton.IsEnabled = $queue.available
        Update-PlayerVolume $queue
        $artworkUrl = Get-ArtworkUrl $item
        $newMediaKey = $queue.queue_id + "`n" + $item.queue_item_id + "`n" + $artworkUrl
        if ($newMediaKey -ne $script:mediaKey) {
            $script:mediaKey = $newMediaKey
            Update-Artwork $artworkUrl
        }
    }
    catch {
        $message = $_.Exception.Message
        if ($message -match '(?i)auth|sign-in|401|403') {
            Show-Unavailable 'Music Assistant sign-in required' 'The saved Guest credential is missing or was rejected'
        }
        else { Show-Unavailable 'Music Assistant unavailable' $message }
    }
    finally { $script:refreshing = $false }
}

function Invoke-Transport {
    param([ValidateSet('Previous', 'Toggle', 'Next', 'Shuffle', 'Repeat')] [string]$Command)
    if ([string]::IsNullOrWhiteSpace($script:currentQueueId)) { return }
    try {
        $apiCommand = $null
        $arguments = @{ queue_id = $script:currentQueueId }
        switch ($Command) {
            'Previous' { $apiCommand = 'player_queues/previous' }
            'Next' { $apiCommand = 'player_queues/next' }
            'Toggle' { $apiCommand = 'player_queues/play_pause' }
            'Shuffle' {
                $apiCommand = 'player_queues/shuffle'
                $arguments.shuffle_enabled = -not $script:shuffleEnabled
            }
            'Repeat' {
                $apiCommand = 'player_queues/repeat'
                $arguments.repeat_mode = switch ($script:repeatMode) {
                    'off' { 'all' }
                    'all' { 'one' }
                    default { 'off' }
                }
            }
        }
        [void](Invoke-MusicAssistantCommand $apiCommand $arguments)
        Update-MusicAssistant
    }
    catch { $source.Text = 'Control failed: ' + $_.Exception.Message }
}

function Save-WindowSettings {
    try {
        $leftToSave = $window.Left
        $topToSave = $window.Top
        if ($script:isCompact) {
            $leftToSave = $window.Left + $window.ActualWidth - $script:expandedWidth
            $topToSave = $window.Top + $window.ActualHeight - $script:expandedHeight
        }
        New-Item -ItemType Directory -Path $settingsDirectory -Force | Out-Null
        @(
            'left=' + $leftToSave.ToString([Globalization.CultureInfo]::InvariantCulture)
            'top=' + $topToSave.ToString([Globalization.CultureInfo]::InvariantCulture)
            'topmost=' + $window.Topmost.ToString([Globalization.CultureInfo]::InvariantCulture)
        ) | Set-Content -LiteralPath $settingsPath -Encoding ASCII
    }
    catch {}
}

function Load-WindowSettings {
    $window.Left = [Windows.SystemParameters]::WorkArea.Right - $window.Width - 24
    $window.Top = [Windows.SystemParameters]::WorkArea.Bottom - $window.Height - 24
    if (-not (Test-Path -LiteralPath $settingsPath)) { return }
    try {
        foreach ($line in Get-Content -LiteralPath $settingsPath) {
            $parts = $line -split '=', 2
            if ($parts.Count -ne 2) { continue }
            if ($parts[0] -eq 'left') { $window.Left = [double]::Parse($parts[1], [Globalization.CultureInfo]::InvariantCulture) }
            if ($parts[0] -eq 'top') { $window.Top = [double]::Parse($parts[1], [Globalization.CultureInfo]::InvariantCulture) }
            if ($parts[0] -eq 'topmost') { $window.Topmost = [bool]::Parse($parts[1]) }
        }
    }
    catch {}
}

function Clamp-ToVisibleDesktop {
    $left = [Windows.SystemParameters]::VirtualScreenLeft
    $top = [Windows.SystemParameters]::VirtualScreenTop
    $right = $left + [Windows.SystemParameters]::VirtualScreenWidth
    $bottom = $top + [Windows.SystemParameters]::VirtualScreenHeight
    $window.Left = [Math]::Max($left, [Math]::Min($window.Left, $right - [Math]::Max(120, $window.Width)))
    $window.Top = [Math]::Max($top, [Math]::Min($window.Top, $bottom - [Math]::Max(60, $window.Height)))
}

function Update-PinAppearance {
    $pinButton.Foreground = if ($window.Topmost) { '#5CBFFF' } else { '#D2D5DC' }
    $pinButton.ToolTip = if ($window.Topmost) { 'Always on top: on' } else { 'Always on top: off' }
}

function Restore-PlayerWindow {
    $window.Dispatcher.Invoke([Action]{
        $window.Show()
        $window.WindowState = [Windows.WindowState]::Normal
        Set-CompactMode $false
        [void]$window.Activate()
    })
}

$timer = New-Object Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromSeconds(2)
$timer.Add_Tick({ Update-MusicAssistant })
$compactTimer = New-Object Windows.Threading.DispatcherTimer
$compactTimer.Interval = [TimeSpan]::FromSeconds(15)
$compactTimer.Add_Tick({
    $compactTimer.Stop()
    if (-not $window.IsMouseOver -and $window.WindowState -eq [Windows.WindowState]::Normal) {
        Set-CompactMode $true
    }
})
$previousButton.Add_Click({ Invoke-Transport 'Previous' })
$playPauseButton.Add_Click({ Invoke-Transport 'Toggle' })
$nextButton.Add_Click({ Invoke-Transport 'Next' })
$shuffleButton.Add_Click({ Invoke-Transport 'Shuffle' })
$repeatButton.Add_Click({ Invoke-Transport 'Repeat' })
$volumeSlider.Add_ValueChanged({
    if (-not $script:updatingVolume) {
        $volumeText.Text = ([int][Math]::Round($volumeSlider.Value)).ToString() + '%'
    }
})
$volumeSlider.Add_PreviewMouseLeftButtonDown({ $script:volumeInteracting = $true })
$volumeSlider.Add_PreviewMouseLeftButtonUp({
    if ($script:volumeInteracting) {
        $script:volumeInteracting = $false
        Set-PlayerVolume
    }
})
$volumeSlider.Add_PreviewKeyUp({ Set-PlayerVolume })
$pinButton.Add_Click({
    $window.Topmost = -not $window.Topmost
    Update-PinAppearance
    Save-WindowSettings
})
$minimizeButton.Add_Click({ $window.WindowState = [Windows.WindowState]::Minimized })
$closeButton.Add_Click({ $window.Close() })
$notifyIcon.Add_DoubleClick({ Restore-PlayerWindow })
$trayOpenItem.Add_Click({ Restore-PlayerWindow })
$trayExitItem.Add_Click({ $window.Dispatcher.Invoke([Action]{ $window.Close() }) })
$window.Add_MouseEnter({
    $compactTimer.Stop()
    Set-CompactMode $false
})
$window.Add_MouseLeave({
    $compactTimer.Stop()
    if ($window.WindowState -eq [Windows.WindowState]::Normal) { $compactTimer.Start() }
})
$dragSurface.Add_MouseLeftButtonDown({
    param($sender, $eventArgs)
    $node = $eventArgs.OriginalSource -as [Windows.DependencyObject]
    while ($null -ne $node) {
        if ($node -is [Windows.Controls.Primitives.ButtonBase]) { return }
        $node = [Windows.Media.VisualTreeHelper]::GetParent($node)
    }
    try { $window.DragMove(); Save-WindowSettings } catch {}
})
$window.Add_Loaded({
    $windowHandle = (New-Object Windows.Interop.WindowInteropHelper($window)).Handle
    [MAFloater.ShellIdentity]::SetWindowIcons($windowHandle, $taskbarIconHandle)
    Load-WindowSettings
    Clamp-ToVisibleDesktop
    Update-PinAppearance
    Update-QueueModeAppearance
    Set-ControlState $false
    try {
        Initialize-MusicAssistantConnection
        $timer.Start()
        $compactTimer.Start()
        Update-MusicAssistant
    }
    catch { Show-Unavailable 'Music Assistant setup needed' $_.Exception.Message }
})
$window.Add_Closing({
    $timer.Stop()
    $compactTimer.Stop()
    $notifyIcon.Visible = $false
    $notifyIcon.Dispose()
    if ($ownsBrandIcon -and $null -ne $brandIcon) { $brandIcon.Dispose() }
    $trayMenu.Dispose()
    if ($null -ne $script:httpClient) {
        Disconnect-MusicAssistant
        $script:httpClient.Dispose()
    }
    if ($null -ne $script:artworkHttpClient) { $script:artworkHttpClient.Dispose() }
    Save-WindowSettings
})

try { [void]$window.ShowDialog() }
finally {
    if ($createdNew) { $singleInstance.ReleaseMutex() }
    $singleInstance.Dispose()
}
