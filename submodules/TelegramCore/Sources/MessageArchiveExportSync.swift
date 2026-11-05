import Foundation
import Postbox
import SwiftSignalKit

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
