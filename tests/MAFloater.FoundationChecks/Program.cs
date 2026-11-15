using MAFloater.Core;

var failures = new List<string>();

Check(AppPaths.SettingsDirectory.EndsWith(
    Path.Combine("AppData", "Local", AppPaths.ApplicationDirectoryName),
    StringComparison.OrdinalIgnoreCase), "Settings remain under the current user's LocalAppData folder.");
Check(Path.GetFileName(AppPaths.CredentialPath) == "credential.dat", "Credential path remains compatible.");
Check(Path.GetFileName(AppPaths.ConnectionSettingsPath) == "connection.json", "Connection path remains compatible.");

CheckValid("http://music-assistant.local:8095", "guest-user");
CheckValid("https://music.example.test", "guest-user");
CheckInvalid("ftp://music.example.test", "guest-user");
CheckInvalid("music-assistant.local:8095", "guest-user");
CheckInvalid("http://music-assistant.local:8095", " ");

if (failures.Count > 0)
{
    foreach (var failure in failures)
    {
        Console.Error.WriteLine($"FAIL: {failure}");
    }

    return 1;
}

Console.WriteLine("PASS: native settings paths and connection validation checks passed.");
return 0;

void CheckValid(string serverUrl, string username)
{
    var settings = new ConnectionSettings { ServerUrl = serverUrl, Username = username };
    Check(ConnectionSettingsValidator.TryValidate(settings, out _), $"Expected valid settings: {serverUrl}");
}

void CheckInvalid(string serverUrl, string username)
{
    var settings = new ConnectionSettings { ServerUrl = serverUrl, Username = username };
    Check(!ConnectionSettingsValidator.TryValidate(settings, out var error) && !string.IsNullOrWhiteSpace(error),
        $"Expected invalid settings: {serverUrl}");
}

void Check(bool condition, string message)
{
    if (!condition)
    {
        failures.Add(message);
    }
}
