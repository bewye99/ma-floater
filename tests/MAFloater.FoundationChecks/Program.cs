using System.Net;
using System.Text;
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

var temporaryDirectory = Path.Combine(Path.GetTempPath(), "MAFloater-FoundationChecks-" + Guid.NewGuid().ToString("N"));
Directory.CreateDirectory(temporaryDirectory);
try
{
    var settingsPath = Path.Combine(temporaryDirectory, "connection.json");
    var credentialPath = Path.Combine(temporaryDirectory, "credential.dat");
    var settings = new ConnectionSettings
    {
        ServerUrl = "http://music-assistant.local:8095/",
        Username = "guest-user ",
        PreferredQueue = " Living Room "
    };
    ConnectionConfigurationStore.Save(settings, "test-password", settingsPath, credentialPath);
    var loaded = ConnectionSettingsStore.Load(settingsPath);
    Check(loaded.ServerUrl == "http://music-assistant.local:8095", "Server URL is normalized compatibly.");
    Check(loaded.Username == "guest-user", "Username is normalized compatibly.");
    Check(loaded.PreferredQueue == "Living Room", "Preferred queue is normalized compatibly.");
    Check(CredentialStore.LoadPassword(credentialPath) == "test-password", "DPAPI credential round-trip succeeds.");
    Check(!Encoding.UTF8.GetString(File.ReadAllBytes(credentialPath)).Contains("test-password", StringComparison.Ordinal),
        "Credential file does not contain the plaintext password.");
}
finally
{
    Directory.Delete(temporaryDirectory, true);
}

await CheckGuestAuthenticationAndNowPlayingAsync();
await CheckNonGuestRejectionAsync();

if (failures.Count > 0)
{
    foreach (var failure in failures)
    {
        Console.Error.WriteLine($"FAIL: {failure}");
    }

    return 1;
}

Console.WriteLine("PASS: native settings, DPAPI, Guest authentication, request isolation, and queue selection checks passed.");
return 0;

async Task CheckGuestAuthenticationAndNowPlayingAsync()
{
    var handler = new ScriptedHandler(
        """{"success":true,"token":"token-value","user":{"role":"guest"}}""",
        """[{"queue_id":"preferred","display_name":"Preferred","state":"idle","available":true,"current_item":{"name":"Idle"}},{"queue_id":"active","display_name":"Active","state":"playing","available":true,"current_item":{"media_item":{"name":"Current track","artists":[{"name":"Current artist"}]}}}]""",
        """{"result":true}""");
    using var httpClient = new HttpClient(handler) { Timeout = TimeSpan.FromSeconds(3) };
    await using var client = new MusicAssistantClient(httpClient);
    var settings = new ConnectionSettings
    {
        ServerUrl = "https://music.example.test",
        Username = "guest-user",
        PreferredQueue = "Preferred"
    };
    await client.LoginAsync(settings, "password");
    var snapshot = await client.GetNowPlayingAsync(settings.PreferredQueue);
    Check(snapshot.HasQueue && snapshot.QueueId == "active", "Playing queue wins over an idle preferred queue.");
    Check(snapshot.Title == "Current track" && snapshot.Artist == "Current artist", "Now-playing metadata is extracted.");
    Check(handler.Requests.Count >= 2, "Login and queue requests were captured.");
    Check(handler.Requests[0].Path == "/auth/login" && handler.Requests[0].Authorization is null,
        "Login is sent without a bearer header.");
    Check(handler.Requests[1].Path == "/api" && handler.Requests[1].Authorization == "Bearer token-value",
        "Bearer authorization is scoped to the Music Assistant API request.");
}

async Task CheckNonGuestRejectionAsync()
{
    var handler = new ScriptedHandler(
        """{"success":true,"token":"admin-token","user":{"role":"admin"}}""",
        """{"result":true}""");
    using var httpClient = new HttpClient(handler) { Timeout = TimeSpan.FromSeconds(3) };
    await using var client = new MusicAssistantClient(httpClient);
    try
    {
        await client.LoginAsync(new ConnectionSettings
        {
            ServerUrl = "https://music.example.test",
            Username = "admin-user"
        }, "password");
        Check(false, "Non-Guest account was accepted.");
    }
    catch (InvalidOperationException exception)
    {
        Check(exception.Message.Contains("not a Guest account", StringComparison.Ordinal),
            "Non-Guest account is rejected explicitly.");
    }
}

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

sealed class ScriptedHandler(params string[] responseBodies) : HttpMessageHandler
{
    private readonly Queue<string> responses = new(responseBodies);

    public List<CapturedRequest> Requests { get; } = [];

    protected override async Task<HttpResponseMessage> SendAsync(
        HttpRequestMessage request,
        CancellationToken cancellationToken)
    {
        var body = request.Content is null
            ? string.Empty
            : await request.Content.ReadAsStringAsync(cancellationToken);
        Requests.Add(new CapturedRequest(
            request.RequestUri?.AbsolutePath ?? string.Empty,
            request.Headers.Authorization?.ToString(),
            body));
        if (responses.Count == 0)
        {
            throw new InvalidOperationException("No scripted response remains.");
        }

        return new HttpResponseMessage(HttpStatusCode.OK)
        {
            Content = new StringContent(responses.Dequeue(), Encoding.UTF8, "application/json")
        };
    }
}

sealed record CapturedRequest(string Path, string? Authorization, string Body);
