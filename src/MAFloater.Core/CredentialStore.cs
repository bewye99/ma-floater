using System.Security.Cryptography;
using System.Text;

namespace MAFloater.Core;

public static class CredentialStore
{
    public static bool Exists(string? path = null) => File.Exists(path ?? AppPaths.CredentialPath);

    public static string LoadPassword(string? path = null)
    {
        path ??= AppPaths.CredentialPath;
        if (!File.Exists(path))
        {
            throw new FileNotFoundException("The Music Assistant credential was not found.", path);
        }

        var protectedBytes = File.ReadAllBytes(path);
        var plainBytes = ProtectedData.Unprotect(protectedBytes, null, DataProtectionScope.CurrentUser);
        try
        {
            return Encoding.UTF8.GetString(plainBytes);
        }
        finally
        {
            CryptographicOperations.ZeroMemory(plainBytes);
        }
    }

    public static void SavePassword(string password, string? path = null)
    {
        if (string.IsNullOrWhiteSpace(password))
        {
            throw new ArgumentException("A password is required.", nameof(password));
        }

        path ??= AppPaths.CredentialPath;
        var directory = Path.GetDirectoryName(path)
            ?? throw new InvalidOperationException("The credential path has no parent directory.");
        Directory.CreateDirectory(directory);

        var plainBytes = Encoding.UTF8.GetBytes(password);
        byte[]? protectedBytes = null;
        var temporaryPath = path + ".tmp";
        try
        {
            protectedBytes = ProtectedData.Protect(plainBytes, null, DataProtectionScope.CurrentUser);
            File.WriteAllBytes(temporaryPath, protectedBytes);
            File.Move(temporaryPath, path, true);
        }
        finally
        {
            if (File.Exists(temporaryPath))
            {
                File.Delete(temporaryPath);
            }

            CryptographicOperations.ZeroMemory(plainBytes);
            if (protectedBytes is not null)
            {
                CryptographicOperations.ZeroMemory(protectedBytes);
            }
        }
    }
}
