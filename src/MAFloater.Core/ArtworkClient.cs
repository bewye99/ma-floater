namespace MAFloater.Core;

public sealed class ArtworkClient : IDisposable
{
    public const int MaximumArtworkBytes = 5 * 1024 * 1024;

    private readonly HttpClient httpClient;
    private readonly bool ownsClient;

    public ArtworkClient(HttpClient? httpClient = null)
    {
        ownsClient = httpClient is null;
        this.httpClient = httpClient ?? new HttpClient { Timeout = TimeSpan.FromSeconds(3) };
        if (!this.httpClient.DefaultRequestHeaders.UserAgent.Any())
        {
            this.httpClient.DefaultRequestHeaders.UserAgent.ParseAdd("MAFloater/0.2.0");
        }
    }

    public async Task<byte[]> DownloadAsync(string url, CancellationToken cancellationToken = default)
    {
        if (!Uri.TryCreate(url, UriKind.Absolute, out var uri) ||
            (uri.Scheme != Uri.UriSchemeHttp && uri.Scheme != Uri.UriSchemeHttps))
        {
            throw new ArgumentException("Artwork URL must use HTTP or HTTPS.", nameof(url));
        }

        if (httpClient.DefaultRequestHeaders.Authorization is not null)
        {
            throw new InvalidOperationException("Artwork requests must not contain an authorization header.");
        }

        using var request = new HttpRequestMessage(HttpMethod.Get, uri);
        request.Headers.Authorization = null;
        using var response = await httpClient.SendAsync(
            request, HttpCompletionOption.ResponseHeadersRead, cancellationToken).ConfigureAwait(false);
        response.EnsureSuccessStatusCode();
        if (response.Content.Headers.ContentLength > MaximumArtworkBytes)
        {
            throw new InvalidDataException("Artwork exceeds the five-megabyte limit.");
        }

        await using var source = await response.Content.ReadAsStreamAsync(cancellationToken).ConfigureAwait(false);
        using var destination = new MemoryStream();
        var buffer = new byte[81920];
        while (true)
        {
            var read = await source.ReadAsync(buffer, cancellationToken).ConfigureAwait(false);
            if (read == 0)
            {
                break;
            }

            if (destination.Length + read > MaximumArtworkBytes)
            {
                throw new InvalidDataException("Artwork exceeds the five-megabyte limit.");
            }

            destination.Write(buffer, 0, read);
        }

        return destination.ToArray();
    }

    public void Dispose()
    {
        if (ownsClient)
        {
            httpClient.Dispose();
        }
    }
}
