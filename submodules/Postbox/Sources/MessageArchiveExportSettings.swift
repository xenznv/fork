import Foundation
import SwiftSignalKit

/// Backend endpoint and credentials of the archive export (`POST /events`, see
/// PROJECT.md §10). Stored in the account preferences, so the configuration
/// survives a restart and never leaves the account database.
public struct ArchivedMessageExportSettings: Codable, Equatable {
    /// Preferences key; deliberately distinct from the pump checkpoint key
    /// (`ArchivedMessageExportDispatcher.defaultStateKey`).
    public static let defaultKey: ValueBoxKey = ValueBoxKey("message_archive_export_settings")

    /// Absolute URL of the events endpoint, for example `https://host/events`.
    public var endpoint: String
    /// Bearer token sent with every event; a blank token disables the export.
    public var token: String

    public init(endpoint: String, token: String) {
        self.endpoint = endpoint
        self.token = token
    }

    /// `nil` while the configuration is incomplete, so an unconfigured account
    /// reports `channelMissing` instead of requesting a malformed URL.
    public var channel: ArchivedMessageExportHTTPChannel? {
        let endpoint = self.endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        let token = self.token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            return nil
        }
        guard let url = URL(string: endpoint), let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http", let host = url.host, !host.isEmpty else {
            return nil
        }
        return ArchivedMessageExportHTTPChannel(url: url, token: token)
    }
}

public func archivedMessageExportSettings(postbox: Postbox) -> Signal<ArchivedMessageExportSettings?, NoError> {
    return postbox.transaction { transaction -> ArchivedMessageExportSettings? in
        return transaction.getPreferencesEntry(key: ArchivedMessageExportSettings.defaultKey)?.get(ArchivedMessageExportSettings.self)
    }
}

public func updateArchivedMessageExportSettings(transaction: Transaction, settings: ArchivedMessageExportSettings?) {
    transaction.setPreferencesEntry(key: ArchivedMessageExportSettings.defaultKey, value: settings.flatMap { PreferencesEntry($0) })
}
