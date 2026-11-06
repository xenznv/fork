import Foundation

/// Configuration of the bot queue reader, compiled into the fork: stock Telegram has no
/// screen for it and the app does not grow custom UI (PROJECT.md §12). Changing any of
/// these values means editing this file and shipping a build.
public enum BotQueueSettings {
    /// Bot API origin. Everything below is appended to it.
    public static let apiBase = "https://api.telegram.org"

    /// Token of the business bot whose update queue this device drains. Left empty in the
    /// repository on purpose: paste the token into a local build only and never commit it
    /// — the value is a full-access credential for every chat the business connection
    /// covers. While it is empty the reader reports `notConfigured` and touches nothing.
    public static let token = ""

    /// Optional `socks5://host:port` / `http://host:port` proxy for the Bot API endpoint,
    /// for networks where `api.telegram.org` is not reachable directly. Empty means a
    /// direct connection, which is what the Bot API normally allows.
    public static let proxy = ""

    /// Kinds of updates to ask for. Business events only: the queue stays free of the
    /// bot's ordinary chat traffic.
    public static let allowedUpdates = BotQueueUpdateParser.allowedUpdates

    /// Bot API maximum per call.
    public static let batchLimit = 100

    /// Long-poll window in seconds. The connection is held open this long while the app is
    /// in the foreground, so a new message arrives immediately.
    public static let longPollTimeout = 25

    /// How often the drain runs while the account is open, in seconds. Each run also
    /// drains whatever accumulated while the app was closed, so this only bounds the delay
    /// of new events, not whether they are seen.
    public static let pollInterval = 600.0

    /// Key of the persisted queue position (`update_id + 1`).
    public static let offsetKey = ValueBoxKey("bot_queue_offset")

    public static var isConfigured: Bool {
        return !self.token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
