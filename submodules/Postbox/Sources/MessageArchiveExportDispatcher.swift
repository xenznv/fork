import Foundation
import SwiftSignalKit

/// Result of a single delivery attempt to the export backend.
public enum ArchivedMessageExportChannelResult: Equatable {
    /// The backend durably stored the event (a repeated delivery of the same
    /// `eventId` counts as accepted too).
    case accepted
    /// The event was not stored; `reason` is a transport/backend detail for logging.
    case failure(String?)
}

/// The transport feeding archive events to the export backend (`POST /events`, see
/// PROJECT.md §10). Kept a protocol so the upload loop can be tested against a stub
/// and the real networking can be added separately.
public protocol ArchivedMessageExportChannel: AnyObject {
    func send(_ event: ArchivedMessageExportEvent, _ completion: @escaping (ArchivedMessageExportChannelResult) -> Void)
}

/// Export progress checkpoint: the position after the last event the backend
/// confirmed. Persisted in account preferences, so a restart continues from there.
/// Duplicated events are tolerated by the backend, which stores them under a stable
/// `eventId`, so a checkpoint that lags behind the backend is always safe to replay.
public struct ArchivedMessageExportSyncState: Codable, Equatable {
    public var sentCursor: ArchivedMessageExportCursor?

    public init(sentCursor: ArchivedMessageExportCursor?) {
        self.sentCursor = sentCursor
    }
}

public enum ArchivedMessageExportPumpOutcome: Equatable {
    /// `count` events were confirmed during this pump and the archive has more.
    case uploaded(Int)
    /// The end of the archive was reached (possibly after uploading some events).
    case caughtUp
    /// A delivery error stopped the pump; already-confirmed events stay in the
    /// checkpoint and the failing event will be retried on the next pump.
    case failure(String?)
    /// The dispatcher has no backend channel configured.
    case channelMissing
}

/// Uploads archived message captures to the export backend one event at a time,
/// advancing a persisted checkpoint only after the backend confirms an event, so
/// loading stops at the first failure and no event is skipped.
public final class ArchivedMessageExportDispatcher {
    public static let defaultStateKey: ValueBoxKey = ValueBoxKey("message_archive_export")

    public let postbox: Postbox
    public let stateKey: ValueBoxKey
    /// The backend channel; replacing it between pumps is fine, the pump runs to
    /// completion before returning.
    public var channel: ArchivedMessageExportChannel?
    /// Blocking waits below are bounded: the pump is meant to run on background
    /// queues, not on the main thread or on any of the Postbox queues.
    let syncTimeout: Double

    public init(postbox: Postbox, stateKey: ValueBoxKey = ArchivedMessageExportDispatcher.defaultStateKey, channel: ArchivedMessageExportChannel? = nil, syncTimeout: Double = 30.0) {
        self.postbox = postbox
        self.stateKey = stateKey
        self.channel = channel
        self.syncTimeout = syncTimeout
    }

    /// Re-reads the backend configuration from the account preferences and applies
    /// it as the channel. Returns `false` when the configuration is missing or
    /// incomplete, in which case a pump reports `channelMissing`.
    @discardableResult
    public func applyStoredSettings() -> Bool {
        let stored: ArchivedMessageExportSettings?? = self.transaction { transaction -> ArchivedMessageExportSettings? in
            return transaction.getPreferencesEntry(key: ArchivedMessageExportSettings.defaultKey)?.get(ArchivedMessageExportSettings.self)
        }
        self.channel = (stored ?? nil)?.channel
        return self.channel != nil
    }

    /// Reads whether the event stream is empty without updating anything.
    @discardableResult
    public func pumpOnce(maxBatchSize: Int = 100) -> ArchivedMessageExportPumpOutcome {
        guard let channel = self.channel else {
            return .channelMissing
        }
        var checkpoint = self.readSyncState()
        var confirmed = 0
        while true {
            guard let batch = self.readBatch(after: checkpoint.sentCursor, limit: maxBatchSize) else {
                self.writeSyncState(checkpoint)
                return .failure("export read failed")
            }
            if batch.events.isEmpty {
                if confirmed > 0 {
                    return .uploaded(confirmed)
                }
                return .caughtUp
            }
            for event in batch.events {
                switch self.send(event, via: channel) {
                case .accepted:
                    confirmed += 1
                    checkpoint.sentCursor = event.cursor
                case .failure(let reason):
                    self.writeSyncState(checkpoint)
                    return .failure(reason ?? "export channel failure")
                }
            }
            self.writeSyncState(checkpoint)
            if batch.events.count < maxBatchSize {
                if confirmed > 0 {
                    return .uploaded(confirmed)
                }
                return .caughtUp
            }
        }
    }

    private func transaction<T>(_ f: @escaping (Transaction) -> T) -> T? {
        let semaphore = DispatchSemaphore(value: 0)
        var result: T?
        let signal = self.postbox.transaction(f)
        let disposable = signal.start(next: { value in
            result = value
            semaphore.signal()
        })
        if semaphore.wait(timeout: .now() + self.syncTimeout) == .timedOut {
            disposable.dispose()
            return nil
        }
        disposable.dispose()
        return result
    }

    private func readSyncState() -> ArchivedMessageExportSyncState {
        let state = self.transaction { transaction -> ArchivedMessageExportSyncState in
            guard let entry = transaction.getPreferencesEntry(key: self.stateKey) else {
                return ArchivedMessageExportSyncState(sentCursor: nil)
            }
            return entry.get(ArchivedMessageExportSyncState.self) ?? ArchivedMessageExportSyncState(sentCursor: nil)
        }
        return state ?? ArchivedMessageExportSyncState(sentCursor: nil)
    }

    private func writeSyncState(_ state: ArchivedMessageExportSyncState) {
        let _ = self.transaction { transaction in
            transaction.setPreferencesEntry(key: self.stateKey, value: PreferencesEntry(state))
        }
    }

    private func readBatch(after cursor: ArchivedMessageExportCursor?, limit: Int) -> ArchivedMessageExportBatch? {
        return self.transaction { transaction -> ArchivedMessageExportBatch in
            transaction.archivedMessageExportBatch(after: cursor, limit: limit)
        }
    }

    private func send(_ event: ArchivedMessageExportEvent, via channel: ArchivedMessageExportChannel) -> ArchivedMessageExportChannelResult {
        let semaphore = DispatchSemaphore(value: 0)
        var result: ArchivedMessageExportChannelResult = .failure("channel did not respond")
        channel.send(event, { value in
            result = value
            semaphore.signal()
        })
        if semaphore.wait(timeout: .now() + self.syncTimeout) == .timedOut {
            return .failure("export channel timed out")
        }
        return result
    }
}
