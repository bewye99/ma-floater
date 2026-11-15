using System.Text.Json;

namespace MAFloater.Core;

public static class ConnectionSettingsStore
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = true
    };

    public static ConnectionSettings Load(string? path = null)
    {
        path ??= AppPaths.ConnectionSettingsPath;
        if (!File.Exists(path))
        {
            throw new FileNotFoundException("Music Assistant connection settings were not found.", path);
        }

        var settings = JsonSerializer.Deserialize<ConnectionSettings>(File.ReadAllText(path), JsonOptions)
            ?? throw new InvalidDataException("Music Assistant connection settings are empty.");
        if (!ConnectionSettingsValidator.TryValidate(settings, out var error))
        {
            throw new InvalidDataException(error);
        }

        return settings;
    }

    public static void Save(ConnectionSettings settings, string? path = null)
    {
        if (!ConnectionSettingsValidator.TryValidate(settings, out var error))
        {
            throw new ArgumentException(error, nameof(settings));
        }

        path ??= AppPaths.ConnectionSettingsPath;
        var directory = Path.GetDirectoryName(path)
            ?? throw new InvalidOperationException("The settings path has no parent directory.");
        Directory.CreateDirectory(directory);

        var normalized = new ConnectionSettings
        {
            ServerUrl = settings.ServerUrl.Trim().TrimEnd('/'),
            Username = settings.Username.Trim(),
            PreferredQueue = settings.PreferredQueue.Trim()
        };
        var temporaryPath = path + ".tmp";
        try
        {
            File.WriteAllText(temporaryPath, JsonSerializer.Serialize(normalized, JsonOptions));
            File.Move(temporaryPath, path, true);
        }
        finally
        {
            if (File.Exists(temporaryPath))
            {
                File.Delete(temporaryPath);
            }
        }
    }
}
