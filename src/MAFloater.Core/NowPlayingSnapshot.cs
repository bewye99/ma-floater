namespace MAFloater.Core;

public sealed record NowPlayingSnapshot(
    bool HasQueue,
    string QueueId,
    string QueueName,
    string State,
    string Title,
    string Artist)
{
    public static NowPlayingSnapshot NothingQueued { get; } =
        new(false, string.Empty, string.Empty, "idle", "Nothing queued", "Start playback in Music Assistant");
}
