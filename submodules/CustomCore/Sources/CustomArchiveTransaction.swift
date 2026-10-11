import Foundation

public enum CustomImportEventDisposition: Equatable {
    case new
    case duplicate
    case conflict
}

public struct CustomImportAccountPreview: Equatable {
    public let accountPeerId: Int64
    public let newCount: Int
    public let duplicateCount: Int
    public let conflictCount: Int
    public let uncompressedBytes: Int64
}

public struct CustomImportPreview: Equatable {
    public let accounts: [CustomImportAccountPreview]
    public let settingsWillChange: Bool
}

public protocol CustomSettingsSnapshotStore: AnyObject {
    func snapshot(accountPeerId: Int64) throws -> CustomSettingsSnapshot
    func replace(_ snapshot: CustomSettingsSnapshot) throws
}

public protocol CustomRetentionConfigurationStore: AnyObject {
    func configuration(accountPeerId: Int64) throws -> CustomRetentionConfiguration
    func replace(_ configuration: CustomRetentionConfiguration) throws
}

public enum CustomArchiveTransaction {
    public static func classify(
        incoming: CustomCanonicalEvent,
        existingById: [CustomEventId: CustomCanonicalEvent]
    ) -> CustomImportEventDisposition {
        guard let existing = existingById[incoming.eventId] else { return .new }
        return existing == incoming ? .duplicate : .conflict
    }

    public static func apply(
        selectedAccountPeerIds: Set<Int64>,
        availableAccountPeerIds: Set<Int64>,
        incomingEvents: [Int64: [CustomCanonicalEvent]],
        incomingSettings: [Int64: CustomSettingsSnapshot],
        confirmSettingsChanges: Bool,
        eventStore: CustomEventStore,
        settingsStore: CustomSettingsSnapshotStore,
        incomingRetention: [Int64: CustomRetentionConfiguration] = [:],
        retentionStore: CustomRetentionConfigurationStore? = nil
    ) throws {
        guard selectedAccountPeerIds.isSubset(of: availableAccountPeerIds) else {
            let missing = selectedAccountPeerIds.subtracting(availableAccountPeerIds).sorted().first!
            throw CustomArchiveValidationError.unavailableAccount(missing)
        }
        if !incomingSettings.keys.filter(selectedAccountPeerIds.contains).isEmpty && !confirmSettingsChanges {
            throw CustomArchiveValidationError.settingsConfirmationRequired
        }

        var eventRollback: [Int64: [CustomCanonicalEvent]] = [:]
        var settingsRollback: [Int64: CustomSettingsSnapshot] = [:]
        var retentionRollback: [Int64: CustomRetentionConfiguration] = [:]
        do {
            for accountPeerId in selectedAccountPeerIds.sorted() {
                let existing = try eventStore.events(accountPeerId: accountPeerId, chatPeerId: nil)
                eventRollback[accountPeerId] = existing
                settingsRollback[accountPeerId] = try settingsStore.snapshot(accountPeerId: accountPeerId)
                if incomingRetention[accountPeerId] != nil, let retentionStore {
                    retentionRollback[accountPeerId] = try retentionStore.configuration(accountPeerId: accountPeerId)
                }
                let existingById = Dictionary(uniqueKeysWithValues: existing.map { ($0.eventId, $0) })
                var merged = existing
                var conflicts = 0
                for event in incomingEvents[accountPeerId] ?? [] {
                    guard event.accountPeerId == accountPeerId else {
                        throw CustomArchiveValidationError.unavailableAccount(event.accountPeerId)
                    }
                    switch classify(incoming: event, existingById: existingById) {
                    case .new:
                        merged.append(event)
                    case .duplicate:
                        break
                    case .conflict:
                        conflicts += 1
                    }
                }
                guard conflicts == 0 else {
                    throw CustomArchiveValidationError.conflictsPresent(conflicts)
                }
                try eventStore.replaceAtomically(accountPeerId: accountPeerId, events: merged)
                if let settings = incomingSettings[accountPeerId] {
                    guard settings.accountPeerId == accountPeerId else {
                        throw CustomArchiveValidationError.unavailableAccount(settings.accountPeerId)
                    }
                    try settingsStore.replace(settings)
                }
                if let retention = incomingRetention[accountPeerId], let retentionStore {
                    guard retention.accountPeerId == accountPeerId else {
                        throw CustomArchiveValidationError.unavailableAccount(retention.accountPeerId)
                    }
                    try retentionStore.replace(retention)
                }
            }
        } catch {
            // Rollback is best-effort for every already touched exact account;
            // original error remains the reported failure.
            for accountPeerId in eventRollback.keys.sorted() {
                if let events = eventRollback[accountPeerId] {
                    try? eventStore.replaceAtomically(accountPeerId: accountPeerId, events: events)
                }
                if let settings = settingsRollback[accountPeerId] {
                    try? settingsStore.replace(settings)
                }
                if let retention = retentionRollback[accountPeerId], let retentionStore {
                    try? retentionStore.replace(retention)
                }
            }
            throw error
        }
    }
}
