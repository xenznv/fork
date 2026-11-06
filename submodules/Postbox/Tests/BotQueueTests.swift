import Foundation
import XCTest
@testable import Postbox

/// The bot queue stores business events exactly as the Bot API delivered them, so its
/// parser and its table are what decide whether a message survives in the archive after
/// the original disappears from Telegram.
final class BotQueueUpdateParserTests: XCTestCase {
    private func message(_ fields: [String: Any]) -> [String: Any] {
        var message: [String: Any] = [
            "message_id": 213,
            "date": 1_800_000_000,
            "text": "hello",
            "chat": ["id": 5697590130, "type": "private"]
        ]
        for (key, value) in fields {
            message[key] = value
        }
        return message
    }

    func testBusinessMessageBecomesOneMessageOperation() throws {
        let update: [String: Any] = ["update_id": 444_526_417, "business_message": self.message([:])]
        let pulled = try XCTUnwrap(BotQueueUpdateParser.parse(update))
        XCTAssertEqual(pulled.updateId, 444_526_417)
        guard case let .message(chatId, messageId, date)? = pulled.operations.first else {
            return XCTFail("expected a message operation")
        }
        XCTAssertEqual(chatId, 5697590130)
        XCTAssertEqual(messageId, 213)
        XCTAssertEqual(date, 1_800_000_000)

        // The stored body is the source payload, so a later reader does not depend on what
        // this build happened to parse.
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: pulled.body) as? [String: Any])
        XCTAssertEqual((body["update_id"] as? NSNumber)?.int64Value ?? -1, 444_526_417)
        XCTAssertNotNil(body["business_message"])
    }

    func testEditedMessageCarriesTheEditDate() throws {
        let update: [String: Any] = [
            "update_id": 444_526_500,
            "edited_business_message": self.message(["edit_date": 1_800_000_900])
        ]
        let pulled = try XCTUnwrap(BotQueueUpdateParser.parse(update))
        guard case let .edit(chatId, messageId, date, editDate)? = pulled.operations.first else {
            return XCTFail("expected an edit operation")
        }
        XCTAssertEqual(chatId, 5697590130)
        XCTAssertEqual(messageId, 213)
        XCTAssertEqual(date, 1_800_000_000)
        XCTAssertEqual(editDate, 1_800_000_900)
    }

    func testEditWithoutEditDateFallsBackToTheMessageDate() throws {
        let update: [String: Any] = ["update_id": 1, "edited_business_message": self.message([:])]
        let pulled = try XCTUnwrap(BotQueueUpdateParser.parse(update))
        guard case let .edit(_, _, date, editDate)? = pulled.operations.first else {
            return XCTFail("expected an edit operation")
        }
        XCTAssertEqual(editDate, date)
    }

    func testDeletionKeepsEveryValidId() throws {
        let update: [String: Any] = [
            "update_id": 7,
            "deleted_business_messages": [
                "chat": ["id": -1001234567890],
                "message_ids": [410, 411, 412, 0, -3, "nonsense"]
            ]
        ]
        let pulled = try XCTUnwrap(BotQueueUpdateParser.parse(update))
        guard case let .deletion(chatId, messageIds)? = pulled.operations.first else {
            return XCTFail("expected a deletion operation")
        }
        XCTAssertEqual(chatId, -1001234567890)
        XCTAssertEqual(messageIds, [410, 411, 412])
    }

    func testUpdatesWithoutStoredContentAreIgnored() {
        XCTAssertNil(BotQueueUpdateParser.parse(["update_id": 1, "business_connection": ["id": "x"]]))
        XCTAssertNil(BotQueueUpdateParser.parse(["business_message": self.message([:])]))
        XCTAssertNil(BotQueueUpdateParser.parse(["update_id": 1, "business_message": ["message_id": 1]]))
        XCTAssertNil(BotQueueUpdateParser.parse(["update_id": 1, "deleted_business_messages": ["chat": ["id": 1], "message_ids": []]]))
    }

    func testAllowedUpdatesCoverTheFourBusinessKinds() {
        XCTAssertEqual(Set(BotQueueUpdateParser.allowedUpdates), Set([
            "business_connection",
            "business_message",
            "edited_business_message",
            "deleted_business_messages"
        ]))
    }
}

/// Records of the same message must coexist by kind: the deletion is what makes the text
/// of a removed message worth keeping, so it must not overwrite the message itself.
final class BotQueueTableTests: XCTestCase {
    private var fixture: MessageHistoryTableFixture!

    override func setUp() {
        super.setUp()
        self.fixture = MessageHistoryTableFixture(name: "BotQueueTableTests")
    }

    override func tearDown() {
        self.fixture.close()
        self.fixture = nil
        super.tearDown()
    }

    private func record(chatId: Int64, messageId: Int32, kind: BotQueueRecordKind, date: Int32 = 1_800_000_000, body: String) -> BotQueueRecord {
        return BotQueueRecord(chatId: chatId, messageId: messageId, kind: kind, eventDate: date, storedAt: date + 1, body: body.data(using: .utf8)!)
    }

    private func store(_ records: [BotQueueRecord]) {
        self.fixture.transaction { _, _ in
            for record in records {
                self.fixture.botQueueTable.set(record)
            }
        }
    }

    private func records(chatId: Int64, limit: Int = 64) -> [BotQueueRecord] {
        var result: [BotQueueRecord] = []
        self.fixture.queue.sync {
            result = self.fixture.botQueueTable.records(chatId: chatId, limit: limit)
        }
        return result
    }

    private func count(_ kind: BotQueueRecordKind) -> Int {
        var result = 0
        self.fixture.queue.sync {
            result = self.fixture.botQueueTable.count(kind: kind)
        }
        return result
    }

    func testMessageEditAndDeletionCoexistAndDecodeBack() {
        let chat: Int64 = 5697590130
        self.store([
            self.record(chatId: chat, messageId: 213, kind: .message, date: 1_800_000_000, body: "{\"n\":1}"),
            self.record(chatId: chat, messageId: 213, kind: .edit, date: 1_800_000_600, body: "{\"n\":2}"),
            self.record(chatId: chat, messageId: 213, kind: .deletion, date: 1_800_000_900, body: "{\"n\":3}")
        ])

        let stored = self.records(chatId: chat)
        XCTAssertEqual(stored.map { $0.kind }, [.message, .edit, .deletion])
        XCTAssertEqual(stored.map { $0.eventDate }, [1_800_000_000, 1_800_000_600, 1_800_000_900])
        XCTAssertEqual(stored.map { String(data: $0.body, encoding: .utf8)! }, ["{\"n\":1}", "{\"n\":2}", "{\"n\":3}"])
        XCTAssertEqual(self.count(.message), 1)
        XCTAssertEqual(self.count(.deletion), 1)
    }

    func testRepeatedDeliveryOverwritesInsteadOfDuplicating() {
        let chat: Int64 = 42
        self.store([self.record(chatId: chat, messageId: 5, kind: .message, body: "first")])
        self.store([self.record(chatId: chat, messageId: 5, kind: .message, body: "second")])

        let stored = self.records(chatId: chat)
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(String(data: stored[0].body, encoding: .utf8), "second")
    }

    func testChatsAreIsolatedAndListedInKeyOrder() {
        self.store([
            self.record(chatId: 7, messageId: 2, kind: .message, body: "a"),
            self.record(chatId: 7, messageId: 1, kind: .message, body: "b"),
            self.record(chatId: -1001234567890, messageId: 9, kind: .message, body: "c")
        ])

        XCTAssertEqual(self.records(chatId: 7).map { $0.messageId }, [1, 2])
        XCTAssertEqual(self.records(chatId: -1001234567890).map { $0.messageId }, [9])
        XCTAssertTrue(self.records(chatId: 8).isEmpty)

        var chatIds: [Int64] = []
        self.fixture.queue.sync {
            chatIds = self.fixture.botQueueTable.chatIds(limit: 16)
        }
        XCTAssertEqual(Set(chatIds), Set<Int64>([7, -1001234567890]))
    }

    func testLimitStopsAfterTheRequestedRecords() {
        self.store((1 ... 5).map { self.record(chatId: 3, messageId: Int32($0), kind: .message, body: "m\($0)") })
        XCTAssertEqual(self.records(chatId: 3, limit: 2).map { $0.messageId }, [1, 2])
        XCTAssertEqual(self.records(chatId: 3, limit: 0).count, 0)
    }

    /// The whole path: an update pulled from the queue, stored, and read back with its
    /// payload intact — this is what a drain leaves behind for the archive to use.
    func testPulledUpdateRoundTripsThroughTheTable() throws {
        let update: [String: Any] = [
            "update_id": 444_526_417,
            "business_message": [
                "message_id": 410,
                "date": 1_800_000_000,
                "text": "victim",
                "chat": ["id": 5697590130]
            ]
        ]
        let pulled = try XCTUnwrap(BotQueueUpdateParser.parse(update))
        var records: [BotQueueRecord] = []
        for operation in pulled.operations {
            guard case let .message(chatId, messageId, date) = operation else {
                continue
            }
            records.append(BotQueueRecord(chatId: chatId, messageId: messageId, kind: .message, eventDate: date, storedAt: date, body: pulled.body))
        }
        self.store(records)

        let stored = self.records(chatId: 5697590130)
        XCTAssertEqual(stored.count, 1)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: stored[0].body) as? [String: Any])
        let message = try XCTUnwrap(body["business_message"] as? [String: Any])
        XCTAssertEqual(message["text"] as? String, "victim")
        XCTAssertEqual((body["update_id"] as? NSNumber)?.int64Value ?? -1, 444_526_417)
    }
}
