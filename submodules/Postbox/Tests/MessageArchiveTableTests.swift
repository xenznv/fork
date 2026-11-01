import Foundation
import XCTest
@testable import Postbox

/// Captures taken by the archive table must decode back to the exact message content
/// that was stored before the message was removed or edited.
final class MessageArchiveTableTests: XCTestCase {
    private var fixture: MessageHistoryTableFixture!

    private let peer = MessageHistoryTableFixture.peerId(310)
    private let namespace = MessageHistoryTableFixture.messageNamespace

    override func setUp() {
        super.setUp()
        self.fixture = MessageHistoryTableFixture(name: "MessageArchiveTableTests")
    }

    override func tearDown() {
        self.fixture.close()
        self.fixture = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func id(_ value: Int32) -> MessageId {
        return MessageId(peerId: self.peer, namespace: self.namespace, id: value)
    }

    private func store(_ messageId: MessageId, timestamp: Int32, text: String, flags: StoreMessageFlags = [.Incoming], media: [Media] = []) {
        let _ = self.fixture.addMessages([MessageHistoryTableFixture.storeMessage(id: messageId, timestamp: timestamp, text: text, media: media, flags: flags)])
    }

    private func replaceContent(_ messageId: MessageId, timestamp: Int32, text: String, flags: StoreMessageFlags = [.Incoming]) {
        let _ = self.fixture.updateMessage(messageId, message: MessageHistoryTableFixture.storeMessage(id: messageId, timestamp: timestamp, text: text, flags: flags))
    }

    /// Captures the current stored content as an edit version, mirroring what the
    /// production update path does before applying the new content.
    private func captureEditVersion(_ messageId: MessageId) {
        self.fixture.queue.sync {
            if let (index, value) = self.fixture.messageHistoryTable.archivedEntryValue(messageId) {
                self.fixture.messageArchiveTable.addCapture(index: index, rawValue: value, kind: .editedVersion, skipIfSameAsLatest: true)
            }
        }
    }

    private func remove(_ messageIds: [MessageId]) {
        let _ = self.fixture.removeMessages(messageIds)
    }

    private func records(_ messageId: MessageId) -> [ArchivedMessageRecord] {
        var result: [ArchivedMessageRecord] = []
        self.fixture.queue.sync {
            result = self.fixture.messageArchiveTable.records(id: messageId)
        }
        return result
    }

    private func perMessageRecordCount(_ messageId: MessageId) -> Int {
        var count = 0
        self.fixture.queue.sync {
            count = self.fixture.messageArchiveTable.recordCount(id: messageId)
        }
        return count
    }

    private func storedRecordCount() -> Int {
        var count = 0
        self.fixture.queue.sync {
            count = self.fixture.messageArchiveTable.recordCount()
        }
        return count
    }

    private func latestSnapshots(for peer: PeerId, limit: Int = 256) -> [ArchivedMessageRecord] {
        var result: [ArchivedMessageRecord] = []
        self.fixture.queue.sync {
            result = self.fixture.messageArchiveTable.latestSnapshotsForPeer(peerId: peer, limit: limit)
        }
        return result
    }

    // MARK: - Deleted snapshots

    func testDeletingMessageStoresSnapshotThatDecodesBack() {
        let messageId = self.id(11)
        self.store(messageId, timestamp: 1200, text: "victim")

        self.remove([messageId])

        let records = self.records(messageId)
        XCTAssertEqual(records.count, 1)
        if let record = records.first {
            XCTAssertEqual(record.id, messageId)
            XCTAssertEqual(record.captureIndex, 1)
            if record.kind != .deleted {
                XCTFail("unexpected kind \(record.kind)")
            }
            XCTAssertEqual(record.message.text, "victim")
            XCTAssertEqual(record.message.timestamp, 1200)
            XCTAssertTrue(record.message.flags.contains(.Incoming))
            XCTAssertEqual(record.message.globalTags, [])
        }
        XCTAssertEqual(self.storedRecordCount(), 1)
    }

    func testDeletingMessageKeepsEmbeddedMediaBytes() {
        let messageId = self.id(12)
        let mediaId = MediaId(namespace: 0, id: 101)
        self.store(messageId, timestamp: 1300, text: "with media", media: [FixtureMedia(id: mediaId, label: "shared")])

        self.remove([messageId])

        let records = self.records(messageId)
        XCTAssertEqual(records.count, 1)
        if let record = records.first {
            var media: [Media] = []
            self.fixture.queue.sync {
                media = self.fixture.messageHistoryTable.renderMessageMedia(referencedMedia: record.message.referencedMedia, embeddedMediaData: record.message.embeddedMediaData)
            }
            XCTAssertEqual(media.count, 1)
            if let fixtureMedia = media.first as? FixtureMedia {
                XCTAssertEqual(fixtureMedia.id, mediaId)
                XCTAssertEqual(fixtureMedia.label, "shared")
            } else {
                XCTFail("media did not decode back as FixtureMedia")
            }
        }
    }

    func testDeletesOfDifferentMessagesDoNotInterfere() {
        let first = self.id(13)
        let second = self.id(14)
        self.store(first, timestamp: 1400, text: "first")
        self.store(second, timestamp: 1401, text: "second")

        self.remove([first, second])

        let firstRecords = self.records(first)
        XCTAssertEqual(firstRecords.count, 1)
        XCTAssertEqual(firstRecords.first?.message.text, "first")

        let secondRecords = self.records(second)
        XCTAssertEqual(secondRecords.count, 1)
        XCTAssertEqual(secondRecords.first?.message.text, "second")
        XCTAssertEqual(self.storedRecordCount(), 2)
    }

    // MARK: - Edit versions

    func testEditingMessageCapturesPreviousVersion() {
        let messageId = self.id(21)
        self.store(messageId, timestamp: 1500, text: "before edit")
        self.captureEditVersion(messageId)
        self.replaceContent(messageId, timestamp: 1500, text: "after edit")
        self.captureEditVersion(messageId)

        let records = self.records(messageId)
        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(records.first?.captureIndex, 1)
        XCTAssertEqual(records.first?.message.text, "before edit")
        XCTAssertEqual(records.last?.captureIndex, 2)
        XCTAssertEqual(records.last?.message.text, "after edit")
        for record in records {
            if record.kind != .editedVersion {
                XCTFail("unexpected kind \(record.kind)")
            }
        }
    }

    func testEditCaptureSkippedWhenPayloadUnchanged() {
        let messageId = self.id(22)
        self.store(messageId, timestamp: 1600, text: "unchanged content")
        self.captureEditVersion(messageId)
        self.captureEditVersion(messageId)

        XCTAssertEqual(self.records(messageId).count, 1)
    }

    func testEditDedupeDoesNotReportOtherMessagesCaptures() {
        let first = self.id(23)
        let second = self.id(24)
        self.store(first, timestamp: 1700, text: "same text")
        self.store(second, timestamp: 1700, text: "same text")

        self.captureEditVersion(first)
        self.captureEditVersion(second)

        XCTAssertEqual(self.records(first).count, 1)
        XCTAssertEqual(self.records(second).count, 1)
        XCTAssertEqual(self.storedRecordCount(), 2)
    }

    // MARK: - Per-message counts

    func testPerMessageCountReportsOnlyThatMessage() {
        let deleted = self.id(41)
        let edited = self.id(42)
        self.store(deleted, timestamp: 1900, text: "deleted")
        self.store(edited, timestamp: 1901, text: "edited")
        self.remove([deleted])
        self.captureEditVersion(edited)
        self.captureEditVersion(edited)

        XCTAssertEqual(self.perMessageRecordCount(deleted), 1)
        XCTAssertEqual(self.perMessageRecordCount(edited), 1)
        XCTAssertEqual(self.perMessageRecordCount(self.id(43)), 0)
        XCTAssertEqual(self.storedRecordCount(), 2)
    }

    // MARK: - Enumeration

    func testEnumerateAllReportsEveryStoredRecord() {
        let first = self.id(31)
        let second = self.id(32)
        self.store(first, timestamp: 1800, text: "one")
        self.store(second, timestamp: 1801, text: "two")
        self.remove([first, second])

        var seenIds: Set<Int32> = []
        var seenKinds: [MessageArchiveKind] = []
        self.fixture.queue.sync {
            self.fixture.messageArchiveTable.enumerateAll { record in
                seenIds.insert(record.id.id)
                seenKinds.append(record.kind)
                return true
            }
        }
        XCTAssertEqual(seenIds, Set([first.id, second.id]))
        XCTAssertEqual(seenKinds, [.deleted, .deleted])
    }

    // MARK: - Per-peer snapshots

    func testPeerListingReturnsNewestDeletedSnapshotPerMessage() {
        let first = self.id(61)
        let second = self.id(62)
        self.store(first, timestamp: 2000, text: "first deleted")
        self.store(second, timestamp: 2001, text: "second deleted")

        self.remove([first, second])

        let snapshots = self.latestSnapshots(for: self.peer)
        XCTAssertEqual(snapshots.count, 2)
        // The chat is read from the highest key downwards, so the newest message comes first.
        XCTAssertEqual(snapshots.map { $0.id.id }, [second.id, first.id])
        XCTAssertEqual(snapshots.map { $0.message.text }, ["second deleted", "first deleted"])
        for record in snapshots {
            if record.kind != .deleted {
                XCTFail("unexpected kind \(record.kind)")
            }
        }
    }

    func testPeerListingKeepsOnlyTheLatestCaptureOfADeletedMessage() {
        let messageId = self.id(63)
        self.store(messageId, timestamp: 2010, text: "initial")
        self.captureEditVersion(messageId)
        self.replaceContent(messageId, timestamp: 2010, text: "edited")

        self.remove([messageId])

        XCTAssertEqual(self.storedRecordCount(), 2)
        let snapshots = self.latestSnapshots(for: self.peer)
        XCTAssertEqual(snapshots.count, 1)
        XCTAssertEqual(snapshots.first?.captureIndex, 2)
        XCTAssertEqual(snapshots.first?.kind, .deleted)
        XCTAssertEqual(snapshots.first?.message.text, "edited")
    }

    func testPeerListingSkipsEditOnlyHistory() {
        let messageId = self.id(64)
        self.store(messageId, timestamp: 2020, text: "still delivered")
        self.captureEditVersion(messageId)

        let snapshots = self.latestSnapshots(for: self.peer)
        XCTAssertEqual(snapshots, [])
    }

    func testPeerListingIsIsolatedBetweenChats() {
        let otherPeer = MessageHistoryTableFixture.peerId(311)
        let own = self.id(65)
        self.store(own, timestamp: 2030, text: "own deletion")

        let other = MessageId(peerId: otherPeer, namespace: self.namespace, id: 12)
        let _ = self.fixture.addMessages([MessageHistoryTableFixture.storeMessage(id: other, timestamp: 2031, text: "other chat deletion")])
        let _ = self.fixture.removeMessages([other])

        XCTAssertEqual(self.latestSnapshots(for: self.peer).map { $0.message.text }, ["own deletion"])
        let otherSnapshots = self.latestSnapshots(for: otherPeer)
        XCTAssertEqual(otherSnapshots.count, 1)
        XCTAssertEqual(otherSnapshots.first?.message.text, "other chat deletion")
    }

    func testPeerListingRespectsLimit() {
        var ids: [MessageId] = []
        for (offset, idValue) in [81, 82, 83].enumerated() {
            let messageId = self.id(Int32(idValue))
            self.store(messageId, timestamp: Int32(2040 + offset), text: "msg \(idValue)")
            ids.append(messageId)
        }
        self.remove(ids)

        XCTAssertEqual(self.latestSnapshots(for: self.peer, limit: 2).map { $0.id.id }, [83, 82])
        XCTAssertEqual(self.latestSnapshots(for: self.peer, limit: 10).count, 3)
    }
}
