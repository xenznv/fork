import Foundation
import BuildConfig

// Client for the external archive API served by the message saver bot.
// Read-only: lists deleted/edited messages that the
// Telegram server no longer returns, so the custom can restore them locally.

public enum CustomArchiveSettingsKey {
    public static let serverURL = "custom.Archive.ServerURL"
    public static let token = "custom.Archive.Token"
    public static let status = "custom.Archive.Status"
    public static let lastSyncPrefix = "custom.Archive.LastSync."
}

public final class CustomArchiveSettings {
    // The archive is wired into the build by default: the embedded URL and
    // token always win. UserDefaults is only a fallback for builds built
    // without the archive configuration, so stale values typed into an old
    // settings screen can never override the official connection.
    public static var serverURL: String {
        get {
            let embedded = BuildConfig.customArchiveURL()
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !embedded.isEmpty {
                return embedded
            }
            return (UserDefaults.standard.string(forKey: CustomArchiveSettingsKey.serverURL) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        set {
            UserDefaults.standard.set(
                newValue.trimmingCharacters(in: .whitespacesAndNewlines),
                forKey: CustomArchiveSettingsKey.serverURL
            )
        }
    }

    public static var token: String {
        get {
            let embedded = BuildConfig.customArchiveToken()
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !embedded.isEmpty {
                return embedded
            }
            return (UserDefaults.standard.string(forKey: CustomArchiveSettingsKey.token) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        set {
            UserDefaults.standard.set(
                newValue.trimmingCharacters(in: .whitespacesAndNewlines),
                forKey: CustomArchiveSettingsKey.token
            )
        }
    }

    public static var isConfigured: Bool {
        return !self.serverURL.isEmpty && !self.token.isEmpty
    }

    public static var status: String {
        get {
            return UserDefaults.standard.string(forKey: CustomArchiveSettingsKey.status) ?? ""
        }
        set {
            UserDefaults.standard.set(newValue, forKey: CustomArchiveSettingsKey.status)
        }
    }

    // The cursor scheme below changed when edits started being restored: a build
    // that only knew about deletions moved a chat's mark past edits it ignored,
    // and nothing would ever ask for them again. Marks are therefore namespaced
    // per scheme, so a chat without a mark for the current scheme is read once
    // from the beginning, which is exactly how those edits come back.
    // v3: stickers restored by v2 carry no pack reference, so they cannot be
    // tapped to open their set. The mark reset makes every chat re-read its
    // history once; media is already on disk, so nothing is re-downloaded.
    public static let lastSyncSchemeVersion = 3

    // The mark written by builds before the current scheme, kept only so it can
    // be cleaned up: it must never be read again.
    private static func legacyLastSyncKey(accountPeerId: Int64, chatPeerId: Int64) -> String {
        return CustomArchiveSettingsKey.lastSyncPrefix
            + "\(accountPeerId).\(chatPeerId)"
    }

    private static func lastSyncKey(accountPeerId: Int64, chatPeerId: Int64) -> String {
        return CustomArchiveSettingsKey.lastSyncPrefix
            + "v\(self.lastSyncSchemeVersion).\(accountPeerId).\(chatPeerId)"
    }

    public static func lastSync(accountPeerId: Int64, chatPeerId: Int64) -> Int {
        return UserDefaults.standard.integer(
            forKey: self.lastSyncKey(accountPeerId: accountPeerId, chatPeerId: chatPeerId)
        )
    }

    public static func setLastSync(accountPeerId: Int64, chatPeerId: Int64, value: Int) {
        UserDefaults.standard.removeObject(
            forKey: self.legacyLastSyncKey(accountPeerId: accountPeerId, chatPeerId: chatPeerId)
        )
        UserDefaults.standard.set(
            value,
            forKey: self.lastSyncKey(accountPeerId: accountPeerId, chatPeerId: chatPeerId)
        )
    }
}

public struct CustomArchiveDeletedMessage {
    public let messageId: Int32
    public let senderId: Int64?
    public let senderName: String?
    public let date: Date?
    public let deletedAt: Date?
    public let text: String?
    public let direction: String?
    // Saved media: "photo", "video", "voice", "document"... plus the path
    // relative to the archive's media root, usable in a /media/ request.
    public let mediaType: String?
    public let mediaPath: String?
    public let mediaSize: Int64?
    // Sticker emoji from the archive metadata: keeps the restored sticker
    // bubble showing its real emoji.
    public let emoji: String?
    // The set the sticker belongs to (short name): tapping the restored
    // sticker opens this set, exactly like a live sticker.
    public let setName: String?

    public init(
        messageId: Int32,
        senderId: Int64?,
        senderName: String?,
        date: Date?,
        deletedAt: Date?,
        text: String?,
        direction: String?,
        mediaType: String? = nil,
        mediaPath: String? = nil,
        mediaSize: Int64? = nil,
        emoji: String? = nil,
        setName: String? = nil
    ) {
        self.messageId = messageId
        self.senderId = senderId
        self.senderName = senderName
        self.date = date
        self.deletedAt = deletedAt
        self.text = text
        self.direction = direction
        self.mediaType = mediaType
        self.mediaPath = mediaPath
        self.mediaSize = mediaSize
        self.emoji = emoji
        self.setName = setName
    }
}

// One recorded edit of a message: the text that was replaced and when. Kept as
// a version list, so a message edited while the app was closed still shows its
// history the way a live edit does.
public struct CustomArchiveEditedMessage {
    public let messageId: Int32
    public let oldText: String?
    public let newText: String?
    public let editedAt: Date?

    public init(
        messageId: Int32,
        oldText: String?,
        newText: String?,
        editedAt: Date?
    ) {
        self.messageId = messageId
        self.oldText = oldText
        self.newText = newText
        self.editedAt = editedAt
    }
}

public struct CustomArchiveUpdates {
    public let serverTime: Int
    public let deleted: [CustomArchiveDeletedMessage]
    public let edited: [CustomArchiveEditedMessage]

    public init(
        serverTime: Int,
        deleted: [CustomArchiveDeletedMessage],
        edited: [CustomArchiveEditedMessage] = []
    ) {
        self.serverTime = serverTime
        self.deleted = deleted
        self.edited = edited
    }
}

// One chat the archive holds messages for. `chatId` uses the same wire
// encoding the app sends when it asks for updates: a plain Telegram id for a
// user chat, and an offset value for the chats the archive stores under a
// negative id (groups and channels).
public struct CustomArchiveChat {
    public let chatId: Int64
    public let title: String?
    public let chatType: String?

    public init(chatId: Int64, title: String?, chatType: String?) {
        self.chatId = chatId
        self.title = title
        self.chatType = chatType
    }
}

public enum CustomArchiveClientError: Error {
    case badURL
    case unauthorized
    case http(Int)
    case decoding
}

public final class CustomArchiveClient {
    private let baseURL: URL
    private let token: String
    private let session: URLSession
    // Media downloads are plain file transfers: they need a much longer budget
    // than the small JSON calls handled by `session`.
    private let mediaSession: URLSession

    public init?(serverURL: String, token: String) {
        var trimmed = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }
        guard !trimmed.isEmpty,
              let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http" else {
            return nil
        }
        self.baseURL = url
        self.token = token
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20.0
        configuration.timeoutIntervalForResource = 40.0
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: configuration)

        let mediaConfiguration = URLSessionConfiguration.ephemeral
        mediaConfiguration.timeoutIntervalForRequest = 60.0
        mediaConfiguration.timeoutIntervalForResource = 300.0
        mediaConfiguration.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.mediaSession = URLSession(configuration: mediaConfiguration)
    }

    public static func fromSettings() -> CustomArchiveClient? {
        guard CustomArchiveSettings.isConfigured else {
            return nil
        }
        return CustomArchiveClient(
            serverURL: CustomArchiveSettings.serverURL,
            token: CustomArchiveSettings.token
        )
    }

    private func request(path: String, query: [URLQueryItem]) -> URLRequest? {
        guard var components = URLComponents(
            url: self.baseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        ) else {
            return nil
        }
        var items = query
        items.append(URLQueryItem(name: "token", value: self.token))
        components.queryItems = items
        guard let url = components.url else {
            return nil
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(self.token)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func run(
        _ request: URLRequest,
        completion: @escaping (Result<Data, Error>) -> Void
    ) {
        let task = self.session.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let http = response as? HTTPURLResponse else {
                completion(.failure(CustomArchiveClientError.decoding))
                return
            }
            if http.statusCode == 401 {
                completion(.failure(CustomArchiveClientError.unauthorized))
                return
            }
            guard (200 ..< 300).contains(http.statusCode), let data = data else {
                completion(.failure(CustomArchiveClientError.http(http.statusCode)))
                return
            }
            completion(.success(data))
        }
        task.resume()
    }

    /// Absolute URL of one saved media file inside the archive API.
    public func mediaURL(relativePath: String) -> URL? {
        return self.request(path: "media/\(relativePath)", query: [])?.url
    }

    /// Downloads one archived media file (photo, video, document) into `destination`.
    ///
    /// `relativePath` is the `media_path` reported by the API; the token travels in
    /// the query string as well, so the file can also be fetched without headers.
    public func downloadMedia(
        relativePath: String,
        destination: URL,
        completion: @escaping (Result<Int64, Error>) -> Void
    ) {
        guard let url = self.mediaURL(relativePath: relativePath) else {
            completion(.failure(CustomArchiveClientError.badURL))
            return
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(self.token)", forHTTPHeaderField: "Authorization")
        let task = self.mediaSession.downloadTask(with: request) { location, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let http = response as? HTTPURLResponse else {
                completion(.failure(CustomArchiveClientError.decoding))
                return
            }
            if http.statusCode == 401 {
                completion(.failure(CustomArchiveClientError.unauthorized))
                return
            }
            guard (200 ..< 300).contains(http.statusCode), let location = location else {
                completion(.failure(CustomArchiveClientError.http(http.statusCode)))
                return
            }
            do {
                let fileManager = FileManager.default
                try fileManager.createDirectory(
                    at: destination.deletingLastPathComponent(),
                    withIntermediateDirectories: true,
                    attributes: nil
                )
                if fileManager.fileExists(atPath: destination.path) {
                    try fileManager.removeItem(at: destination)
                }
                try fileManager.moveItem(at: location, to: destination)
                let attributes = try fileManager.attributesOfItem(atPath: destination.path)
                let fileSize = (attributes[.size] as? NSNumber)?.int64Value ?? 0
                completion(.success(fileSize))
            } catch {
                completion(.failure(error))
            }
        }
        task.resume()
    }

    // One drain request: tells the archive which rows this device has fully
    // pulled into its local store, so rows nobody needs any more disappear and
    // the archive keeps only what no device has read back yet. A failure is
    // harmless: the rows simply stay in the archive and the next successful
    // sync offers them again.
    public func purgeDelivered(
        chatId: Int64,
        messageIds: [Int32],
        completion: @escaping (Bool) -> Void
    ) {
        guard !messageIds.isEmpty,
              let request = self.request(path: "chat/\(chatId)/purge", query: []) else {
            completion(false)
            return
        }
        var post = request
        post.httpMethod = "POST"
        post.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let ids = messageIds.map { String($0) }.joined(separator: ",")
        post.httpBody = Data("{\"message_ids\": [\(ids)]}".utf8)
        self.run(post) { result in
            switch result {
            case let .failure(error):
                CustomDebugConsole.log(
                    "archive purge failed chat=\(chatId) count=\(messageIds.count): \(error)"
                )
                completion(false)
            case .success:
                completion(true)
            }
        }
    }

    public func fetchMessageCount(completion: @escaping (Result<Int, Error>) -> Void) {
        guard let request = self.request(path: "health", query: []) else {
            completion(.failure(CustomArchiveClientError.badURL))
            return
        }
        self.run(request) { result in
            switch result {
            case let .failure(error):
                completion(.failure(error))
            case let .success(data):
                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let messages = json["messages"] as? Int else {
                    completion(.failure(CustomArchiveClientError.decoding))
                    return
                }
                completion(.success(messages))
            }
        }
    }

    public func fetchUpdates(
        chatId: Int64,
        after: Int,
        completion: @escaping (CustomArchiveUpdates?) -> Void
    ) {
        guard let request = self.request(
            path: "chat/\(chatId)/updates",
            query: [URLQueryItem(name: "after", value: String(after))]
        ) else {
            completion(nil)
            return
        }
        self.run(request) { result in
            switch result {
            case let .failure(error):
                CustomDebugConsole.log(
                    "archive updates request failed chat=\(chatId) after=\(after): \(error)"
                )
                completion(nil)
            case let .success(data):
                completion(CustomArchiveClient.decodeUpdates(data))
            }
        }
    }

    /// Lists the chats the archive holds messages for, newest activity first.
    /// The launch sync uses this to restore every chat without waiting for any
    /// of them to be opened.
    public func fetchChats(completion: @escaping ([CustomArchiveChat]?) -> Void) {
        guard let request = self.request(path: "chats", query: []) else {
            completion(nil)
            return
        }
        self.run(request) { result in
            switch result {
            case let .failure(error):
                CustomDebugConsole.log("archive chats request failed: \(error)")
                completion(nil)
            case let .success(data):
                completion(CustomArchiveClient.decodeChats(data))
            }
        }
    }

    private static func decodeInt64(_ value: Any?) -> Int64? {
        if let value = value as? Int64 {
            return value
        }
        if let value = value as? Int {
            return Int64(value)
        }
        if let value = value as? NSNumber {
            return value.int64Value
        }
        return nil
    }

    private static func decodeDate(_ value: Any?) -> Date? {
        guard let string = value as? String, !string.isEmpty else {
            return nil
        }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: string) {
            return date
        }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: string)
    }

    private static func decodeUpdates(_ data: Data) -> CustomArchiveUpdates? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let serverTime = json["server_time"] as? Int ?? Int(Date().timeIntervalSince1970)
        var deleted: [CustomArchiveDeletedMessage] = []
        if let rows = json["deleted"] as? [[String: Any]] {
            for row in rows {
                guard let messageId = row["message_id"] as? Int else {
                    continue
                }
                let senderId: Int64?
                if let value = row["sender_id"] as? Int {
                    senderId = Int64(value)
                } else if let value = row["sender_id"] as? Int64 {
                    senderId = value
                } else {
                    senderId = nil
                }
                deleted.append(
                    CustomArchiveDeletedMessage(
                        messageId: Int32(messageId),
                        senderId: senderId,
                        senderName: row["sender_name"] as? String,
                        date: CustomArchiveClient.decodeDate(row["date"]),
                        deletedAt: CustomArchiveClient.decodeDate(row["deleted_at"]),
                        text: row["text"] as? String,
                        direction: row["direction"] as? String,
                        mediaType: row["media_type"] as? String,
                        mediaPath: row["media_path"] as? String,
                        mediaSize: CustomArchiveClient.decodeInt64(row["media_size"]),
                        emoji: row["emoji"] as? String,
                        setName: row["set_name"] as? String
                    )
                )
            }
        }
        var edited: [CustomArchiveEditedMessage] = []
        if let rows = json["edited"] as? [[String: Any]] {
            for row in rows {
                guard let messageId = row["message_id"] as? Int else {
                    continue
                }
                edited.append(
                    CustomArchiveEditedMessage(
                        messageId: Int32(messageId),
                        oldText: row["old_text"] as? String,
                        newText: row["new_text"] as? String,
                        editedAt: CustomArchiveClient.decodeDate(row["edited_at"])
                    )
                )
            }
        }
        return CustomArchiveUpdates(serverTime: serverTime, deleted: deleted, edited: edited)
    }

    private static func decodeChats(_ data: Data) -> [CustomArchiveChat]? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rows = json["chats"] as? [[String: Any]] else {
            return nil
        }
        var chats: [CustomArchiveChat] = []
        for row in rows {
            guard let chatId = CustomArchiveClient.decodeInt64(row["chat_id"]) else {
                continue
            }
            chats.append(
                CustomArchiveChat(
                    chatId: chatId,
                    title: row["title"] as? String,
                    chatType: row["chat_type"] as? String
                )
            )
        }
        return chats
    }
}
