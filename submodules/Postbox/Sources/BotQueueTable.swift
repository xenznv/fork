import Foundation

/// What a pulled update says about a specific message. Deliberately separate from
/// `MessageArchiveKind`: the archive stores snapshots this device took of its own
/// message history, while these records keep what the bot's queue delivered, including
/// chats and messages this device may never have seen.
public enum BotQueueRecordKind: Int8 {
    case message = 0
    case edit = 1
    case deletion = 2
}

/// One business event as it came out of the update queue.
public struct BotQueueRecord {
    /// Bot API chat id: positive for a private chat, negative for a group or channel.
    public let chatId: Int64
    public let messageId: Int32
    public let kind: BotQueueRecordKind
    /// Message date from the update (the edit date for an edit), Unix seconds.
    public let eventDate: Int32
    /// When this device stored the record, Unix seconds.
    public let storedAt: Int32
    /// The whole update as JSON, byte for byte as the Bot API delivered it. Storing the
    /// source payload keeps later readers independent of which fields this build knows.
    public let body: Data

    public init(chatId: Int64, messageId: Int32, kind: BotQueueRecordKind, eventDate: Int32, storedAt: Int32, body: Data) {
        self.chatId = chatId
        self.messageId = messageId
        self.kind = kind
        self.eventDate = eventDate
        self.storedAt = storedAt
        self.body = body
    }
}

/// Records pulled from the bot's update queue, keyed by (chat, message, kind) so that a
/// message, its later edit and its deletion coexist instead of overwriting each other:
/// the deletion is what makes the text of a removed message worth keeping.
///
/// Value layout: int32 event date | int32 stored at | int32 body length | body bytes
final class BotQueueTable: Table {
    static func tableSpec(_ id: Int32) -> ValueBoxTable {
        return ValueBoxTable(id: id, keyType: .binary, compactValuesOnCreation: false)
    }

    private static let keyLength = 8 + 4 + 1
    private static let headerLength = 4 + 4 + 4

    private let sharedKey = ValueBoxKey(length: BotQueueTable.keyLength)

    // Layout: int64 chatId | int32 messageId | int8 kind
    private func key(chatId: Int64, messageId: Int32, kind: BotQueueRecordKind, key: ValueBoxKey = ValueBoxKey(length: BotQueueTable.keyLength)) -> ValueBoxKey {
        key.setInt64(0, value: chatId)
        key.setInt32(8, value: messageId)
        key.setInt8(8 + 4, value: kind.rawValue)
        return key
    }

    private func chatBoundKey(chatId: Int64, tail: UInt8) -> ValueBoxKey {
        let key = ValueBoxKey(length: BotQueueTable.keyLength)
        memset(key.memory, Int32(tail), key.length)
        key.setInt64(0, value: chatId)
        return key
    }

    private func lowerBound() -> ValueBoxKey {
        let key = ValueBoxKey(length: BotQueueTable.keyLength)
        memset(key.memory, 0, key.length)
        return key
    }

    private func upperBound() -> ValueBoxKey {
        let key = ValueBoxKey(length: BotQueueTable.keyLength)
        memset(key.memory, 0xff, key.length)
        return key
    }

    // MARK: Writing

    /// Writes one record, replacing an earlier record with the same (chat, message, kind):
    /// a repeated update is the same information delivered twice, not a new version.
    func set(_ record: BotQueueRecord) {
        var eventDate = record.eventDate
        var storedAt = record.storedAt
        var bodyLength = Int32(record.body.count)

        let buffer = WriteBuffer(capacity: BotQueueTable.headerLength + record.body.count)
        buffer.write(&eventDate, offset: 0, length: 4)
        buffer.write(&storedAt, offset: 0, length: 4)
        buffer.write(&bodyLength, offset: 0, length: 4)
        record.body.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            if let base = bytes.baseAddress, bytes.count > 0 {
                buffer.write(base, offset: 0, length: bytes.count)
            }
        }

        self.valueBox.set(self.table, key: self.key(chatId: record.chatId, messageId: record.messageId, kind: record.kind, key: self.sharedKey), value: buffer)
    }

    // MARK: Reading

    func record(chatId: Int64, messageId: Int32, kind: BotQueueRecordKind) -> BotQueueRecord? {
        guard let value = self.valueBox.get(self.table, key: self.key(chatId: chatId, messageId: messageId, kind: kind)) else {
            return nil
        }
        return readBotQueueRecord(chatId: chatId, messageId: messageId, kind: kind, value: value)
    }

    /// Every record of one chat in key order (message id, then kind).
    func records(chatId: Int64, limit: Int) -> [BotQueueRecord] {
        guard limit > 0 else {
            return []
        }
        var records: [BotQueueRecord] = []
        self.valueBox.range(self.table, start: self.chatBoundKey(chatId: chatId, tail: 0x00), end: self.chatBoundKey(chatId: chatId, tail: 0xff), values: { key, value in
            guard key.length == BotQueueTable.keyLength else {
                return true
            }
            let kind = BotQueueRecordKind(rawValue: key.getInt8(8 + 4))
            if let kind = kind, let record = readBotQueueRecord(chatId: key.getInt64(0), messageId: key.getInt32(8), kind: kind, value: value) {
                records.append(record)
            }
            return records.count < limit
        }, limit: 0)
        return records
    }

    func count(kind: BotQueueRecordKind) -> Int {
        var count = 0
        self.valueBox.range(self.table, start: self.lowerBound(), end: self.upperBound(), values: { key, _ in
            if key.length == BotQueueTable.keyLength, key.getInt8(8 + 4) == kind.rawValue {
                count += 1
            }
            return true
        }, limit: 0)
        return count
    }

    /// Chat ids that have at least one record, in key order. Used by diagnostics and by
    /// readers that walk the queue chat by chat.
    func chatIds(limit: Int) -> [Int64] {
        guard limit > 0 else {
            return []
        }
        var ids: [Int64] = []
        var last: Int64?
        self.valueBox.range(self.table, start: self.lowerBound(), end: self.upperBound(), values: { key, _ in
            guard key.length == BotQueueTable.keyLength else {
                return true
            }
            let chatId = key.getInt64(0)
            if chatId != last {
                last = chatId
                ids.append(chatId)
            }
            return ids.count < limit
        }, limit: 0)
        return ids
    }
}

/// Decodes one stored record. `ValueBoxKey` and the value share the same chat/message/kind
/// identity, so only the payload part needs to be read from the value.
private func readBotQueueRecord(chatId: Int64, messageId: Int32, kind: BotQueueRecordKind, value: ReadBuffer) -> BotQueueRecord? {
    let headerLength = 12
    let raw = value.makeData()
    guard raw.count >= headerLength else {
        return nil
    }

    var eventDate: Int32 = 0
    var storedAt: Int32 = 0
    var bodyLength: Int32 = 0
    raw.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
        guard let base = bytes.baseAddress, bytes.count >= headerLength else {
            return
        }
        memcpy(&eventDate, base, 4)
        memcpy(&storedAt, base.advanced(by: 4), 4)
        memcpy(&bodyLength, base.advanced(by: 8), 4)
    }

    // A truncated value (interrupted write, older layout) is dropped instead of being
    // handed out as an empty event: the next poll re-fetches the update anyway.
    guard bodyLength >= 0, headerLength + Int(bodyLength) <= raw.count else {
        return nil
    }
    let body = raw.subdata(in: headerLength ..< (headerLength + Int(bodyLength)))

    return BotQueueRecord(chatId: chatId, messageId: messageId, kind: kind, eventDate: eventDate, storedAt: storedAt, body: body)
}
