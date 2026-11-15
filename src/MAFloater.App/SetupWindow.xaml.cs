using System.Windows;
using MAFloater.Core;

namespace MAFloater.App;

public partial class SetupWindow : Window
{
    public SetupWindow(ConnectionSettings? existingSettings)
    {
        InitializeComponent();
        ServerUrlBox.Text = existingSettings?.ServerUrl ?? "http://music-assistant.local:8095";
        UsernameBox.Text = existingSettings?.Username ?? string.Empty;
        PreferredQueueBox.Text = existingSettings?.PreferredQueue ?? string.Empty;
    }

    private async void SaveButton_Click(object sender, RoutedEventArgs e)
    {
        var settings = new ConnectionSettings
        {
            ServerUrl = ServerUrlBox.Text,
            Username = UsernameBox.Text,
            PreferredQueue = PreferredQueueBox.Text
        };
        if (!ConnectionSettingsValidator.TryValidate(settings, out var error))
        {
            StatusText.Text = error;
            return;
        }

        var password = PasswordBox.Password;
        if (string.IsNullOrWhiteSpace(password))
        {
            StatusText.Text = "Enter the Guest account password.";
            return;
        }

        SaveButton.IsEnabled = false;
        StatusText.Text = "Testing the Guest account…";
        try
        {
            await using (var client = new MusicAssistantClient())
            {
                await client.LoginAsync(settings, password);
            }

            ConnectionConfigurationStore.Save(settings, password);
            PasswordBox.Clear();
            DialogResult = true;
        }
        catch (Exception exception)
        {
            StatusText.Text = exception.Message;
        }
        finally
        {
            SaveButton.IsEnabled = true;
        }
    }

    private void CancelButton_Click(object sender, RoutedEventArgs e)
    {
        PasswordBox.Clear();
        DialogResult = false;
    }
}
