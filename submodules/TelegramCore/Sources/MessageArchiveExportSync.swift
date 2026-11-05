import Foundation
import Postbox
import SwiftSignalKit

/// Backend configuration of the archive export, as seen by the settings UI: the
/// account preferences stay an implementation detail of the export layer.
public struct MessageArchiveExportConfiguration: Equatable {
    public var endpoint: String
    public var token: String

    public init(endpoint: String, token: String) {
        self.endpoint = endpoint
        self.token = token
    }

    /// Mirrors the validation the pump applies: an unusable configuration just
    /// disables the upload instead of sending broken requests.
    public var isUsable: Bool {
        return ArchivedMessageExportSettings(endpoint: self.endpoint, token: self.token).channel != nil
    }
}

public func messageArchiveExportConfiguration(account: Account) -> Signal<MessageArchiveExportConfiguration?, NoError> {
    return archivedMessageExportSettings(postbox: account.postbox)
    |> map { settings in
        guard let settings = settings else {
            return nil
        }
        return MessageArchiveExportConfiguration(endpoint: settings.endpoint, token: settings.token)
    }
}

/// `nil` disables the upload and removes the stored token.
public func updateMessageArchiveExportConfiguration(account: Account, configuration: MessageArchiveExportConfiguration?) -> Signal<Void, NoError> {
    return account.postbox.transaction { transaction -> Void in
        updateArchivedMessageExportSettings(transaction: transaction, settings: configuration.flatMap { ArchivedMessageExportSettings(endpoint: $0.endpoint, token: $0.token) })
    }
}

/// Drives the archive export pump from the account's background operations: each
/// tick re-reads the backend configuration and drains the archive until the backend
/// stops accepting events. The pump is checkpointed and idempotent, so an account
/// without a configuration only costs a preferences read, and a failed upload is
/// retried on the next tick.
public func managedMessageArchiveExport(postbox: Postbox, pollingInterval: Double = 30.0) -> Signal<Void, NoError> {
    return Signal { _ in
        let queue = Queue(name: "MessageArchiveExport")
        let dispatcher = ArchivedMessageExportDispatcher(postbox: postbox)
        let timer = SwiftSignalKit.Timer(timeout: pollingInterval, repeat: true, completion: {
            guard dispatcher.applyStoredSettings() else {
                return
            }
            switch dispatcher.pumpOnce() {
                case let .uploaded(count):
                    Logger.shared.log("MessageArchiveExport", "Uploaded \(count) events")
                case let .failure(reason):
                    Logger.shared.log("MessageArchiveExport", "Pump failed: \(reason ?? "unknown")")
                case .caughtUp, .channelMissing:
                    break
            }
        }, queue: queue)
        timer.start()
        return ActionDisposable {
            timer.invalidate()
        }
    }
}
