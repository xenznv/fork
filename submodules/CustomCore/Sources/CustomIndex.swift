import Foundation

public struct CustomCanonicalLocator: Codable, Equatable {
    public let kind: CustomEventKind
    public let relativeFile: String
    public let eventId: CustomEventId

    public init(kind: CustomEventKind, relativeFile: String, eventId: CustomEventId) throws {
        guard !relativeFile.hasPrefix("/"), !relativeFile.split(separator: "/").contains("..") else {
            throw CustomCoreError.invalidRelativePath(relativeFile)
        }
        self.kind = kind
        self.relativeFile = relativeFile
        self.eventId = eventId
    }
}

public struct CustomTimeMachineIndexRecord: Codable, Equatable {
    public let accountPeerId: Int64
    public let chatPeerId: Int64
    public let eventId: CustomEventId
    public let sequence: Int64
    public let kind: CustomEventKind
    public let senderPeerId: Int64?
    public let observedAtMs: Int64
    public let byteOffset: UInt64
    public let byteLength: UInt64
    public let messageNamespace: Int32?
    public let messageId: Int32?
    public let locator: CustomCanonicalLocator

    public init(
        accountPeerId: Int64,
        chatPeerId: Int64,
        eventId: CustomEventId,
        sequence: Int64,
        kind: CustomEventKind,
        senderPeerId: Int64?,
        observedAtMs: Int64,
        byteOffset: UInt64 = 0,
        byteLength: UInt64 = 0,
        messageNamespace: Int32? = nil,
        messageId: Int32? = nil,
        locator: CustomCanonicalLocator
    ) {
        self.accountPeerId = accountPeerId
        self.chatPeerId = chatPeerId
        self.eventId = eventId
        self.sequence = sequence
        self.kind = kind
        self.senderPeerId = senderPeerId
        self.observedAtMs = observedAtMs
        self.byteOffset = byteOffset
        self.byteLength = byteLength
        self.messageNamespace = messageNamespace
        self.messageId = messageId
        self.locator = locator
    }
}
