import Foundation
import Postbox
import SwiftSignalKit

/// Drives the bot queue drain from the account's background operations: once right away,
/// then every `pollInterval` seconds while the app runs. Each drain empties the queue, so
/// the interval bounds how quickly a new event shows up, not whether it is seen — whatever
/// accumulated while the app was closed is collected on the first pass after it opens.
///
/// The token is compiled in (`BotQueueSettings`); without it the reader stays idle instead
/// of issuing unauthenticated requests.
public func managedBotQueueIngest(postbox: Postbox, pollingInterval: Double = BotQueueSettings.pollInterval) -> Signal<Void, NoError> {
    return Signal { _ in
        let ingest = BotQueueIngest(postbox: postbox)
        guard ingest.isConfigured else {
            Logger.shared.log("BotQueue", "No token in BotQueueSettings; the queue reader stays idle")
            return EmptyDisposable
        }

        let queue = Queue(name: "BotQueueIngest")
        let pump: () -> Void = {
            switch ingest.pumpOnce() {
            case let .stored(updates, records):
                Logger.shared.log("BotQueue", "Confirmed \(updates) updates, stored \(records) records")
            case .caughtUp:
                break
            case .notConfigured:
                break
            case let .conflict(description):
                Logger.shared.log("BotQueue", "Another poller holds the queue (409): \(description)")
            case let .failure(description):
                Logger.shared.log("BotQueue", "Drain failed: \(description)")
            }
        }

        // The first pass runs immediately: after a cold start the queue holds everything
        // that happened while the app was closed, and waiting a full interval for it would
        // eat into the 24-hour window the queue keeps.
        queue.async(pump)

        let timer = SwiftSignalKit.Timer(timeout: pollingInterval, repeat: true, completion: pump, queue: queue)
        timer.start()
        return ActionDisposable {
            timer.invalidate()
        }
    }
}
