import Foundation

/// A single thing a pulled update tells us about a chat. One `business_message`
/// produces one operation; one deletion produces one operation per chat, carrying the
/// ids it removed.
public enum BotQueueOperation {
    case message(chatId: Int64, messageId: Int32, date: Int32)
    case edit(chatId: Int64, messageId: Int32, date: Int32, editDate: Int32)
    case deletion(chatId: Int64, messageIds: [Int32])
}

/// One Bot API update reduced to what this module stores, plus the queue position it
/// came from. `updateId` is what the poller sends back as `offset` to confirm it.
public struct BotQueuePulledUpdate {
    public let updateId: Int64
    public let operations: [BotQueueOperation]
    /// The update as JSON, kept verbatim in every record it produced.
    public let body: Data

    public init(updateId: Int64, operations: [BotQueueOperation], body: Data) {
        self.updateId = updateId
        self.operations = operations
        self.body = body
    }
}

/// Turns Bot API updates into records. Pure: no storage, no networking, so the shape of
/// the payload can be tested without running a Postbox.
public enum BotQueueUpdateParser {
    public static let messageKey = "business_message"
    public static let editedMessageKey = "edited_business_message"
    public static let deletedMessagesKey = "deleted_business_messages"

    /// Bot API field names of the update kinds the queue is asked for.
    public static let allowedUpdates: [String] = [
        "business_connection",
        messageKey,
        editedMessageKey,
        deletedMessagesKey
    ]

    /// `nil` when the update carries nothing this module stores (a connection toggle, an
    /// unknown kind, a malformed payload); such an update is still confirmed, so the
    /// queue does not hand it out forever.
    public static func parse(_ update: [String: Any]) -> BotQueuePulledUpdate? {
        guard let updateId = int64(update["update_id"]) else {
            return nil
        }
        let body = (try? JSONSerialization.data(withJSONObject: update, options: [.sortedKeys])) ?? Data()

        if let message = update[messageKey] as? [String: Any] {
            guard let operation = messageOperation(message: message, isEdit: false) else {
                return nil
            }
            return BotQueuePulledUpdate(updateId: updateId, operations: [operation], body: body)
        }

        if let message = update[editedMessageKey] as? [String: Any] {
            guard let operation = messageOperation(message: message, isEdit: true) else {
                return nil
            }
            return BotQueuePulledUpdate(updateId: updateId, operations: [operation], body: body)
        }

        if let deleted = update[deletedMessagesKey] as? [String: Any] {
            guard let chat = deleted["chat"] as? [String: Any], let chatId = int64(chat["id"]) else {
                return nil
            }
            guard let rawIds = deleted["message_ids"] as? [Any] else {
                return nil
            }
            var messageIds: [Int32] = []
            for rawId in rawIds {
                if let value = int64(rawId), value > 0, value <= Int64(Int32.max) {
                    messageIds.append(Int32(value))
                }
            }
            guard !messageIds.isEmpty else {
                return nil
            }
            return BotQueuePulledUpdate(updateId: updateId, operations: [.deletion(chatId: chatId, messageIds: messageIds)], body: body)
        }

        return nil
    }

    private static func messageOperation(message: [String: Any], isEdit: Bool) -> BotQueueOperation? {
        guard let chat = message["chat"] as? [String: Any], let chatId = int64(chat["id"]) else {
            return nil
        }
        guard let messageIdValue = int64(message["message_id"]), messageIdValue > 0, messageIdValue <= Int64(Int32.max) else {
            return nil
        }
        let messageId = Int32(messageIdValue)
        let date = int32(message["date"]) ?? 0
        if isEdit {
            // An edit without an edit date is still an edit: the capture time is what
            // makes two versions distinguishable, and the date is only a display hint.
            let editDate = int32(message["edit_date"]) ?? date
            return .edit(chatId: chatId, messageId: messageId, date: date, editDate: editDate)
        }
        return .message(chatId: chatId, messageId: messageId, date: date)
    }

    private static func int64(_ value: Any?) -> Int64? {
        if let value = value as? Int64 {
            return value
        }
        if let value = value as? Int {
            return Int64(value)
        }
        if let value = value as? NSNumber {
            return value.int64Value
        }
        if let value = value as? Double, value == value.rounded(), abs(value) < 9.0e15 {
            return Int64(value)
        }
        return nil
    }

    private static func int32(_ value: Any?) -> Int32? {
        guard let value = int64(value), value >= Int64(Int32.min), value <= Int64(Int32.max) else {
            return nil
        }
        return Int32(value)
    }
}
