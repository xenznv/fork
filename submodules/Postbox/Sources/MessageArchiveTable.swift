import Foundation

public enum MessageArchiveKind: Int8 {
    case deleted
    case editedVersion
}

/// A single stored version of a message, rendered for consumption outside the module.
public struct ArchivedMessageVersion {
    public let message: Message
    public let kind: MessageArchiveKind
    /// When this version was captured locally (not when the message was sent).
    public let captureTimestamp: Int32
    /// Monotonically growing per-message version number, starting at 1.
    public let captureIndex: Int32

    init(message: Message, kind: MessageArchiveKind, captureTimestamp: Int32, captureIndex: Int32) {
        self.message = message
        self.kind = kind
        self.captureTimestamp = captureTimestamp
        self.captureIndex = captureIndex
    }
}

/// A position in the archive's key order. Export walks records in the same order the
/// table stores them, so a cursor fully identifies where the next page starts.
public struct ArchivedMessageExportCursor: Equatable, Hashable, Codable {
    public let peerId: PeerId
    public let namespace: MessageId.Namespace
    public let id: MessageId.Id
    public let captureIndex: Int32

    public init(peerId: PeerId, namespace: MessageId.Namespace, id: MessageId.Id, captureIndex: Int32) {
        self.peerId = peerId
        self.namespace = namespace
        self.id = id
        self.captureIndex = captureIndex
    }
}

/// One archived record prepared for shipping off-device. `payload` is the stored value
/// verbatim, so the receiving side reads it with the same layout `ArchivedMessageVersion`
/// is decoded from.
public struct ArchivedMessageExportEvent {
    /// Stable for a given capture, so a receiver can ignore repeated delivery of it.
    public let eventId: String
    public let stream: String
    /// Capture time in Unix seconds; a retry does not depend on the current device clock.
    public let eventTime: Int32
    public let payload: Data
    /// The export-table position the event was read from; the export checkpoint stores
    /// the cursor of the last event the backend confirmed.
    public let cursor: ArchivedMessageExportCursor

    public init(eventId: String, stream: String, eventTime: Int32, payload: Data, cursor: ArchivedMessageExportCursor) {
        self.eventId = eventId
        self.stream = stream
        self.eventTime = eventTime
        self.payload = payload
        self.cursor = cursor
    }
}

/// One page of export events plus the cursor to continue from; `nextCursor` is nil when
/// no records follow the page.
public struct ArchivedMessageExportBatch {
    public let events: [ArchivedMessageExportEvent]
    public let nextCursor: ArchivedMessageExportCursor?
}

/// A stored capture as it comes out of the table, before it is shaped into an event.
struct ArchivedMessageExportRecord {
    let cursor: ArchivedMessageExportCursor
    let eventTime: Int32
    let payload: Data
}

/// Builds the event identity shared by every delivery of the same capture. Kept apart
/// from the table so that the format can be tested without a running Postbox.
func archivedMessageExportEvent(record: ArchivedMessageExportRecord) -> ArchivedMessageExportEvent {
    return ArchivedMessageExportEvent(
        eventId: "message_archive:\(record.cursor.peerId.toInt64()):\(record.cursor.namespace):\(record.cursor.id):\(record.cursor.captureIndex)",
        stream: "message_archive",
        eventTime: record.eventTime,
        payload: record.payload,
        cursor: record.cursor
    )
}

struct ArchivedMessageRecord {
    let id: MessageId
    let timestamp: Int32
    let captureTimestamp: Int32
    let kind: MessageArchiveKind
    let captureIndex: Int32
    let message: IntermediateMessage
}

final class MessageArchiveTable: Table {
    static func tableSpec(_ id: Int32) -> ValueBoxTable {
        return ValueBoxTable(id: id, keyType: .binary, compactValuesOnCreation: false)
    }
    
    private let sharedKey = ValueBoxKey(length: 8 + 4 + 4 + 4)
    
    // Layout: int64 peerId | int32 namespace | int32 id | int32 captureIndex
    private func key(_ id: MessageId, captureIndex: Int32, key: ValueBoxKey = ValueBoxKey(length: 8 + 4 + 4 + 4)) -> ValueBoxKey {
        key.setInt64(0, value: id.peerId.toInt64())
        key.setInt32(8, value: id.namespace)
        key.setInt32(8 + 4, value: id.id)
        key.setInt32(8 + 4 + 4, value: captureIndex)
        return key
    }
    
    private func sharedKeyFor(_ id: MessageId, captureIndex: Int32) -> ValueBoxKey {
        return self.key(id, captureIndex: captureIndex, key: self.sharedKey)
    }
    
    private func lowerBound() -> ValueBoxKey {
        let key = ValueBoxKey(length: 8 + 4 + 4 + 4)
        memset(key.memory, 0, key.length)
        return key
    }
    
    private func upperBound() -> ValueBoxKey {
        let key = ValueBoxKey(length: 8 + 4 + 4 + 4)
        memset(key.memory, 0xff, key.length)
        return key
    }
    
    private func captureTimestamp() -> Int32 {
        // Unix time, matching every other timestamp the app displays and synchronizes.
        return Int32(Date().timeIntervalSince1970)
    }
    
    // MARK: Writing
    
    /// Persists a snapshot taken from an existing message entry before it is modified or removed.
    /// The payload is kept verbatim (the same binary encoding the message history table uses),
    /// preceded by a small header which reproduces the parts of the key that are not present
    /// in the entry itself.
    ///
    /// Value layout: int32 message timestamp | int32 capture timestamp | int8 kind | raw entry bytes
    func addCapture(index: MessageIndex, rawValue: ReadBuffer, kind: MessageArchiveKind, skipIfSameAsLatest: Bool) {
        let id = index.id
        
        if skipIfSameAsLatest, self.latestEntryMatchesPayload(id: id, kind: kind, rawValue: rawValue) {
            return
        }
        
        let captureIndex: Int32
        if let latest = self.latestCaptureIndex(id) {
            captureIndex = latest &+ 1
        } else {
            captureIndex = 1
        }
        
        var messageTimestamp = index.timestamp
        var storedCaptureTimestamp = self.captureTimestamp()
        var kindValue = kind.rawValue
        
        let buffer = WriteBuffer(capacity: 4 + 4 + 1 + rawValue.length)
        buffer.write(&messageTimestamp, offset: 0, length: 4)
        buffer.write(&storedCaptureTimestamp, offset: 0, length: 4)
        buffer.write(&kindValue, offset: 0, length: 1)
        buffer.write(rawValue.memory, offset: 0, length: rawValue.length)
        
        self.valueBox.set(self.table, key: self.sharedKeyFor(id, captureIndex: captureIndex), value: buffer)
    }
    
    /// True when the most recent stored record for the message carries an identical entry
    /// payload. The comparison covers the payload region only: the stored value starts
    /// with a 9-byte header (2x int32 + int8) that is skipped, and `kind` is not part of
    /// the comparison because dedup applies to repeated captures of the same content.
    private func latestEntryMatchesPayload(id: MessageId, kind: MessageArchiveKind, rawValue: ReadBuffer) -> Bool {
        let headerLength = 4 + 4 + 1
        var matches = false
        self.valueBox.range(self.table, start: self.key(id, captureIndex: Int32.max).successor, end: self.key(id, captureIndex: 1).predecessor, values: { _, value in
            guard value.length >= headerLength else {
                return false
            }
            let payloadLength = value.length - headerLength
            let payloadBytes = value.memory.advanced(by: headerLength)
            matches = payloadLength == rawValue.length && memcmp(payloadBytes, rawValue.memory, payloadLength) == 0
            return false
        }, limit: 1)
        return matches
    }
    
    // MARK: Reading
    
    func records(id: MessageId, limit: Int32 = 128) -> [ArchivedMessageRecord] {
        var records: [ArchivedMessageRecord] = []
        self.valueBox.range(self.table, start: self.key(id, captureIndex: 1).predecessor, end: self.key(id, captureIndex: Int32.max).successor, values: { key, value in
            guard key.length == 8 + 4 + 4 + 4 else {
                return true
            }
            if let record = readArchivedMessageRecord(key: key, value: value) {
                records.append(record)
            }
            return Int32(records.count) < limit
        }, limit: 0)
        return records
    }
    
    /// Boundary key that brackets all records of one chat inside the table's key space.
    /// Keys are big-endian, so the first differing byte before the chat's tail already
    /// orders other chats fully outside this range.
    private func peerBoundKey(peerId: PeerId, tail: UInt8) -> ValueBoxKey {
        let key = ValueBoxKey(length: 8 + 4 + 4 + 4)
        memset(key.memory, Int32(tail), key.length)
        key.setInt64(0, value: peerId.toInt64())
        return key
    }
    
    /// The newest deleted snapshot of every message of one chat, newest messages first.
    /// The peer's key range is read in descending order, so the first record met for a
    /// (namespace, id) pair is its latest capture; records are only counted when the
    /// capture is a deletion (edit-version records are skipped and let older records of
    /// the same message through), and reading stops early once `limit` distinct
    /// messages are collected.
    func latestSnapshotsForPeer(peerId: PeerId, limit: Int) -> [ArchivedMessageRecord] {
        var latest: [ArchivedMessageRecord?] = []
        var seen: Set<MessageId> = Set()
        if limit > 0 {
            self.valueBox.range(self.table, start: self.peerBoundKey(peerId: peerId, tail: 0xff), end: self.peerBoundKey(peerId: peerId, tail: 0x00), values: { key, value in
                guard key.length == 8 + 4 + 4 + 4 else {
                    return true
                }
                if let record = readArchivedMessageRecord(key: key, value: value), record.kind == .deleted {
                    if !seen.contains(record.id) {
                        seen.insert(record.id)
                        latest.append(record)
                        return latest.count < limit
                    }
                }
                return true
            }, limit: 0)
        }
        return latest.compactMap { $0 }
    }
    
    func enumerateAll(_ f: (ArchivedMessageRecord) -> Bool) {
        self.valueBox.range(self.table, start: self.lowerBound(), end: self.upperBound(), values: { key, value in
            if let record = readArchivedMessageRecord(key: key, value: value) {
                return f(record)
            }
            return true
        }, limit: 0)
    }
    
    /// One page of records in key order, starting strictly after `after`. The payload is
    /// the stored value verbatim: header (message timestamp, capture timestamp, kind)
    /// followed by the entry bytes.
    func exportRecords(after: ArchivedMessageExportCursor?, limit: Int) -> [ArchivedMessageExportRecord] {
        guard limit > 0 else {
            return []
        }
        var records: [ArchivedMessageExportRecord] = []
        var start: ValueBoxKey
        if let after = after {
            let id = MessageId(peerId: after.peerId, namespace: after.namespace, id: after.id)
            // The range start is exclusive, so the cursor's own key (without a `.successor`)
            // is already the correct lower bound. Taking `successor` here would be wrong:
            // the capture index is stored little-endian, so incrementing the last byte
            // (its most significant byte in memcmp order) would skip captureIndex+1 keys
            // and hide every capture after the first for this message.
            start = self.key(id, captureIndex: after.captureIndex)
        } else {
            start = self.lowerBound()
        }
        self.valueBox.range(self.table, start: start, end: self.upperBound(), values: { key, value in
            guard key.length == 8 + 4 + 4 + 4, value.length >= 4 + 4 + 1 else {
                return true
            }
            // Copy the record before touching the buffer: reading advances its position,
            // and the payload must stay the whole stored value.
            let payload = value.makeData()
            var captureTimestamp: Int32 = 0
            payload.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
                if let base = bytes.baseAddress, bytes.count >= 4 + 4 {
                    memcpy(&captureTimestamp, base.advanced(by: 4), 4)
                }
            }
            let cursor = ArchivedMessageExportCursor(
                peerId: PeerId(key.getInt64(0)),
                namespace: key.getInt32(8),
                id: key.getInt32(8 + 4),
                captureIndex: key.getInt32(8 + 4 + 4)
            )
            records.append(ArchivedMessageExportRecord(cursor: cursor, eventTime: captureTimestamp, payload: payload))
            return records.count < limit
        }, limit: 0)
        return records
    }

    func recordCount(id: MessageId) -> Int {
        var count = 0
        self.valueBox.range(self.table, start: self.key(id, captureIndex: 1).predecessor, end: self.key(id, captureIndex: Int32.max).successor, keys: { _ in
            count += 1
            return true
        }, limit: 0)
        return count
    }

    func recordCount() -> Int {
        var count = 0
        self.valueBox.range(self.table, start: self.lowerBound(), end: self.upperBound(), keys: { _ in
            count += 1
            return true
        }, limit: 0)
        return count
    }
    
    private func latestCaptureIndex(_ id: MessageId) -> Int32? {
        var latestIndex: Int32?
        self.valueBox.range(self.table, start: self.key(id, captureIndex: Int32.max).successor, end: self.key(id, captureIndex: 1).predecessor, values: { key, _ in
            if key.length == 8 + 4 + 4 + 4 {
                latestIndex = key.getInt32(8 + 4 + 4)
            }
            return false
        }, limit: 1)
        return latestIndex
    }
}

private let archivedEntryTypeIntermediateMessage: Int8 = 0

// Mirrors the private per-field flags layout of the intermediate message entry format
// (see MessageHistoryTable). Both encodings must stay in sync.
private struct ArchivedEntryDataFlags: OptionSet {
    var rawValue: Int8
    
    init() {
        self.rawValue = 0
    }
    
    init(rawValue: Int8) {
        self.rawValue = rawValue
    }
    
    static let hasGloballyUniqueId = ArchivedEntryDataFlags(rawValue: 1 << 0)
    static let hasGlobalTags = ArchivedEntryDataFlags(rawValue: 1 << 1)
    static let hasGroupingKey = ArchivedEntryDataFlags(rawValue: 1 << 2)
    static let hasGroupInfo = ArchivedEntryDataFlags(rawValue: 1 << 3)
    static let hasLocalTags = ArchivedEntryDataFlags(rawValue: 1 << 4)
    static let hasThreadId = ArchivedEntryDataFlags(rawValue: 1 << 5)
}

// Decodes an archived record from its key and stored value. The entry payload section is
// byte-for-byte the intermediate message entry format used by MessageHistoryTable; the
// message id and timestamp that live in the source table's key are taken from the archive
// key and the value header instead. Keep in sync with MessageHistoryTable.readIntermediateEntry.
private func readArchivedMessageRecord(key: ValueBoxKey, value: ReadBuffer) -> ArchivedMessageRecord? {
    precondition(key.length == 8 + 4 + 4 + 4)
    
    let id = MessageId(peerId: PeerId(key.getInt64(0)), namespace: key.getInt32(8), id: key.getInt32(8 + 4))
    let captureIndex = key.getInt32(8 + 4 + 4)
    
    var messageTimestamp: Int32 = 0
    var captureTimestamp: Int32 = 0
    var kindValue: Int8 = 0
    value.read(&messageTimestamp, offset: 0, length: 4)
    value.read(&captureTimestamp, offset: 0, length: 4)
    value.read(&kindValue, offset: 0, length: 1)
    
    var entryType: Int8 = 0
    value.read(&entryType, offset: 0, length: 1)
    if entryType != archivedEntryTypeIntermediateMessage {
        return nil
    }
    
    var stableId: UInt32 = 0
    value.read(&stableId, offset: 0, length: 4)
    
    var stableVersion: UInt32 = 0
    value.read(&stableVersion, offset: 0, length: 4)
    
    var dataFlagsValue: Int8 = 0
    value.read(&dataFlagsValue, offset: 0, length: 1)
    let dataFlags = ArchivedEntryDataFlags(rawValue: dataFlagsValue)
    
    var globallyUniqueId: Int64?
    if dataFlags.contains(.hasGloballyUniqueId) {
        var globallyUniqueIdValue: Int64 = 0
        value.read(&globallyUniqueIdValue, offset: 0, length: 8)
        globallyUniqueId = globallyUniqueIdValue
    }
    
    var globalTags: GlobalMessageTags = []
    if dataFlags.contains(.hasGlobalTags) {
        var globalTagsValue: UInt32 = 0
        value.read(&globalTagsValue, offset: 0, length: 4)
        globalTags = GlobalMessageTags(rawValue: globalTagsValue)
    }
    
    var groupingKey: Int64?
    if dataFlags.contains(.hasGroupingKey) {
        var groupingKeyValue: Int64 = 0
        value.read(&groupingKeyValue, offset: 0, length: 8)
        groupingKey = groupingKeyValue
    }
    
    var groupInfo: MessageGroupInfo?
    if dataFlags.contains(.hasGroupInfo) {
        var stableIdValue: UInt32 = 0
        value.read(&stableIdValue, offset: 0, length: 4)
        groupInfo = MessageGroupInfo(stableId: stableIdValue)
    }
    
    var localTags: LocalMessageTags = []
    if dataFlags.contains(.hasLocalTags) {
        var localTagsValue: UInt32 = 0
        value.read(&localTagsValue, offset: 0, length: 4)
        localTags = LocalMessageTags(rawValue: localTagsValue)
    }
    
    var threadId: Int64?
    if dataFlags.contains(.hasThreadId) {
        var threadIdValue: Int64 = 0
        value.read(&threadIdValue, offset: 0, length: 8)
        threadId = threadIdValue
    }
    
    var flagsValue: UInt32 = 0
    value.read(&flagsValue, offset: 0, length: 4)
    let flags = MessageFlags(rawValue: flagsValue)
    
    var tagsValue: UInt32 = 0
    value.read(&tagsValue, offset: 0, length: 4)
    let tags = MessageTags(rawValue: tagsValue)
    
    var forwardInfoFlags: Int8 = 0
    value.read(&forwardInfoFlags, offset: 0, length: 1)
    var forwardInfo: IntermediateMessageForwardInfo?
    if forwardInfoFlags != 0 {
        var forwardAuthorId: Int64 = 0
        var forwardDate: Int32 = 0
        var forwardSourceId: PeerId?
        var forwardSourceMessageId: MessageId?
        var authorSignature: String? = nil
        var psaType: String? = nil
        var forwardFlags: MessageForwardInfo.Flags = []
        
        value.read(&forwardAuthorId, offset: 0, length: 8)
        value.read(&forwardDate, offset: 0, length: 4)
        
        if (forwardInfoFlags & (1 << 1)) != 0 {
            var forwardSourceIdValue: Int64 = 0
            value.read(&forwardSourceIdValue, offset: 0, length: 8)
            forwardSourceId = PeerId(forwardSourceIdValue)
        }
        
        if (forwardInfoFlags & (1 << 2)) != 0 {
            var forwardSourceMessagePeerId: Int64 = 0
            var forwardSourceMessageNamespace: Int32 = 0
            var forwardSourceMessageIdId: Int32 = 0
            value.read(&forwardSourceMessagePeerId, offset: 0, length: 8)
            value.read(&forwardSourceMessageNamespace, offset: 0, length: 4)
            value.read(&forwardSourceMessageIdId, offset: 0, length: 4)
            forwardSourceMessageId = MessageId(peerId: PeerId(forwardSourceMessagePeerId), namespace: forwardSourceMessageNamespace, id: forwardSourceMessageIdId)
        }
        
        if (forwardInfoFlags & (1 << 3)) != 0 {
            var signatureLength: Int32 = 0
            value.read(&signatureLength, offset: 0, length: 4)
            authorSignature = String(data: Data(bytes: value.memory.assumingMemoryBound(to: UInt8.self).advanced(by: value.offset), count: Int(signatureLength)), encoding: .utf8)
            value.skip(Int(signatureLength))
        }
        
        if (forwardInfoFlags & (1 << 4)) != 0 {
            var psaTypeLength: Int32 = 0
            value.read(&psaTypeLength, offset: 0, length: 4)
            psaType = String(data: Data(bytes: value.memory.assumingMemoryBound(to: UInt8.self).advanced(by: value.offset), count: Int(psaTypeLength)), encoding: .utf8)
            value.skip(Int(psaTypeLength))
        }
        
        if (forwardInfoFlags & (1 << 5)) != 0 {
            var rawValue: Int32 = 0
            value.read(&rawValue, offset: 0, length: 4)
            forwardFlags = MessageForwardInfo.Flags(rawValue: rawValue)
        }
        
        forwardInfo = IntermediateMessageForwardInfo(authorId: forwardAuthorId == 0 ? nil : PeerId(forwardAuthorId), sourceId: forwardSourceId, sourceMessageId: forwardSourceMessageId, date: forwardDate, authorSignature: authorSignature, psaType: psaType, flags: forwardFlags)
    }
    
    var hasAuthor: Int8 = 0
    value.read(&hasAuthor, offset: 0, length: 1)
    var authorId: PeerId?
    if hasAuthor == 1 {
        var internalAuthorId: Int64 = 0
        value.read(&internalAuthorId, offset: 0, length: 8)
        authorId = PeerId(internalAuthorId)
    }
    
    var textLength: Int32 = 0
    value.read(&textLength, offset: 0, length: 4)
    let text = String(data: Data(bytes: value.memory.assumingMemoryBound(to: UInt8.self).advanced(by: value.offset), count: Int(textLength)), encoding: .utf8) ?? ""
    value.skip(Int(textLength))
    
    let attributesOffset = value.offset
    var attributeCount: Int32 = 0
    value.read(&attributeCount, offset: 0, length: 4)
    for _ in 0 ..< attributeCount {
        var attributeLength: Int32 = 0
        value.read(&attributeLength, offset: 0, length: 4)
        value.skip(Int(attributeLength))
    }
    let attributesLength = value.offset - attributesOffset
    let attributesBytes = malloc(attributesLength)!
    memcpy(attributesBytes, value.memory + attributesOffset, attributesLength)
    let attributesData = ReadBuffer(memory: attributesBytes, length: attributesLength, freeWhenDone: true)
    
    let embeddedMediaOffset = value.offset
    var embeddedMediaCount: Int32 = 0
    value.read(&embeddedMediaCount, offset: 0, length: 4)
    for _ in 0 ..< embeddedMediaCount {
        var mediaLength: Int32 = 0
        value.read(&mediaLength, offset: 0, length: 4)
        value.skip(Int(mediaLength))
    }
    let embeddedMediaLength = value.offset - embeddedMediaOffset
    let embeddedMediaBytes = malloc(embeddedMediaLength)!
    memcpy(embeddedMediaBytes, value.memory + embeddedMediaOffset, embeddedMediaLength)
    let embeddedMediaData = ReadBuffer(memory: embeddedMediaBytes, length: embeddedMediaLength, freeWhenDone: true)
    
    var referencedMediaIds: [MediaId] = []
    var referencedMediaIdsCount: Int32 = 0
    value.read(&referencedMediaIdsCount, offset: 0, length: 4)
    for _ in 0 ..< referencedMediaIdsCount {
        var idNamespace: Int32 = 0
        var idId: Int64 = 0
        value.read(&idNamespace, offset: 0, length: 4)
        value.read(&idId, offset: 0, length: 8)
        referencedMediaIds.append(MediaId(namespace: idNamespace, id: idId))
    }
    
    var customTags: [MemoryBuffer] = []
    var customTagCount: Int32 = 0
    if value.offset < value.length {
        value.read(&customTagCount, offset: 0, length: 4)
        for _ in 0 ..< customTagCount {
            var customTagLength: Int32 = 0
            value.read(&customTagLength, offset: 0, length: 4)
            customTags.append(value.readMemoryBuffer(length: Int(customTagLength)))
        }
    }
    
    let message = IntermediateMessage(stableId: stableId, stableVersion: stableVersion, id: id, globallyUniqueId: globallyUniqueId, groupingKey: groupingKey, groupInfo: groupInfo, threadId: threadId, timestamp: messageTimestamp, flags: flags, tags: tags, globalTags: globalTags, localTags: localTags, customTags: customTags, forwardInfo: forwardInfo, authorId: authorId, text: text, attributesData: attributesData, embeddedMediaData: embeddedMediaData, referencedMedia: referencedMediaIds)
    
    return ArchivedMessageRecord(id: id, timestamp: messageTimestamp, captureTimestamp: captureTimestamp, kind: MessageArchiveKind(rawValue: kindValue) ?? .deleted, captureIndex: captureIndex, message: message)
}
