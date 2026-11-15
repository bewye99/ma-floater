using System.Net;
using System.Text;
using System.Text.Json;
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
await CheckTokenRefreshAsync();
await CheckArtworkIsolationAsync();

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
        Ok("""{"success":true,"token":"token-value","user":{"role":"guest"}}"""),
        Ok("""[{"queue_id":"preferred","display_name":"Preferred","state":"idle","available":true,"current_item":{"name":"Idle"}},{"queue_id":"active","display_name":"Active","state":"playing","available":true,"items":3,"shuffle_enabled":true,"repeat_mode":"all","current_item":{"streamdetails":{"stream_metadata":{"image_url":"https://images.example.test/cover.jpg"}},"media_item":{"name":"Current track","artists":[{"name":"Current artist"}]}}}]"""),
        Ok("""[{"player_id":"active","available":true,"supported_features":["volume_set"],"volume_level":42}]"""),
        Ok("""{"result":true}"""),
        Ok("""{"result":true}"""),
        Ok("""{"result":true}"""),
        Ok("""{"result":true}"""),
        Ok("""{"result":true}"""),
        Ok("""{"result":true}"""),
        Ok("""{"result":true}"""));
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
    Check(snapshot.ArtworkUrl == "https://images.example.test/cover.jpg", "Absolute artwork URL is retained.");
    Check(snapshot.HasMultipleItems && snapshot.ShuffleEnabled && snapshot.RepeatMode == "all",
        "Queue control state is extracted.");
    Check(snapshot.SupportsVolume && snapshot.VolumeLevel == 42, "Supported player volume is extracted.");
    Check(handler.Requests.Count >= 2, "Login and queue requests were captured.");
    Check(handler.Requests[0].Path == "/auth/login" && handler.Requests[0].Authorization is null,
        "Login is sent without a bearer header.");
    Check(handler.Requests[1].Path == "/api" && handler.Requests[1].Authorization == "Bearer token-value",
        "Bearer authorization is scoped to the Music Assistant API request.");

    await client.PreviousAsync(snapshot.QueueId);
    await client.PlayPauseAsync(snapshot.QueueId);
    await client.NextAsync(snapshot.QueueId);
    await client.SetShuffleAsync(snapshot.QueueId, false);
    await client.SetRepeatAsync(snapshot.QueueId, "one");
    await client.SetVolumeAsync(snapshot.QueueId, 120);
    Check(HasCommand(handler.Requests, "player_queues/previous", "queue_id", "active"), "Previous targets the selected queue.");
    Check(HasCommand(handler.Requests, "player_queues/play_pause", "queue_id", "active"), "Play/pause targets the selected queue.");
    Check(HasCommand(handler.Requests, "player_queues/next", "queue_id", "active"), "Next targets the selected queue.");
    Check(HasCommand(handler.Requests, "player_queues/shuffle", "queue_id", "active"), "Shuffle targets the selected queue.");
    Check(HasCommand(handler.Requests, "player_queues/repeat", "queue_id", "active"), "Repeat targets the selected queue.");
    Check(HasNumericCommand(handler.Requests, "players/cmd/volume_set", "volume_level", 100),
        "Volume targets the selected player and clamps to 100 percent.");
}

async Task CheckNonGuestRejectionAsync()
{
    var handler = new ScriptedHandler(
        Ok("""{"success":true,"token":"admin-token","user":{"role":"admin"}}"""),
        Ok("""{"result":true}"""));
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

async Task CheckTokenRefreshAsync()
{
    var handler = new ScriptedHandler(
        Ok("""{"success":true,"token":"first-token","user":{"role":"guest"}}"""),
        new ScriptedResponse(HttpStatusCode.Unauthorized, "{}"),
        Ok("""{"success":true,"token":"second-token","user":{"role":"guest"}}"""),
        Ok("[]"),
        Ok("""{"result":true}"""));
    using var httpClient = new HttpClient(handler) { Timeout = TimeSpan.FromSeconds(3) };
    await using var client = new MusicAssistantClient(httpClient, () => "password");
    var settings = new ConnectionSettings
    {
        ServerUrl = "https://music.example.test",
        Username = "guest-user"
    };
    await client.LoginAsync(settings, "password");
    var snapshot = await client.GetNowPlayingAsync(null);
    Check(!snapshot.HasQueue, "Token refresh retry returns the queue result.");
    Check(handler.Requests.Count(request => request.Path == "/auth/login") == 2,
        "A 401 triggers exactly one replacement sign-in.");
    Check(handler.Requests.Any(request => request.Authorization == "Bearer second-token"),
        "The retried API request uses the replacement token.");
}

async Task CheckArtworkIsolationAsync()
{
    var handler = new ArtworkHandler(new byte[] { 1, 2, 3, 4 });
    using var httpClient = new HttpClient(handler) { Timeout = TimeSpan.FromSeconds(3) };
    using var client = new ArtworkClient(httpClient);
    var bytes = await client.DownloadAsync("https://images.example.test/cover.jpg");
    Check(bytes.SequenceEqual(new byte[] { 1, 2, 3, 4 }), "Artwork bytes are returned.");
    Check(handler.Authorization is null, "Artwork request contains no authorization header.");

    var oversizedHandler = new ArtworkHandler([], ArtworkClient.MaximumArtworkBytes + 1L);
    using var oversizedHttpClient = new HttpClient(oversizedHandler) { Timeout = TimeSpan.FromSeconds(3) };
    using var oversizedClient = new ArtworkClient(oversizedHttpClient);
    try
    {
        _ = await oversizedClient.DownloadAsync("https://images.example.test/oversized.jpg");
        Check(false, "Oversized artwork was accepted.");
    }
    catch (InvalidDataException)
    {
        Check(true, "Oversized artwork is rejected.");
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

bool HasCommand(IEnumerable<CapturedRequest> requests, string command, string argumentName, string argumentValue) =>
    requests.Any(request =>
    {
        using var document = JsonDocument.Parse(request.Body);
        var root = document.RootElement;
        return root.TryGetProperty("command", out var commandValue) && commandValue.GetString() == command &&
            root.TryGetProperty("args", out var arguments) &&
            arguments.TryGetProperty(argumentName, out var argument) && argument.GetString() == argumentValue;
    });

bool HasNumericCommand(IEnumerable<CapturedRequest> requests, string command, string argumentName, int argumentValue) =>
    requests.Any(request =>
    {
        using var document = JsonDocument.Parse(request.Body);
        var root = document.RootElement;
        return root.TryGetProperty("command", out var commandValue) && commandValue.GetString() == command &&
            root.TryGetProperty("args", out var arguments) &&
            arguments.TryGetProperty(argumentName, out var argument) && argument.TryGetInt32(out var value) &&
            value == argumentValue;
    });

ScriptedResponse Ok(string body) => new(HttpStatusCode.OK, body);

sealed class ScriptedHandler(params ScriptedResponse[] scriptedResponses) : HttpMessageHandler
{
    private readonly Queue<ScriptedResponse> responses = new(scriptedResponses);

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

        var response = responses.Dequeue();
        return new HttpResponseMessage(response.StatusCode)
        {
            Content = new StringContent(response.Body, Encoding.UTF8, "application/json")
        };
    }
}

sealed record CapturedRequest(string Path, string? Authorization, string Body);

sealed record ScriptedResponse(HttpStatusCode StatusCode, string Body);

sealed class ArtworkHandler(byte[] bytes, long? contentLength = null) : HttpMessageHandler
{
    public string? Authorization { get; private set; }

    protected override Task<HttpResponseMessage> SendAsync(
        HttpRequestMessage request,
        CancellationToken cancellationToken)
    {
        Authorization = request.Headers.Authorization?.ToString();
        var content = new ByteArrayContent(bytes);
        if (contentLength.HasValue)
        {
            content.Headers.ContentLength = contentLength.Value;
        }

        return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = content });
    }
}
