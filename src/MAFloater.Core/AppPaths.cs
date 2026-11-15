namespace MAFloater.Core;

public static class AppPaths
{
    public const string ApplicationDirectoryName = "MAFloater";

    public static string SettingsDirectory =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), ApplicationDirectoryName);

    public static string ConnectionSettingsPath => Path.Combine(SettingsDirectory, "connection.json");

    public static string CredentialPath => Path.Combine(SettingsDirectory, "credential.dat");

    public static string WindowSettingsPath => Path.Combine(SettingsDirectory, "settings.json");
}
