using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;

namespace MAFloater.Core;

public sealed class MusicAssistantClient : IAsyncDisposable
{
    private readonly HttpClient httpClient;
    private readonly bool ownsClient;
    private Uri? serverUri;
    private string? accessToken;
    private string? currentQueueId;

    public MusicAssistantClient(HttpClient? httpClient = null)
    {
        ownsClient = httpClient is null;
        this.httpClient = httpClient ?? new HttpClient { Timeout = TimeSpan.FromSeconds(3) };
        if (!this.httpClient.DefaultRequestHeaders.UserAgent.Any())
        {
            this.httpClient.DefaultRequestHeaders.UserAgent.ParseAdd("MAFloater/0.2.0");
        }
    }

    public bool IsConnected => serverUri is not null && !string.IsNullOrWhiteSpace(accessToken);

    public async Task LoginAsync(
        ConnectionSettings settings,
        string password,
        CancellationToken cancellationToken = default)
    {
        if (!ConnectionSettingsValidator.TryValidate(settings, out var error))
        {
            throw new ArgumentException(error, nameof(settings));
        }

        if (string.IsNullOrWhiteSpace(password))
        {
            throw new ArgumentException("A password is required.", nameof(password));
        }

        serverUri = new Uri(settings.ServerUrl.TrimEnd('/') + "/", UriKind.Absolute);
        var payload = JsonSerializer.Serialize(new
        {
            provider_id = "builtin",
            credentials = new { username = settings.Username, password },
            device_name = "MA Floater for Windows"
        });
        using var content = new StringContent(payload, Encoding.UTF8, "application/json");
        using var response = await httpClient.PostAsync(
            new Uri(serverUri, "auth/login"), content, cancellationToken).ConfigureAwait(false);
        if (!response.IsSuccessStatusCode)
        {
            throw new InvalidOperationException($"Music Assistant sign-in failed (HTTP {(int)response.StatusCode}).");
        }

        using var document = JsonDocument.Parse(await response.Content.ReadAsStringAsync(cancellationToken).ConfigureAwait(false));
        var root = document.RootElement;
        var success = root.TryGetProperty("success", out var successElement) && successElement.ValueKind == JsonValueKind.True;
        var token = GetString(root, "token");
        if (string.IsNullOrWhiteSpace(token))
        {
            token = GetString(root, "access_token");
        }

        if (!success || string.IsNullOrWhiteSpace(token))
        {
            var detail = GetString(root, "error");
            throw new InvalidOperationException(string.IsNullOrWhiteSpace(detail)
                ? "Music Assistant rejected the sign-in."
                : detail);
        }

        accessToken = token;
        var role = root.TryGetProperty("user", out var user) ? GetString(user, "role") : string.Empty;
        if (!string.Equals(role, "guest", StringComparison.OrdinalIgnoreCase))
        {
            await LogoutAsync(cancellationToken).ConfigureAwait(false);
            throw new InvalidOperationException("The configured account is not a Guest account; refusing broader access.");
        }
    }

    public async Task<NowPlayingSnapshot> GetNowPlayingAsync(
        string? preferredQueue,
        CancellationToken cancellationToken = default)
    {
        var queues = await InvokeCommandAsync("player_queues/all", new { }, cancellationToken).ConfigureAwait(false);
        var snapshot = NowPlayingSelector.Select(queues, currentQueueId, preferredQueue);
        currentQueueId = snapshot.HasQueue ? snapshot.QueueId : null;
        return snapshot;
    }

    public async Task LogoutAsync(CancellationToken cancellationToken = default)
    {
        if (!IsConnected)
        {
            return;
        }

        try
        {
            await InvokeCommandAsync("auth/logout", new { }, cancellationToken).ConfigureAwait(false);
        }
        catch
        {
        }
        finally
        {
            accessToken = null;
            currentQueueId = null;
        }
    }

    private async Task<JsonElement> InvokeCommandAsync(
        string command,
        object arguments,
        CancellationToken cancellationToken)
    {
        if (!IsConnected || serverUri is null)
        {
            throw new InvalidOperationException("Music Assistant is not connected.");
        }

        var payload = JsonSerializer.Serialize(new
        {
            command,
            message_id = Guid.NewGuid().ToString("N"),
            args = arguments
        });
        using var request = new HttpRequestMessage(HttpMethod.Post, new Uri(serverUri, "api"))
        {
            Content = new StringContent(payload, Encoding.UTF8, "application/json")
        };
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", accessToken);
        using var response = await httpClient.SendAsync(request, cancellationToken).ConfigureAwait(false);
        var body = await response.Content.ReadAsStringAsync(cancellationToken).ConfigureAwait(false);
        if (!response.IsSuccessStatusCode)
        {
            throw new InvalidOperationException($"Music Assistant request failed (HTTP {(int)response.StatusCode}).");
        }

        using var document = JsonDocument.Parse(body);
        var root = document.RootElement;
        if (root.ValueKind == JsonValueKind.Object && root.TryGetProperty("error_code", out _))
        {
            var detail = GetString(root, "details");
            throw new InvalidOperationException(string.IsNullOrWhiteSpace(detail)
                ? "Music Assistant rejected the request."
                : detail);
        }

        return root.ValueKind == JsonValueKind.Object && root.TryGetProperty("result", out var result)
            ? result.Clone()
            : root.Clone();
    }

    private static string GetString(JsonElement element, string propertyName) =>
        element.TryGetProperty(propertyName, out var value) && value.ValueKind == JsonValueKind.String
            ? value.GetString() ?? string.Empty
            : string.Empty;

    public async ValueTask DisposeAsync()
    {
        await LogoutAsync().ConfigureAwait(false);
        if (ownsClient)
        {
            httpClient.Dispose();
        }
    }
}
