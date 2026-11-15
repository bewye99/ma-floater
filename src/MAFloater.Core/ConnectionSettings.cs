using System.Text.Json.Serialization;

namespace MAFloater.Core;

public sealed class ConnectionSettings
{
    [JsonPropertyName("server_url")]
    public string ServerUrl { get; init; } = string.Empty;

    [JsonPropertyName("username")]
    public string Username { get; init; } = string.Empty;

    [JsonPropertyName("preferred_queue")]
    public string PreferredQueue { get; init; } = string.Empty;
}
