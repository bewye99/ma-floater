namespace MAFloater.Core;

public static class ConnectionConfigurationStore
{
    public static void Save(
        ConnectionSettings settings,
        string password,
        string? settingsPath = null,
        string? credentialPath = null)
    {
        settingsPath ??= AppPaths.ConnectionSettingsPath;
        credentialPath ??= AppPaths.CredentialPath;
        var priorSettings = File.Exists(settingsPath) ? File.ReadAllBytes(settingsPath) : null;
        var priorCredential = File.Exists(credentialPath) ? File.ReadAllBytes(credentialPath) : null;

        try
        {
            ConnectionSettingsStore.Save(settings, settingsPath);
            CredentialStore.SavePassword(password, credentialPath);
        }
        catch
        {
            Restore(settingsPath, priorSettings);
            Restore(credentialPath, priorCredential);
            throw;
        }
    }

    private static void Restore(string path, byte[]? contents)
    {
        if (contents is null)
        {
            if (File.Exists(path))
            {
                File.Delete(path);
            }

            return;
        }

        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllBytes(path, contents);
    }
}
