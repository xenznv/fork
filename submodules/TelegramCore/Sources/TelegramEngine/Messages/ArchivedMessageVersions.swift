import Foundation
import SwiftSignalKit
import Postbox

public enum EngineMessageArchiveKind {
    case deleted
    case editedVersion
}

/// A locally archived version of a message: either the content that an edit replaced, or the
/// content a message still had when it was deleted on this device.
public struct EngineMessageArchivedVersion {
    public let message: EngineMessage
    public let kind: EngineMessageArchiveKind
    /// Unix time of the local capture, not the time the message was sent.
    public let captureTimestamp: Int32
    /// Per-message version number, starting at 1 and growing with every capture.
    public let captureIndex: Int32

    init(version: ArchivedMessageVersion) {
        self.message = EngineMessage(version.message)
        switch version.kind {
        case .deleted:
            self.kind = .deleted
        case .editedVersion:
            self.kind = .editedVersion
        }
        self.captureTimestamp = version.captureTimestamp
        self.captureIndex = version.captureIndex
    }
}

public extension TelegramEngine.Messages {
    /// Every archived version of the message, oldest first. Empty when nothing was ever captured.
    func archivedMessageVersions(id: MessageId) -> Signal<[EngineMessageArchivedVersion], NoError> {
        return self.account.postbox.transaction { transaction -> [EngineMessageArchivedVersion] in
            return transaction.archivedMessageVersions(id).map(EngineMessageArchivedVersion.init(version:))
        }
    }

    /// Number of archived versions, for deciding whether showing them is worth an entry in a menu.
    func archivedMessageVersionCount(id: MessageId) -> Signal<Int, NoError> {
        return self.account.postbox.transaction { transaction -> Int in
            return transaction.archivedMessageVersionCount(id)
        }
    }

    /// The newest captured snapshot of every deleted message of one chat, newest first.
    /// Re-emits when the chat's message history changes (the deleted-messages stretch of
    /// the history view already updates on any removal), and reads the archive table
    /// fresh on each emission.
    func archivedDeletedMessageSnapshots(peerId: EnginePeer.Id) -> Signal<[EngineMessageArchivedVersion], NoError> {
        let deletedMessagesKey = PostboxViewKey.deletedMessages(peerId: peerId)
        return self.account.postbox.combinedView(keys: [deletedMessagesKey])
        |> mapToSignal { _ -> Signal<[EngineMessageArchivedVersion], NoError> in
            return self.account.postbox.transaction { transaction -> [EngineMessageArchivedVersion] in
                return transaction.archivedDeletedMessageVersions(peerId: peerId).filter { $0.kind == .deleted }.map(EngineMessageArchivedVersion.init(version:))
            }
        }
    }
}
