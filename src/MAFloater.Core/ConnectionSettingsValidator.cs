namespace MAFloater.Core;

public static class ConnectionSettingsValidator
{
    public static bool TryValidate(ConnectionSettings? settings, out string error)
    {
        if (settings is null)
        {
            error = "Connection settings are required.";
            return false;
        }

        if (!Uri.TryCreate(settings.ServerUrl, UriKind.Absolute, out var serverUri) ||
            (serverUri.Scheme != Uri.UriSchemeHttp && serverUri.Scheme != Uri.UriSchemeHttps) ||
            string.IsNullOrWhiteSpace(serverUri.Host))
        {
            error = "The Music Assistant address must be an absolute HTTP or HTTPS URL.";
            return false;
        }

        if (string.IsNullOrWhiteSpace(settings.Username))
        {
            error = "A dedicated Music Assistant Guest username is required.";
            return false;
        }

        error = string.Empty;
        return true;
    }
}
