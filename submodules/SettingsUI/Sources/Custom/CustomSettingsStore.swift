import Foundation

public enum CustomSendStyleV1: String, Codable, CaseIterable {
    case normal
    case bold
    case italic
    case monospace
    case strikethrough
    case underline
    case spoiler
}

public struct CustomSettingsV1: Codable, Equatable {
    public var schemaVersion: Int = 1
    public var sendStyle: CustomSendStyleV1
    public var saveDeletedMessages: Bool
    public var saveEditHistory: Bool
    public var portableDeletedReplies: Bool
    public var preserveDeletedMedia: Bool

    public init(
        sendStyle: CustomSendStyleV1 = .normal,
        saveDeletedMessages: Bool = false,
        saveEditHistory: Bool = false,
        portableDeletedReplies: Bool = false,
        preserveDeletedMedia: Bool = false
    ) {
        self.sendStyle = sendStyle
        self.saveDeletedMessages = saveDeletedMessages
        self.saveEditHistory = saveEditHistory
        self.portableDeletedReplies = portableDeletedReplies
        self.preserveDeletedMedia = preserveDeletedMedia
    }
}

public enum CustomSettingsStoreError: Error, Equatable {
    case unsupportedSchemaVersion(Int)
}

public final class CustomSettingsStore {
    private let fileURL: URL
    private let decoder = JSONDecoder()

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func load() throws -> CustomSettingsV1 {
        guard FileManager.default.fileExists(atPath: self.fileURL.path) else {
            return CustomSettingsV1()
        }
        let value = try self.decoder.decode(
            CustomSettingsV1.self,
            from: Data(contentsOf: self.fileURL)
        )
        guard value.schemaVersion == 1 else {
            throw CustomSettingsStoreError.unsupportedSchemaVersion(value.schemaVersion)
        }
        return value
    }

    public func save(_ value: CustomSettingsV1) throws {
        guard value.schemaVersion == 1 else {
            throw CustomSettingsStoreError.unsupportedSchemaVersion(value.schemaVersion)
        }
        try FileManager.default.createDirectory(
            at: self.fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = JSONEncoder.OutputFormatting.sortedKeys
        try encoder.encode(value).write(to: self.fileURL, options: .atomic)
    }
}
