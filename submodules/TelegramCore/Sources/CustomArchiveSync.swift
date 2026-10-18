import Foundation
import Postbox
import CustomCore
import SwiftSignalKit

// Pulls deleted messages from the external archive API (see CustomCore)
// and restores them into the local message store as regular "deleted" messages,
// exactly like deletions observed live: the text survives, the bubble keeps its
// deleted mark, and the message stays in the chat.
//
// Saved media comes along: files are downloaded into the app's cache and turned
// into real Telegram media (see CustomArchiveMedia), so a restored photo is a
// photo bubble and a restored video plays, instead of the message being text-only.

// A restore runs while a chat is opening, so it will not pull arbitrarily large
// video files; anything bigger keeps the text and is reported to the log.
private let customArchiveMaxMediaBytes: Int64 = 25 * 1024 * 1024

// The archive stores non-user chats (groups, channels) under a negative id and
// reports them back offset by this mark, so they cannot be mistaken for a user
// id. Real Telegram user ids stay far below it.
private let customArchiveNonUserChatMark: Int64 = 1_000_000_000_000

// How many archive chats one launch sync covers. The list arrives newest
// activity first, so a long-unused chat simply syncs when it is opened.
private let customLaunchSyncMaxChats = 30

// Media that could not be fetched right now (network, timeout): the sync mark
// stays put so the next chat open tries again. Files that can never be used
// (too large, unreadable) are not listed here, so they do not cause churn.
private struct CustomArchiveMediaResult {
    let mediaByMessageId: [Int32: Media]
    let retryableMessageIds: Set<Int32>
}

// What one chat sync changed, and which edits it could not apply yet: an edit
// whose message is not on the device has to be retried, so the sync mark only
// moves forward once everything landed.
private struct CustomArchiveSyncOutcome {
    let changed: Int
    let unappliedEdits: Int
}

// The stored message with a new attribute and media set, every other property
// kept exactly as it was.
private func customArchiveUpdatedStoreMessage(
    _ current: Message,
    attributes: [MessageAttribute],
    media: [Media]
) -> StoreMessage {
    return StoreMessage(
        id: current.id,
        customStableId: nil,
        globallyUniqueId: current.globallyUniqueId,
        groupingKey: current.groupingKey,
        threadId: current.threadId,
        timestamp: current.timestamp,
        flags: StoreMessageFlags(current.flags),
        tags: current.tags,
        globalTags: current.globalTags,
        localTags: current.localTags,
        forwardInfo: current.forwardInfo.flatMap(StoreMessageForwardInfo.init),
        authorId: current.author?.id,
        text: current.text,
        attributes: attributes,
        media: media
    )
}

// The edit history of a message with the archive's edit events merged in: one
// entry per edit event holding the version that was replaced, oldest first,
// exactly like a live edit records it (see CustomEditHistoryAttribute).
// Returns nil when the history already knows every event.
private func customArchiveMergedEditHistory(
    base: CustomEditHistoryAttribute?,
    edits: [CustomArchiveEditedMessage]
) -> (originalText: String?, texts: [String], dates: [String])? {
    var texts = base?.editHistoryTexts ?? []
    var dates = base?.editHistoryDates ?? []
    var originalText = base?.originalText
    var added = false

    for edit in edits {
        guard let oldText = edit.oldText, !oldText.isEmpty else {
            continue
        }
        let dateText = String(Int32((edit.editedAt ?? Date()).timeIntervalSince1970))

        // The app records the same edit live when it was running, so an event
        // already in the history (same text, same moment) is skipped.
        var known = false
        if texts.count == dates.count {
            for i in 0 ..< texts.count {
                if texts[i] == oldText && dates[i] == dateText {
                    known = true
                    break
                }
            }
        }
        if known {
            continue
        }

        texts.append(oldText)
        dates.append(dateText)
        if originalText == nil {
            originalText = oldText
        }
        added = true
    }

    guard added else {
        return nil
    }
    if texts.count > 30 {
        texts = Array(texts.suffix(30))
        dates = Array(dates.suffix(30))
    }
    return (originalText, texts, dates)
}

public func customSyncArchivedMessages(
    accountPeerId: PeerId,
    peerId: PeerId,
    postbox: Postbox,
    completion: @escaping (Int) -> Void
) {
    guard let client = CustomArchiveClient.fromSettings() else {
        CustomDebugConsole.error("archive sync: client not configured")
        completion(0)
        return
    }

    // The archive API speaks raw Telegram ids, not packed PeerId values:
    // user ids no longer fitting 32 bits arrive distorted via toInt64(),
    // so the id is taken from the PeerId itself (namespace-free).
    let accountId = accountPeerId.id._internalGetInt64Value()
    let chatId = peerId.id._internalGetInt64Value()
    let after = CustomArchiveSettings.lastSync(accountPeerId: accountId, chatPeerId: chatId)
    CustomDebugConsole.log(
        "archive sync: chat=\(chatId) after=\(after)"
    )

    client.fetchUpdates(chatId: chatId, after: after) { updates in
        guard let updates = updates else {
            CustomDebugConsole.error(
                "archive sync: no response for chat=\(chatId)"
            )
            completion(0)
            return
        }

        guard !updates.deleted.isEmpty || !updates.edited.isEmpty else {
            CustomDebugConsole.log(
                "archive sync: chat=\(chatId) has nothing new"
            )
            CustomArchiveSettings.setLastSync(
                accountPeerId: accountId,
                chatPeerId: chatId,
                value: updates.serverTime
            )
            completion(0)
            return
        }

        CustomDebugConsole.log(
            "archive sync: chat=\(chatId) restoring \(updates.deleted.count) message(s), \(updates.edited.count) edit(s)"
        )

        // Edit events grouped per message, oldest first: the API answers newest
        // first, while the stored history lists the replaced versions in order.
        var editsByMessageId: [Int32: [CustomArchiveEditedMessage]] = [:]
        for edit in updates.edited.sorted(by: { lhs, rhs in
            (lhs.editedAt ?? Date.distantPast) < (rhs.editedAt ?? Date.distantPast)
        }) {
            editsByMessageId[edit.messageId, default: []].append(edit)
        }

        customDownloadArchivedMedia(
            client: client,
            chatId: chatId,
            items: updates.deleted
        ) { mediaResult in
            let mediaByMessageId = mediaResult.mediaByMessageId
            let _ = (postbox.transaction { transaction -> CustomArchiveSyncOutcome in
                var changed = 0
                var unappliedEdits = 0
                var pendingEdits = editsByMessageId

                for item in updates.deleted {
                    let messageId = MessageId(
                        peerId: peerId,
                        namespace: Namespaces.Message.Cloud,
                        id: item.messageId
                    )
                    let timestamp = Int32(
                        (item.date ?? Date()).timeIntervalSince1970
                    )
                    let deletedAt = Int32(
                        (item.deletedAt ?? item.date ?? Date()).timeIntervalSince1970
                    )
                    let text = item.text ?? ""
                    let archivedMedia = mediaByMessageId[item.messageId]
                    let archivedEdits = pendingEdits.removeValue(forKey: item.messageId) ?? []

                    if let existing = transaction.getMessage(messageId) {
                        // The message is already local (arrived before deletion):
                        // make sure it carries the deleted mark and the archived
                        // edit history, and give it the archived file when the
                        // device never kept one.
                        let existingAttr = existing.attributes.first(
                            where: { $0 is CustomEditHistoryAttribute }
                        ) as? CustomEditHistoryAttribute
                        let mergedEdits = customArchiveMergedEditHistory(
                            base: existingAttr,
                            edits: archivedEdits
                        )

                        var attributes = existing.attributes
                        var needsUpdate = false

                        if existingAttr?.isDeleted != true || mergedEdits != nil {
                            attributes.removeAll(where: { $0 is CustomEditHistoryAttribute })
                            attributes.append(CustomEditHistoryAttribute(
                                originalText: mergedEdits?.originalText
                                    ?? existingAttr?.originalText
                                    ?? (existing.text.isEmpty ? nil : existing.text),
                                editHistoryTexts: mergedEdits?.texts ?? existingAttr?.editHistoryTexts ?? [],
                                editHistoryDates: mergedEdits?.dates ?? existingAttr?.editHistoryDates ?? [],
                                isDeleted: true,
                                deletedAt: deletedAt,
                                originalEntities: existingAttr?.originalEntities ?? [],
                                editHistoryEntities: existingAttr?.editHistoryEntities ?? [],
                                editHistorySnapshots: existingAttr?.editHistorySnapshots ?? []
                            ))
                            needsUpdate = true
                        }

                        var media = existing.media
                        if media.isEmpty, let archivedMedia = archivedMedia {
                            media = [archivedMedia]
                            needsUpdate = true
                        } else if let archivedFile = archivedMedia as? TelegramMediaFile, archivedFile.isSticker,
                                  let existingFile = media.first as? TelegramMediaFile, existingFile.isSticker {
                            // An older build restored this sticker without its
                            // set reference: replace it with the archive's, so
                            // tapping opens the set like on any live sticker.
                            let hasPack: (TelegramMediaFile) -> Bool = { file in
                                file.attributes.contains {
                                    if case .Sticker(_, .some, _) = $0 {
                                        return true
                                    }
                                    return false
                                }
                            }
                            if !hasPack(existingFile) && hasPack(archivedFile) {
                                media = [archivedFile]
                                needsUpdate = true
                            }
                        }

                        if needsUpdate {
                            transaction.updateMessage(messageId, update: { current in
                                return .update(customArchiveUpdatedStoreMessage(
                                    current,
                                    attributes: attributes,
                                    media: media
                                ))
                            })
                            changed += 1
                        }
                    } else {
                        // The message never reached this device: recreate it from
                        // the archive with the text, the media and the deleted mark.
                        let incoming = item.direction != "outgoing"
                        var storeFlags = StoreMessageFlags()
                        if incoming {
                            storeFlags.insert(.Incoming)
                        }

                        // An edit made before the deletion is restored with it.
                        let mergedEdits = customArchiveMergedEditHistory(
                            base: nil,
                            edits: archivedEdits
                        )
                        let media: [Media] = archivedMedia.map { [$0] } ?? []
                        let attributes: [MessageAttribute] = [
                            CustomEditHistoryAttribute(
                                originalText: mergedEdits?.originalText
                                    ?? (text.isEmpty ? nil : text),
                                editHistoryTexts: mergedEdits?.texts ?? [],
                                editHistoryDates: mergedEdits?.dates ?? [],
                                isDeleted: true,
                                deletedAt: deletedAt
                            )
                        ]
                        let (tags, globalTags) = tagsForStoreMessage(
                            incoming: incoming,
                            attributes: attributes,
                            media: media,
                            textEntities: nil,
                            isPinned: false
                        )

                        let storeMessage = StoreMessage(
                            id: messageId,
                            customStableId: nil,
                            globallyUniqueId: nil,
                            groupingKey: nil,
                            threadId: nil,
                            timestamp: timestamp,
                            flags: storeFlags,
                            tags: tags,
                            globalTags: globalTags,
                            localTags: LocalMessageTags(),
                            forwardInfo: nil,
                            authorId: item.senderId.map { PeerId(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value($0)) },
                            text: text,
                            attributes: attributes,
                            media: media
                        )
                        let _ = transaction.addMessages([storeMessage], location: .Random)
                        changed += 1
                    }
                }

                // Edits of messages that were not deleted: attach the history to
                // whatever the device holds. A message that is not local yet (the
                // app may still be catching up with the server) keeps its sync
                // mark, so the next pass applies the edit instead of losing it.
                for (pendingMessageId, pendingEditEvents) in pendingEdits {
                    let id = MessageId(
                        peerId: peerId,
                        namespace: Namespaces.Message.Cloud,
                        id: pendingMessageId
                    )
                    guard let existing = transaction.getMessage(id) else {
                        unappliedEdits += 1
                        continue
                    }
                    let existingAttr = existing.attributes.first(
                        where: { $0 is CustomEditHistoryAttribute }
                    ) as? CustomEditHistoryAttribute
                    guard let mergedEdits = customArchiveMergedEditHistory(
                        base: existingAttr,
                        edits: pendingEditEvents
                    ) else {
                        continue
                    }

                    var attributes = existing.attributes
                    attributes.removeAll(where: { $0 is CustomEditHistoryAttribute })
                    attributes.append(CustomEditHistoryAttribute(
                        originalText: mergedEdits.originalText,
                        editHistoryTexts: mergedEdits.texts,
                        editHistoryDates: mergedEdits.dates,
                        isDeleted: existingAttr?.isDeleted ?? false,
                        deletedAt: existingAttr?.deletedAt ?? 0,
                        originalEntities: existingAttr?.originalEntities ?? [],
                        editHistoryEntities: existingAttr?.editHistoryEntities ?? [],
                        editHistorySnapshots: existingAttr?.editHistorySnapshots ?? []
                    ))
                    transaction.updateMessage(id, update: { current in
                        return .update(customArchiveUpdatedStoreMessage(
                            current,
                            attributes: attributes,
                            media: current.media
                        ))
                    })
                    changed += 1
                }

                return CustomArchiveSyncOutcome(
                    changed: changed,
                    unappliedEdits: unappliedEdits
                )
            }            |> deliverOnMainQueue).start(next: { outcome in
                CustomDebugConsole.log(
                    "archive sync: chat=\(chatId) restored \(outcome.changed) message(s)"
                )
                if !mediaResult.retryableMessageIds.isEmpty {
                    CustomDebugConsole.log(
                        "archive sync will retry media for \(mediaResult.retryableMessageIds.count) message(s)"
                    )
                }
                if outcome.unappliedEdits > 0 {
                    CustomDebugConsole.log(
                        "archive sync will retry \(outcome.unappliedEdits) edit(s) for chat=\(chatId)"
                    )
                }
                if mediaResult.retryableMessageIds.isEmpty && outcome.unappliedEdits == 0 {
                    CustomArchiveSettings.setLastSync(
                        accountPeerId: accountId,
                        chatPeerId: chatId,
                        value: updates.serverTime
                    )
                    // Fully delivered: everything is in the local store, so
                    // the archive rows have served their purpose. Dropping
                    // them keeps the archive a handover mailbox instead of an
                    // ever-growing store — the device retains everything
                    // (messages, media, edit history) locally forever. A
                    // failed drain just means the rows are re-offered after
                    // the next sync, which re-adds nothing and re-purges.
                    let deliveredIds = updates.deleted.map { $0.messageId }
                    if !deliveredIds.isEmpty {
                        client.purgeDelivered(chatId: chatId, messageIds: deliveredIds) { purged in
                            CustomDebugConsole.log(
                                "archive sync: chat=\(chatId) drained \(deliveredIds.count) row(s): \(purged ? "ok" : "deferred")"
                            )
                        }
                    }
                }
                completion(outcome.changed)
            })
        }
    }
}

// The same restore, but for every chat the archive knows about, run right after
// the app becomes usable. Opening a chat still syncs it on its own; this only
// means the deletions are usually back before the chat is opened at all.
//
// The chat list is asked of the archive itself, because the local database only
// knows what actually reached the device.
public func customSyncAllArchivedChats(
    accountPeerId: PeerId,
    postbox: Postbox,
    completion: @escaping (Int) -> Void
) {
    guard let client = CustomArchiveClient.fromSettings() else {
        CustomDebugConsole.error("archive launch sync: client not configured")
        completion(0)
        return
    }

    client.fetchChats { chats in
        guard let chats = chats else {
            CustomDebugConsole.error("archive launch sync: no chat list")
            completion(0)
            return
        }

        // The archive is fed by a Telegram Business connection, so its chats
        // are 1:1 conversations and their ids are CloudUser peers. Anything
        // else is skipped rather than restored into a made-up chat.
        var pending: [PeerId] = []
        var skipped = 0
        for chat in chats {
            if let chatType = chat.chatType, chatType != "private" {
                skipped += 1
                continue
            }
            if chat.chatId >= customArchiveNonUserChatMark || chat.chatId <= 0 {
                skipped += 1
                continue
            }
            pending.append(PeerId(
                namespace: Namespaces.Peer.CloudUser,
                id: PeerId.Id._internalFromInt64Value(chat.chatId)
            ))
        }

        if pending.count > customLaunchSyncMaxChats {
            pending = Array(pending.prefix(customLaunchSyncMaxChats))
        }

        CustomDebugConsole.log(
            "archive launch sync: \(pending.count) chat(s), \(skipped) skipped"
        )

        var restored = 0
        func step() {
            guard !pending.isEmpty else {
                CustomDebugConsole.log(
                    "archive launch sync: restored \(restored) message(s) in total"
                )
                completion(restored)
                return
            }
            let peerId = pending.removeFirst()
            customSyncArchivedMessages(
                accountPeerId: accountPeerId,
                peerId: peerId,
                postbox: postbox,
                completion: { changed in
                    restored += changed
                    step()
                }
            )
        }
        step()
    }
}

// Downloads the media of the given archive items one after another (the numbers
// here are small) and returns the ready media objects keyed by message id. Every
// failure is only logged: a message without its file is still worth restoring.
private func customDownloadArchivedMedia(
    client: CustomArchiveClient,
    chatId: Int64,
    items: [CustomArchiveDeletedMessage],
    completion: @escaping (CustomArchiveMediaResult) -> Void
) {
    var pending = items.filter { item in
        guard let path = item.mediaPath else {
            return false
        }
        return !path.isEmpty
    }
    var mediaByMessageId: [Int32: Media] = [:]
    var retryableMessageIds: Set<Int32> = []

    func step() {
        guard !pending.isEmpty else {
            completion(CustomArchiveMediaResult(
                mediaByMessageId: mediaByMessageId,
                retryableMessageIds: retryableMessageIds
            ))
            return
        }
        let item = pending.removeFirst()
        guard let relativePath = item.mediaPath, !relativePath.isEmpty else {
            step()
            return
        }
        if let expectedSize = item.mediaSize, expectedSize > customArchiveMaxMediaBytes {
            CustomDebugConsole.log(
                "archive media skipped id=\(item.messageId) bytes=\(expectedSize)"
            )
            step()
            return
        }

        let localFile = customArchiveMediaLocalFile(
            chatId: chatId,
            messageId: item.messageId,
            mediaType: item.mediaType,
            relativePath: relativePath
        )

        let cachedSize = customArchiveFileSize(localFile)
        if cachedSize > 0 {
            if let media = customArchiveMediaObject(
                mediaType: item.mediaType,
                relativePath: relativePath,
                localFile: localFile,
                byteSize: cachedSize,
                emoji: item.emoji,
                setName: item.setName
            ) {
                mediaByMessageId[item.messageId] = media
            } else {
                CustomDebugConsole.log(
                    "archive media unreadable id=\(item.messageId) type=\(item.mediaType ?? "?")"
                )
            }
            step()
            return
        }

        client.downloadMedia(relativePath: relativePath, destination: localFile) { result in
            switch result {
            case let .success(byteSize):
                // The size is also checked after the fact: older builds of the
                // archive API do not report it before the download.
                if byteSize > customArchiveMaxMediaBytes {
                    try? FileManager.default.removeItem(at: localFile)
                    CustomDebugConsole.log(
                        "archive media skipped after download id=\(item.messageId) bytes=\(byteSize)"
                    )
                    step()
                    return
                }
                if let media = customArchiveMediaObject(
                    mediaType: item.mediaType,
                    relativePath: relativePath,
                    localFile: localFile,
                    byteSize: byteSize,
                    emoji: item.emoji,
                    setName: item.setName
                ) {
                    mediaByMessageId[item.messageId] = media
                    CustomDebugConsole.log(
                        "archive media restored id=\(item.messageId) type=\(item.mediaType ?? "?") bytes=\(byteSize)"
                    )
                } else {
                    CustomDebugConsole.log(
                        "archive media unreadable id=\(item.messageId) type=\(item.mediaType ?? "?")"
                    )
                }
            case .failure(let error):
                retryableMessageIds.insert(item.messageId)
                CustomDebugConsole.log(
                    "archive media failed id=\(item.messageId): \(error)"
                )
            }
            step()
        }
    }

    step()
}
