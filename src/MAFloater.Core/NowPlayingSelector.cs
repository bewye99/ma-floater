using System.Text.Json;

namespace MAFloater.Core;

public static class NowPlayingSelector
{
    public static NowPlayingSnapshot Select(
        JsonElement queues,
        string? currentQueueId,
        string? preferredQueue)
    {
        if (queues.ValueKind != JsonValueKind.Array)
        {
            return NowPlayingSnapshot.NothingQueued;
        }

        var withItems = queues.EnumerateArray()
            .Where(queue => GetBoolean(queue, "available") && HasCurrentItem(queue))
            .Select(queue => queue.Clone())
            .ToList();
        if (withItems.Count == 0)
        {
            return NowPlayingSnapshot.NothingQueued;
        }

        var playing = withItems.Where(queue =>
            string.Equals(GetString(queue, "state"), "playing", StringComparison.OrdinalIgnoreCase)).ToList();
        var selected = FindById(playing, currentQueueId)
            ?? FindByName(playing, preferredQueue)
            ?? playing.Cast<JsonElement?>().FirstOrDefault()
            ?? FindById(withItems, currentQueueId)
            ?? FindByName(withItems, preferredQueue);
        if (selected is null)
        {
            return NowPlayingSnapshot.NothingQueued;
        }

        var queue = selected.Value;
        var item = queue.GetProperty("current_item");
        return new NowPlayingSnapshot(
            true,
            GetString(queue, "queue_id"),
            GetString(queue, "display_name"),
            GetString(queue, "state"),
            GetTitle(item),
            GetArtist(item));
    }

    private static JsonElement? FindById(IEnumerable<JsonElement> queues, string? queueId) =>
        string.IsNullOrWhiteSpace(queueId)
            ? null
            : queues.Cast<JsonElement?>().FirstOrDefault(queue =>
                string.Equals(GetString(queue!.Value, "queue_id"), queueId, StringComparison.Ordinal));

    private static JsonElement? FindByName(IEnumerable<JsonElement> queues, string? queueName) =>
        string.IsNullOrWhiteSpace(queueName)
            ? null
            : queues.Cast<JsonElement?>().FirstOrDefault(queue =>
                string.Equals(GetString(queue!.Value, "display_name"), queueName, StringComparison.Ordinal));

    private static bool HasCurrentItem(JsonElement queue) =>
        queue.TryGetProperty("current_item", out var item) && item.ValueKind is not JsonValueKind.Null;

    private static bool GetBoolean(JsonElement element, string name) =>
        element.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.True;

    private static string GetString(JsonElement element, string name) =>
        element.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.String
            ? value.GetString() ?? string.Empty
            : string.Empty;

    private static string GetTitle(JsonElement item)
    {
        var streamTitle = GetNestedString(item, "streamdetails", "stream_metadata", "title");
        if (!string.IsNullOrWhiteSpace(streamTitle))
        {
            return streamTitle;
        }

        var mediaName = GetNestedString(item, "media_item", "name");
        return !string.IsNullOrWhiteSpace(mediaName) ? mediaName : GetString(item, "name") is { Length: > 0 } name
            ? name
            : "Unknown track";
    }

    private static string GetArtist(JsonElement item)
    {
        var streamArtist = GetNestedString(item, "streamdetails", "stream_metadata", "artist");
        if (!string.IsNullOrWhiteSpace(streamArtist))
        {
            return streamArtist;
        }

        if (item.TryGetProperty("media_item", out var mediaItem))
        {
            if (mediaItem.TryGetProperty("artists", out var artists) && artists.ValueKind == JsonValueKind.Array)
            {
                var names = artists.EnumerateArray()
                    .Select(artist => GetString(artist, "name"))
                    .Where(name => !string.IsNullOrWhiteSpace(name));
                var combined = string.Join(", ", names);
                if (!string.IsNullOrWhiteSpace(combined))
                {
                    return combined;
                }
            }

            var publisher = GetString(mediaItem, "publisher");
            if (!string.IsNullOrWhiteSpace(publisher))
            {
                return publisher;
            }
        }

        return "Unknown artist";
    }

    private static string GetNestedString(JsonElement element, params string[] path)
    {
        var current = element;
        foreach (var part in path)
        {
            if (!current.TryGetProperty(part, out current))
            {
                return string.Empty;
            }
        }

        return current.ValueKind == JsonValueKind.String ? current.GetString() ?? string.Empty : string.Empty;
    }
}
