using Microsoft.Win32;

namespace MAFloater.App;

internal static class StartupRegistration
{
    private const string RunKeyPath = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private const string ValueName = "MA Floater";

    public static bool IsEnabled()
    {
        var executablePath = Environment.ProcessPath;
        if (string.IsNullOrWhiteSpace(executablePath))
        {
            return false;
        }

        using var key = Registry.CurrentUser.OpenSubKey(RunKeyPath, writable: false);
        return string.Equals(
            key?.GetValue(ValueName) as string,
            Quote(executablePath),
            StringComparison.OrdinalIgnoreCase);
    }

    public static void SetEnabled(bool enabled)
    {
        var executablePath = Environment.ProcessPath
            ?? throw new InvalidOperationException("The MA Floater executable path is unavailable.");
        using var key = Registry.CurrentUser.CreateSubKey(RunKeyPath, writable: true)
            ?? throw new InvalidOperationException("The current user's Windows startup settings are unavailable.");

        if (enabled)
        {
            key.SetValue(ValueName, Quote(executablePath), RegistryValueKind.String);
            return;
        }

        if (string.Equals(
            key.GetValue(ValueName) as string,
            Quote(executablePath),
            StringComparison.OrdinalIgnoreCase))
        {
            key.DeleteValue(ValueName, throwOnMissingValue: false);
        }
    }

    private static string Quote(string path) => $"\"{path}\"";
}
