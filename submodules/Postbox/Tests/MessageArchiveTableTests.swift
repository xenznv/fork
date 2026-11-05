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

    func testDeletingMessageCanonizesReferencedMediaIntoSnapshot() {
        let holder = self.id(15)
        let sharer = self.id(16)
        let mediaId = MediaId(namespace: 0, id: 102)

        // The first message embeds the media row; the second message ends up referencing it.
        self.store(holder, timestamp: 1500, text: "holder", media: [FixtureMedia(id: mediaId, label: "shared")])
        self.store(sharer, timestamp: 1501, text: "sharer", media: [FixtureMedia(id: mediaId, label: "shared")])

        XCTAssertEqual(self.fixture.referenceCount(mediaId), 2, "expected the shared media row to become Direct and referenced by both messages")

        self.remove([sharer])

        var records = self.records(sharer)
        XCTAssertEqual(records.count, 1)
        if let record = records.first {
            XCTAssertTrue(record.message.referencedMedia.isEmpty, "referenced media must be resolved into the snapshot at capture time")
            var media: [Media] = []
            self.fixture.queue.sync {
                media = self.fixture.messageHistoryTable.renderMessageMedia(referencedMedia: record.message.referencedMedia, embeddedMediaData: record.message.embeddedMediaData)
            }
            guard let fixtureMedia = media.first as? FixtureMedia else {
                XCTFail("canonized media did not decode back as FixtureMedia")
                return
            }
            XCTAssertEqual(fixtureMedia.id, mediaId)
            XCTAssertEqual(fixtureMedia.label, "shared")
        }

        // The media row still exists for the first message; removing it as well must not
        // affect the already captured snapshot.
        self.remove([holder])

        records = self.records(sharer)
        XCTAssertEqual(records.count, 1)
        if let record = records.first {
            XCTAssertNil(self.fixture.mediaEntry(mediaId))
            var media: [Media] = []
            self.fixture.queue.sync {
                media = self.fixture.messageHistoryTable.renderMessageMedia(referencedMedia: record.message.referencedMedia, embeddedMediaData: record.message.embeddedMediaData)
            }
            XCTAssertEqual((media.first as? FixtureMedia)?.label, "shared")
        }
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

        XCTAssertTrue(self.latestSnapshots(for: self.peer).isEmpty)
    }

    func testPeerListingIsIsolatedBetweenChats() {
        let otherPeer = MessageHistoryTableFixture.peerId(311)
        let own = self.id(65)
        self.store(own, timestamp: 2030, text: "own deletion")
        self.remove([own])

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

    // MARK: - Export

    private func exportPage(after cursor: ArchivedMessageExportCursor?, limit: Int) -> [ArchivedMessageExportRecord] {
        var page: [ArchivedMessageExportRecord] = []
        self.fixture.queue.sync {
            page = self.fixture.messageArchiveTable.exportRecords(after: cursor, limit: limit)
        }
        return page
    }

    func testExportPagesThroughEveryCaptureExactlyOnce() {
        let edited = self.id(1)
        self.store(edited, timestamp: 100, text: "one")
        // Capture before replacing the content: the archive dedupes identical payloads, so
        // the edit version and the later deletion must carry different texts.
        self.captureEditVersion(edited)
        self.replaceContent(edited, timestamp: 100, text: "two")
        self.remove([edited])

        let deleted = self.id(2)
        self.store(deleted, timestamp: 200, text: "three")
        self.remove([deleted])

        var collected: [ArchivedMessageExportRecord] = []
        var cursor: ArchivedMessageExportCursor?
        var pages = 0
        while true {
            let page = self.exportPage(after: cursor, limit: 1)
            if page.isEmpty {
                break
            }
            pages += 1
            collected.append(contentsOf: page)
            cursor = page.last?.cursor
            XCTAssertLessThanOrEqual(pages, 10)
        }

        XCTAssertEqual(collected.count, 3)
        XCTAssertEqual(collected.map { $0.cursor.id }, [edited.id, edited.id, deleted.id])
        XCTAssertEqual(collected.map { $0.cursor.captureIndex }, [1, 2, 1])
        XCTAssertEqual(Set(collected.map { $0.cursor }).count, 3)
    }

    func testExportPayloadCarriesStoredHeaderAndKind() {
        let messageId = self.id(3)
        self.store(messageId, timestamp: 300, text: "content")
        self.remove([messageId])

        let records = self.exportPage(after: nil, limit: 10)
        XCTAssertEqual(records.count, 1)
        guard let record = records.first else {
            return
        }

        var messageTimestamp: Int32 = 0
        var captureTimestamp: Int32 = 0
        var kind: Int8 = 0
        record.payload.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            guard let base = bytes.baseAddress, bytes.count >= 9 else {
                return
            }
            memcpy(&messageTimestamp, base, 4)
            memcpy(&captureTimestamp, base.advanced(by: 4), 4)
            memcpy(&kind, base.advanced(by: 8), 1)
        }
        XCTAssertEqual(messageTimestamp, 300)
        XCTAssertEqual(captureTimestamp, record.eventTime)
        XCTAssertEqual(kind, MessageArchiveKind.deleted.rawValue)
        XCTAssertEqual(record.cursor.captureIndex, 1)
    }

    func testExportEventIdIsStablePerCaptureAndUniqueBetweenCaptures() {
        let messageId = self.id(4)
        self.store(messageId, timestamp: 400, text: "before")
        self.captureEditVersion(messageId)
        self.replaceContent(messageId, timestamp: 400, text: "after")
        self.remove([messageId])

        let records = self.exportPage(after: nil, limit: 10)
        XCTAssertEqual(records.count, 2)

        let events = records.map(archivedMessageExportEvent)
        let expected = [
            "message_archive:\(self.peer.toInt64()):\(self.namespace):\(messageId.id):1",
            "message_archive:\(self.peer.toInt64()):\(self.namespace):\(messageId.id):2"
        ]
        XCTAssertEqual(events.map { $0.eventId }, expected)
        XCTAssertEqual(events.map { $0.stream }, ["message_archive", "message_archive"])
        XCTAssertEqual(events.map { $0.eventTime }, records.map { $0.eventTime })
        XCTAssertEqual(events.map { $0.payload }, records.map { $0.payload })

        // Rebuilding from the same record yields the same identity: retries are idempotent.
        XCTAssertEqual(archivedMessageExportEvent(record: records[0]).eventId, events[0].eventId)
        XCTAssertNotEqual(events[0].eventId, events[1].eventId)
    }
}

// MARK: - Export dispatcher

/// A channel stub that accepts the first `acceptedLimit` events and declines the rest,
/// recording what it actually accepted.
private final class StubExportChannel: ArchivedMessageExportChannel {
    private let lock = NSLock()
    private(set) var events: [ArchivedMessageExportEvent] = []
    var acceptedLimit: Int = Int.max

    func send(_ event: ArchivedMessageExportEvent, _ completion: @escaping (ArchivedMessageExportChannelResult) -> Void) {
        var accept = false
        self.lock.lock()
        accept = self.events.count < self.acceptedLimit
        self.lock.unlock()
        DispatchQueue.global().async {
            var acceptedNow = false
            if accept {
                self.lock.lock()
                if self.events.count < self.acceptedLimit {
                    self.events.append(event)
                    acceptedNow = true
                }
                self.lock.unlock()
            }
            completion(acceptedNow ? .accepted : .failure("stub declined"))
        }
    }
}


// MARK: - Export HTTP channel

/// The wire format must match the backend contract (PROJECT.md §10): one
/// `POST /events` per event, bearer token, JSON with a base64 payload, any 2xx
/// means stored, a backend error surfaces as a failure with its status and a
/// body excerpt.
final class ArchivedMessageExportHTTPChannelTests: XCTestCase {
    private let url = URL(string: "https://backend.example.com/events")!

    private func sampleEvent() -> ArchivedMessageExportEvent {
        return ArchivedMessageExportEvent(
            eventId: "message_archive:711:2:5:12",
            stream: "message_archive",
            eventTime: 1_735_689_600,
            payload: Data([1, 2, 3, 255]),
            cursor: ArchivedMessageExportCursor(peerId: MessageHistoryTableFixture.peerId(711), namespace: 2, id: 5, captureIndex: 12)
        )
    }

    func testRequestMatchesBackendContract() throws {
        let event = self.sampleEvent()
        let channel = ArchivedMessageExportHTTPChannel(url: self.url, token: "secret-token", session: .shared)
        let request = channel.makeRequest(event)

        XCTAssertEqual(request.url, self.url)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer secret-token")

        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap((try JSONSerialization.jsonObject(with: body, options: [])) as? [String: Any])
        XCTAssertEqual(json["event_id"] as? String, event.eventId)
        XCTAssertEqual(json["stream"] as? String, event.stream)
        XCTAssertEqual(json["payload"] as? String, event.payload.base64EncodedString())
        XCTAssertEqual((json["event_time"] as? NSNumber)?.int32Value, event.eventTime)
    }

    func testResultOutcomeMapping() {
        func response(_ statusCode: Int) -> HTTPURLResponse {
            return HTTPURLResponse(url: self.url, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
        }

        // A 2xx (including the backend's 201) means stored, dedup included.
        XCTAssertEqual(ArchivedMessageExportHTTPChannel.result(data: "{\"sync_id\": 1}".data(using: .utf8), response: response(201), error: nil), .accepted)
        XCTAssertEqual(ArchivedMessageExportHTTPChannel.result(data: nil, response: response(200), error: nil), .accepted)

        // Backend rejections surface as failures with status and a body excerpt.
        XCTAssertEqual(ArchivedMessageExportHTTPChannel.result(data: "{\"error\": \"unauthorized\"}".data(using: .utf8), response: response(401), error: nil), .failure("backend_401: {\"error\": \"unauthorized\"}"))
        XCTAssertEqual(ArchivedMessageExportHTTPChannel.result(data: nil, response: response(429), error: nil), .failure("backend_429: "))

        // Transport-level errors and non-HTTP responses are failures too.
        let transportError = URLError(.networkConnectionLost)
        if case .failure(let reason) = ArchivedMessageExportHTTPChannel.result(data: nil, response: nil, error: transportError) {
            XCTAssertFalse(reason!.isEmpty)
        } else {
            XCTFail("expected failure")
        }
        XCTAssertEqual(ArchivedMessageExportHTTPChannel.result(data: nil, response: URLResponse(url: self.url, mimeType: nil, expectedContentLength: 0, textEncodingName: nil), error: nil), .failure("non_http_response"))
    }
}

/// The export pump walks the archive event by event and must never advance its
/// checkpoint past an event the backend has not confirmed.
final class ArchivedMessageExportDispatcherTests: XCTestCase {
    private var fixture: PostboxFixture!

    private let peer = MessageHistoryTableFixture.peerId(711)
    private let namespace = MessageHistoryTableFixture.messageNamespace

    override func setUp() {
        super.setUp()
        self.fixture = PostboxFixture(name: "ArchivedMessageExportDispatcherTests")
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

    /// Two messages of one chat, stored and then deleted, so the archive holds two
    /// deletion captures.
    private func storeAndDeleteTwoMessages() {
        self.fixture.transaction { transaction in
            transaction.updatePeersInternal([FixturePeer(id: self.peer, title: "chat")], update: { _, updated in updated })
            let _ = transaction.addMessages([
                MessageHistoryTableFixture.storeMessage(id: self.id(1), timestamp: 100, text: "one"),
                MessageHistoryTableFixture.storeMessage(id: self.id(2), timestamp: 200, text: "two")
            ], location: .Random)
        }
        self.fixture.transaction { transaction in
            transaction.deleteMessages([self.id(1), self.id(2)], forEachMedia: nil)
        }
    }

    private func savedCheckpoint(dispatcher: ArchivedMessageExportDispatcher) -> ArchivedMessageExportCursor? {
        var cursor: ArchivedMessageExportCursor?
        self.fixture.transaction { transaction in
            let entry = transaction.getPreferencesEntry(key: dispatcher.stateKey)
            cursor = entry?.get(ArchivedMessageExportSyncState.self)?.sentCursor
        }
        return cursor
    }

    func testPumpUploadsWholeArchiveAndPersistsCheckpoint() {
        self.storeAndDeleteTwoMessages()
        let channel = StubExportChannel()
        let dispatcher = ArchivedMessageExportDispatcher(postbox: self.fixture.postbox!, channel: channel)

        XCTAssertEqual(dispatcher.pumpOnce(), .uploaded(2))
        XCTAssertEqual(channel.events.count, 2)
        XCTAssertEqual(channel.events.map { $0.cursor.id }, [1, 2])
        XCTAssertEqual(self.savedCheckpoint(dispatcher: dispatcher), channel.events.last?.cursor)

        // The uploaded events are recorded in the checkpoint, so the next pump is idle.
        XCTAssertEqual(dispatcher.pumpOnce(), .caughtUp)
        XCTAssertEqual(channel.events.count, 2)
    }

    func testPumpFailureKeepsCheckpointAndRetries() {
        self.storeAndDeleteTwoMessages()
        let channel = StubExportChannel()
        channel.acceptedLimit = 1
        let dispatcher = ArchivedMessageExportDispatcher(postbox: self.fixture.postbox!, channel: channel)

        XCTAssertEqual(dispatcher.pumpOnce(), .failure("stub declined"))
        XCTAssertEqual(channel.events.count, 1)
        // The confirmed event is checkpointed; the declined one is not.
        XCTAssertEqual(self.savedCheckpoint(dispatcher: dispatcher), channel.events.first?.cursor)

        // The backend is healthy again: the declined event is retried, and this time
        // it carries the same stable identity, so the backend can dedupe it.
        channel.acceptedLimit = Int.max
        XCTAssertEqual(dispatcher.pumpOnce(), .uploaded(1))
        XCTAssertEqual(channel.events.count, 2)
        // The retry is the declined capture again (the message with id 2), with the
        // same stable identity that lets the backend ignore a repeated delivery.
        XCTAssertEqual(channel.events[1].cursor.id, 2)
        XCTAssertEqual(channel.events[1].eventId, "message_archive:\(self.peer.toInt64()):\(self.namespace):\(channel.events[1].cursor.id):\(channel.events[1].cursor.captureIndex)")
        XCTAssertEqual(self.savedCheckpoint(dispatcher: dispatcher), channel.events.last?.cursor)
    }

    func testPumpOnEmptyArchiveReportsCaughtUp() {
        let dispatcher = ArchivedMessageExportDispatcher(postbox: self.fixture.postbox!, channel: StubExportChannel())
        XCTAssertEqual(dispatcher.pumpOnce(), .caughtUp)
    }

    func testPumpWithoutChannelReportsMissing() {
        let dispatcher = ArchivedMessageExportDispatcher(postbox: self.fixture.postbox!)
        XCTAssertEqual(dispatcher.pumpOnce(), .channelMissing)
    }
}


// MARK: - Export configuration

/// The backend is compiled into the fork, so these tests pin the validation the
/// pump relies on: an unusable configuration must not produce a channel, and the
/// compiled-in one must be usable.
final class ArchivedMessageExportSettingsTests: XCTestCase {
    func testCompiledConfigurationProducesAChannel() {
        let channel = ArchivedMessageExportSettings.channel
        XCTAssertTrue(channel is ArchivedMessageExportHTTPChannel)
    }

    func testIncompleteConfigurationProducesNoChannel() {
        XCTAssertNil(ArchivedMessageExportSettings.makeChannel(endpoint: "https://export.example.com/events", token: "   "))
        XCTAssertNil(ArchivedMessageExportSettings.makeChannel(endpoint: "", token: "secret"))
        XCTAssertNil(ArchivedMessageExportSettings.makeChannel(endpoint: "not a url", token: "secret"))
        XCTAssertNil(ArchivedMessageExportSettings.makeChannel(endpoint: "ftp://export.example.com/events", token: "secret"))
        XCTAssertNil(ArchivedMessageExportSettings.makeChannel(endpoint: "https://", token: "secret"))
    }

    /// Values pasted with surrounding whitespace still work.
    func testWhitespaceAroundTheConfigurationIsIgnored() {
        XCTAssertNotNil(ArchivedMessageExportSettings.makeChannel(endpoint: " https://export.example.com/events ", token: " secret "))
    }
}
