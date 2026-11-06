import Foundation
import SwiftSignalKit

/// Persisted queue position plus what the last successful drain delivered, so a build in
/// the field can be diagnosed from its log alone.
public struct BotQueueSyncState: Codable, Equatable {
    /// `update_id + 1` of the last confirmed page: the offset the next call resumes from.
    public var offset: Int64?
    /// Number of updates (not records) confirmed so far.
    public var confirmedUpdates: Int
    /// Unix time of the last confirmed page.
    public var lastSyncTime: Int32

    public init(offset: Int64? = nil, confirmedUpdates: Int = 0, lastSyncTime: Int32 = 0) {
        self.offset = offset
        self.confirmedUpdates = confirmedUpdates
        self.lastSyncTime = lastSyncTime
    }
}

public enum BotQueuePumpOutcome: Equatable {
    /// `records` records were stored and `updates` queue positions confirmed.
    case stored(updates: Int, records: Int)
    /// The queue was empty: everything delivered so far is confirmed.
    case caughtUp
    /// No token is compiled in, so nothing was requested.
    case notConfigured
    /// Another process polls the same bot; the drain stopped instead of fighting it.
    case conflict(String)
    /// The drain stopped on an error; whatever was already stored stays confirmed.
    case failure(String)
}

/// Drains the bot's update queue into Postbox: one `getUpdates` page at a time, each page
/// written together with the new queue position in a single transaction. The position only
/// advances with the records it belongs to, so an interrupted drain replays a page instead
/// of skipping it, and a replayed page overwrites the same (chat, message, kind) records
/// instead of duplicating them.
public final class BotQueueIngest {
    public let postbox: Postbox
    private let poller: BotQueuePoller?
    /// Bounded wait for a Postbox transaction; the drain runs on background queues.
    private let syncTimeout: Double

    public init(postbox: Postbox, token: String = BotQueueSettings.token, apiBase: String = BotQueueSettings.apiBase, proxy: String = BotQueueSettings.proxy, syncTimeout: Double = 30.0) {
        self.postbox = postbox
        self.syncTimeout = syncTimeout
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, let url = URL(string: apiBase), url.host != nil {
            self.poller = BotQueuePoller(apiBase: apiBase, token: trimmed, proxy: proxy)
        } else {
            self.poller = nil
        }
    }

    public var isConfigured: Bool {
        return self.poller != nil
    }

    /// Drains the queue until it is empty or a page fails. Safe to call repeatedly.
    public func pumpOnce() -> BotQueuePumpOutcome {
        guard let poller = self.poller else {
            return .notConfigured
        }

        var totalUpdates = 0
        var totalRecords = 0
        while true {
            guard let state = self.readState() else {
                return .failure("could not read the queue position")
            }

            let outcome = poller.fetch(
                offset: state.offset,
                limit: BotQueueSettings.batchLimit,
                timeout: BotQueueSettings.longPollTimeout,
                allowedUpdates: BotQueueSettings.allowedUpdates
            )

            switch outcome {
            case .conflict(let description):
                return .conflict(description)
            case .failure(let description, _):
                return totalUpdates > 0 ? .stored(updates: totalUpdates, records: totalRecords) : .failure(description)
            case .updates(let rawUpdates):
                if rawUpdates.isEmpty {
                    return totalUpdates > 0 ? .stored(updates: totalUpdates, records: totalRecords) : .caughtUp
                }

                var updates: [BotQueuePulledUpdate] = []
                var lastUpdateId: Int64 = 0
                for rawUpdate in rawUpdates {
                    guard let updateId = (rawUpdate["update_id"] as? NSNumber)?.int64Value else {
                        // Without an id the page cannot be confirmed; stop before it so the
                        // same page is requested again rather than skipped.
                        return .failure("update without an id")
                    }
                    lastUpdateId = max(lastUpdateId, updateId)
                    if let parsed = BotQueueUpdateParser.parse(rawUpdate) {
                        updates.append(parsed)
                    }
                }

                guard let storedRecords = self.apply(updates: updates, state: state, nextOffset: lastUpdateId + 1) else {
                    return totalUpdates > 0 ? .stored(updates: totalUpdates, records: totalRecords) : .failure("could not store the page")
                }

                totalUpdates += rawUpdates.count
                totalRecords += storedRecords

                // A short page is the end of the queue: no point in another long poll that
                // would just sit there for `longPollTimeout` seconds.
                if rawUpdates.count < BotQueueSettings.batchLimit {
                    return .stored(updates: totalUpdates, records: totalRecords)
                }
            }
        }
    }

    /// Stores one page and advances the position in the same transaction.
    private func apply(updates: [BotQueuePulledUpdate], state: BotQueueSyncState, nextOffset: Int64) -> Int? {
        let storedAt = Int32(Date().timeIntervalSince1970)
        return self.transaction { transaction -> Int in
            var records: [BotQueueRecord] = []
            for update in updates {
                for operation in update.operations {
                    switch operation {
                    case let .message(chatId, messageId, date):
                        records.append(BotQueueRecord(chatId: chatId, messageId: messageId, kind: .message, eventDate: date, storedAt: storedAt, body: update.body))
                    case let .edit(chatId, messageId, _, editDate):
                        records.append(BotQueueRecord(chatId: chatId, messageId: messageId, kind: .edit, eventDate: editDate, storedAt: storedAt, body: update.body))
                    case let .deletion(chatId, messageIds):
                        for messageId in messageIds {
                            records.append(BotQueueRecord(chatId: chatId, messageId: messageId, kind: .deletion, eventDate: storedAt, storedAt: storedAt, body: update.body))
                        }
                    }
                }
            }

            transaction.storeBotQueueRecords(records)

            var next = state
            next.offset = nextOffset
            next.confirmedUpdates += 1
            next.lastSyncTime = storedAt
            transaction.setPreferencesEntry(key: BotQueueSettings.offsetKey, value: PreferencesEntry(next))

            return records.count
        }
    }

    public func readState() -> BotQueueSyncState? {
        return self.transaction { transaction -> BotQueueSyncState in
            guard let entry = transaction.getPreferencesEntry(key: BotQueueSettings.offsetKey) else {
                return BotQueueSyncState()
            }
            return entry.get(BotQueueSyncState.self) ?? BotQueueSyncState()
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
}
