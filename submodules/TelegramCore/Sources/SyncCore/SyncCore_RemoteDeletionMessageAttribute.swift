import Foundation
import Postbox

/// A message the server deleted while this account keeps its copy: the message stays where it is,
/// with its content, and this attribute marks it so that the chat can show it differently.
public class RemoteDeletionMessageAttribute: MessageAttribute {
    /// When the deletion was received, in seconds since 1970.
    public let deletionTimestamp: Int32

    public var associatedMessageIds: [MessageId] = []

    public init(deletionTimestamp: Int32) {
        self.deletionTimestamp = deletionTimestamp
    }

    required public init(decoder: PostboxDecoder) {
        self.deletionTimestamp = decoder.decodeInt32ForKey("t", orElse: 0)
    }

    public func encode(_ encoder: PostboxEncoder) {
        encoder.encodeInt32(self.deletionTimestamp, forKey: "t")
    }
}

public extension Message {
    var remoteDeletionAttribute: RemoteDeletionMessageAttribute? {
        for attribute in self.attributes {
            if let attribute = attribute as? RemoteDeletionMessageAttribute {
                return attribute
            }
        }
        return nil
    }
}
