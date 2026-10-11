import Foundation
import UIKit
import Display
import Postbox
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext
import AlertUI
import LegacyMediaPickerUI
import CustomCore

// "Database" screen: overview of the Custom capture database (deleted /
// edited message events, recovered media), a full-database wipe with an
// automatic export beforehand, and a human-readable HTML export of every
// captured event, grouped by chat (whole database or a single chat, with small
// media files embedded as base64 data URIs).

private func customDatabaseRootURL() -> URL {
    return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Custom", isDirectory: true)
}

private struct CustomDatabaseStats: Equatable {
    var eventCount: Int = 0
    var chatCount: Int = 0
    var mediaCount: Int = 0
    var mediaBytes: Int64 = 0
    var error: String? = nil
}

private func customDatabaseLoadStats(accountPeerId: Int64) -> CustomDatabaseStats {
    let store = CustomJSONLEventStore(rootURL: customDatabaseRootURL())
    do {
        let events = try store.events(accountPeerId: accountPeerId, chatPeerId: nil)
        var chatIds = Set<Int64>()
        var mediaCount = 0
        var mediaBytes: Int64 = 0
        for event in events {
            chatIds.insert(event.chatPeerId)
            if event.payload.mediaRelativePath != nil {
                mediaCount += 1
                mediaBytes += max(0, event.payload.mediaByteCount ?? 0)
            }
        }
        return CustomDatabaseStats(
            eventCount: events.count,
            chatCount: chatIds.count,
            mediaCount: mediaCount,
            mediaBytes: mediaBytes
        )
    } catch {
        return CustomDatabaseStats(error: String(describing: error))
    }
}

// MARK: - Readable HTML export

private struct CustomDatabaseChatGroup {
    let chatPeerId: Int64
    let title: String
    var events: [CustomCanonicalEvent]
}

private func customDatabaseEscapeHtml(_ source: String) -> String {
    var result = ""
    result.reserveCapacity(source.count)
    for character in source {
        switch character {
        case "&": result.append("&amp;")
        case "<": result.append("&lt;")
        case ">": result.append("&gt;")
        case "\"": result.append("&quot;")
        default: result.append(character)
        }
    }
    return result
}

private func customDatabaseExportFileDate(_ ms: Int64) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    formatter.timeZone = TimeZone.current
    return formatter.string(from: Date(timeIntervalSince1970: Double(ms) / 1000.0))
}

private func customDatabaseExportFileStamp(_ ms: Int64) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    formatter.timeZone = TimeZone.current
    return formatter.string(from: Date(timeIntervalSince1970: Double(ms) / 1000.0))
}

/// Turns a chat display name into a safe file name component: replaces
/// characters the Files app does not allow, trims whitespace and clamps
/// the length. Falls back to "chat" for empty names.
private func customDatabaseExportFileTitle(_ chatName: String) -> String {
    let invalidCharacters = "/\\?%*|\"<>:\n\r\t"
    var result = ""
    result.reserveCapacity(chatName.count)
    for character in chatName {
        if String(character).contains(where: { invalidCharacters.contains($0) }) {
            result.append(" ")
        } else {
            result.append(character)
        }
    }
    let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty {
        return "chat"
    }
    return trimmed.count > 60 ? String(trimmed.prefix(60)) : trimmed
}

private let customDatabaseMediaEmbedLimit: Int64 = 10 * 1024 * 1024

private func customDatabaseMediaMime(forExtension ext: String) -> String {
    switch ext {
    case "jpg", "jpeg": return "image/jpeg"
    case "png": return "image/png"
    case "gif": return "image/gif"
    case "heic", "heif": return "image/heic"
    case "webp": return "image/webp"
    case "bmp": return "image/bmp"
    case "tiff", "tif": return "image/tiff"
    case "mp4", "m4v", "mov": return "video/mp4"
    case "webm": return "video/webm"
    case "mp3": return "audio/mpeg"
    case "m4a": return "audio/mp4"
    case "wav": return "audio/wav"
    case "aac": return "audio/aac"
    case "ogg", "oga": return "audio/ogg"
    case "pdf": return "application/pdf"
    case "txt": return "text/plain"
    default: return "application/octet-stream"
    }
}

/// Reads a captured media file and renders it as an inline base64 data URI
/// (images, video, audio, pdf, small text files). Returns nil when the file is
/// missing, empty, over the size limit, or of an unsupported type.
private func customDatabaseMediaEmbedHtml(relativePath: String, byteCount: Int64?) -> String? {
    guard !relativePath.isEmpty else { return nil }
    let fileManager = FileManager.default
    let fileURL = customDatabaseRootURL().appendingPathComponent(relativePath)
    guard fileManager.fileExists(atPath: fileURL.path) else { return nil }

    let actualSize: Int64
    if let byteCount, byteCount > 0 {
        actualSize = byteCount
    } else {
        do {
            let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
            actualSize = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        } catch {
            return nil
        }
    }
    guard actualSize > 0, actualSize <= customDatabaseMediaEmbedLimit else { return nil }

    guard let data = try? Data(contentsOf: fileURL), !data.isEmpty else { return nil }
    let mime = customDatabaseMediaMime(forExtension: fileURL.pathExtension.lowercased())
    let base64 = data.base64EncodedString()
    switch mime {
    case let m where m.hasPrefix("image/"):
        return "<img class=\"media-embed\" src=\"data:\(m);base64,\(base64)\" alt=\"media\">"
    case let m where m.hasPrefix("video/"):
        return "<video class=\"media-embed\" src=\"data:\(m);base64,\(base64)\" controls preload=\"metadata\"></video>"
    case let m where m.hasPrefix("audio/"):
        return "<audio class=\"media-embed\" src=\"data:\(m);base64,\(base64)\" controls preload=\"metadata\"></audio>"
    case "application/pdf":
        return "<object class=\"media-embed\" type=\"application/pdf\" data=\"data:application/pdf;base64,\(base64)\"></object>"
    default:
        let name = customDatabaseEscapeHtml(fileURL.lastPathComponent)
        return "<a class=\"media-file\" href=\"data:\(mime);base64,\(base64)\" download=\"\(name)\">\(name)</a>"
    }
}

private func customDatabaseKindBadge(_ kind: CustomEventKind) -> String {
    switch kind {
    case .deletedMessage:
        return "🗑 Deleted"
    case .deletedReply:
        return "↩ Deleted Reply"
    case .editedMessage:
        return "✏️ Edited"
    case .recoveredMedia:
        return "🖼 Media"
    case .profileSnapshot:
        return "👤 Profile"
    case .presence:
        return "🟢 Presence"
    case .gift:
        return "🎁 Gift"
    case .personalChannel:
        return "📢 Channel"
    }
}

private func customDatabaseEventHtml(_ event: CustomCanonicalEvent) -> String {
    var lines: [String] = []
    let badge = customDatabaseKindBadge(event.kind)
    let when = customDatabaseExportFileDate(event.observedAtMs)
    lines.append("<div class=\"event kind-\(event.kind.rawValue)\">")
    lines.append("<div class=\"event-head\"><span class=\"badge\">\(badge)</span><span class=\"time\">\(when)</span>")
    if let messageId = event.messageId {
        lines.append("<span class=\"msgid\">msg #\(messageId)</span>")
    }
    lines.append("</div>")
    if let previousText = event.payload.previousText, !previousText.isEmpty {
        lines.append("<div class=\"label\">Before</div>")
        lines.append("<blockquote class=\"before\">\(customDatabaseEscapeHtml(previousText))</blockquote>")
    }
    if let text = event.payload.text, !text.isEmpty {
        lines.append("<div class=\"label\">\(event.payload.previousText != nil ? "After" : "Content")</div>")
        lines.append("<p class=\"content\">\(customDatabaseEscapeHtml(text))</p>")
    } else if event.payload.previousText == nil && event.payload.mediaRelativePath == nil {
        lines.append("<p class=\"content muted\">—</p>")
    }
    var mediaEmbed: String? = nil
    if let relativePath = event.payload.mediaRelativePath, !relativePath.isEmpty {
        mediaEmbed = customDatabaseMediaEmbedHtml(relativePath: relativePath, byteCount: event.payload.mediaByteCount)
    }
    if let embed = mediaEmbed {
        lines.append(embed)
    }
    if let mediaKind = event.payload.mediaKind, !mediaKind.isEmpty {
        var mediaLine = mediaKind
        if let byteCount = event.payload.mediaByteCount, byteCount > 0 {
            mediaLine += String(format: " · %.1f MB", Double(byteCount) / (1024.0 * 1024.0))
        }
        if event.payload.mediaRelativePath != nil {
            mediaLine += mediaEmbed != nil ? " (embedded in this file)" : " (attached in archive)"
        }
        lines.append("<p class=\"media\">\(customDatabaseEscapeHtml(mediaLine))</p>")
    } else if event.payload.mediaRelativePath != nil && mediaEmbed == nil {
        lines.append("<p class=\"media\">Media saved in archive (not embedded)</p>")
    }
    if !event.payload.metadata.isEmpty {
        let items = event.payload.metadata.keys.sorted().map { key in
            "\(customDatabaseEscapeHtml(key)): \(customDatabaseEscapeHtml(event.payload.metadata[key] ?? ""))"
        }
        lines.append("<p class=\"meta\">\(items.joined(separator: " · "))</p>")
    }
    lines.append("</div>")
    return lines.joined(separator: "\n")
}

private func customDatabaseRenderHtml(
    groups: [CustomDatabaseChatGroup],
    accountPeerId: Int64,
    generatedAtMs: Int64
) -> String {
    let totalEvents = groups.reduce(0) { $0 + $1.events.count }
    let pageTitle = groups.count == 1 ? "Экспорт чата" : "Экспорт базы"
    var html: [String] = []
    html.append("""
<!DOCTYPE html>
<html lang="ru">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Custom Export \(customDatabaseExportFileStamp(generatedAtMs))</title>
<style>
:root { color-scheme: light dark; }
body { font-family: -apple-system, "Segoe UI", Roboto, sans-serif; margin: 0; background: #f2f4f7; color: #1c1e21; }
header { padding: 20px; background: #2c3e50; color: #fff; }
header h1 { margin: 0 0 6px; font-size: 20px; }
header p { margin: 0; opacity: 0.85; font-size: 13px; }
main { max-width: 720px; margin: 0 auto; padding: 16px; }
section.chat { background: #fff; border-radius: 12px; margin: 14px 0; padding: 14px 16px; box-shadow: 0 1px 3px rgba(0,0,0,0.08); }
section.chat h2 { margin: 0 0 4px; font-size: 16px; }
section.chat .sub { font-size: 12px; color: #65676b; margin-bottom: 10px; }
.event { border-top: 1px solid #e4e6eb; padding: 10px 0; }
.event-head { display: flex; gap: 8px; align-items: baseline; flex-wrap: wrap; font-size: 12px; color: #65676b; }
.badge { font-weight: 600; color: #2c3e50; }
.time { font-variant-numeric: tabular-nums; }
.msgid { opacity: 0.7; }
.label { font-size: 11px; text-transform: uppercase; letter-spacing: 0.04em; color: #8a8d91; margin-top: 6px; }
blockquote.before { margin: 4px 0 0; padding: 6px 10px; border-left: 3px solid #e74c3c; background: rgba(231,76,60,0.06); border-radius: 4px; white-space: pre-wrap; word-break: break-word; }
p.content { margin: 4px 0 0; padding: 6px 10px; background: rgba(44,62,80,0.05); border-radius: 6px; white-space: pre-wrap; word-break: break-word; }
p.media { margin: 4px 0 0; font-size: 13px; color: #2980b9; }
img.media-embed, video.media-embed, object.media-embed { display: block; max-width: 100%; max-height: 420px; margin: 8px 0 2px; border-radius: 8px; background: rgba(0,0,0,0.04); }
audio.media-embed { display: block; width: 100%; max-width: 420px; margin: 8px 0 2px; }
a.media-file { display: inline-block; margin: 4px 0 0; font-size: 13px; color: #2980b9; word-break: break-all; }
p.meta { margin: 4px 0 0; font-size: 11px; color: #8a8d91; word-break: break-all; }
.muted { color: #b0b3b8; }
@media (prefers-color-scheme: dark) {
  body { background: #18191a; color: #e4e6eb; }
  section.chat { background: #242526; }
  .event { border-top-color: #3a3b3c; }
  .badge { color: #b0b3b8; }
  p.content { background: rgba(255,255,255,0.05); }
}
</style>
</head>
<body>
<header>
<h1>\(pageTitle)</h1>
<p>Аккаунт ID \(accountPeerId) · \(totalEvents) событий · создано \(customDatabaseExportFileDate(generatedAtMs))</p>
<p>Файл содержит захваченные удалённые сообщения, правки и восстановленные медиа. Локальные данные, не отправлялись в Telegram.</p>
</header>
<main>
""")
    if groups.isEmpty {
        html.append("<section class=\"chat\"><p class=\"content muted\">База пуста.</p></section>")
    }
    for group in groups {
        html.append("<section class=\"chat\">")
        html.append("<h2>\(customDatabaseEscapeHtml(group.title))</h2>")
        html.append("<div class=\"sub\">ID \(group.chatPeerId) · \(group.events.count) событий</div>")
        for event in group.events {
            html.append(customDatabaseEventHtml(event))
        }
        html.append("</section>")
    }
    html.append("</main>\n</body>\n</html>")
    return html.joined(separator: "\n")
}

/// Writes a human-readable HTML export and returns the file URL.
/// When chatPeerId is provided, only that chat's events are exported.
private func customDatabaseWriteReadableExport(accountPeerId: Int64, context: AccountContext, chatPeerId: Int64? = nil) throws -> URL {
    let store = CustomJSONLEventStore(rootURL: customDatabaseRootURL())
    let events = try store.events(accountPeerId: accountPeerId, chatPeerId: chatPeerId)

    // Group by chat; newest event first inside each chat, chats ordered by their newest event.
    let now = Int64(Date().timeIntervalSince1970 * 1000.0)
    var grouped: [Int64: [CustomCanonicalEvent]] = [:]
    for event in events {
        grouped[event.chatPeerId, default: []].append(event)
    }

    var names: [Int64: String] = [:]
    let peerIds = grouped.keys.map { PeerId($0) }
    if !peerIds.isEmpty {
        names = CustomDatabasePeerNameResolver.resolve(
            context: context,
            peerIds: peerIds
        )
    }

    let groups: [CustomDatabaseChatGroup] = grouped.map { chatPeerId, chatEvents in
        CustomDatabaseChatGroup(
            chatPeerId: chatPeerId,
            title: names[chatPeerId] ?? "Chat \(chatPeerId)",
            events: chatEvents.sorted { $0.observedAtMs > $1.observedAtMs }
        )
    }.sorted { lhs, rhs in
        let lhsLatest = lhs.events.first?.observedAtMs ?? 0
        let rhsLatest = rhs.events.first?.observedAtMs ?? 0
        return lhsLatest > rhsLatest
    }

    let html = customDatabaseRenderHtml(groups: groups, accountPeerId: accountPeerId, generatedAtMs: now)
    // Single-chat exports are named after the chat so files are easy to tell
    // apart in the Files app; whole-database exports keep a timestamp.
    let fileTitle: String
    if groups.count == 1, let chat = groups.first {
        fileTitle = customDatabaseExportFileTitle(chat.title)
    } else {
        fileTitle = "export-all-\(customDatabaseExportFileStamp(now))"
    }
    let fileURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("Custom-\(fileTitle).html")
    try html.data(using: .utf8)?.write(to: fileURL, options: .atomic)
    return fileURL
}

// MARK: - Peer name resolution

private enum CustomDatabasePeerNameResolver {
    static func resolve(context: AccountContext, peerIds: [PeerId]) -> [Int64: String] {
        var resolved: [Int64: String] = [:]
        let semaphore = DispatchSemaphore(value: 0)
        _ = context.account.postbox.transaction { transaction -> Void in
            for peerId in peerIds {
                if let peer = transaction.getPeer(peerId) {
                    let title = peer.debugDisplayTitle
                    if !title.isEmpty {
                        resolved[peerId.toInt64()] = title
                    }
                }
            }
        }.start(next: { _ in
            semaphore.signal()
        }, completed: {
            semaphore.signal()
        })
        _ = semaphore.wait(timeout: .now() + 3.0)
        return resolved
    }
}

// MARK: - Controller

private final class CustomDatabaseArguments {
    let exportReadable: () -> Void
    let exportOneChat: () -> Void
    let exportArchiveFirst: () -> Void
    let clearDatabase: () -> Void

    init(
        exportReadable: @escaping () -> Void,
        exportOneChat: @escaping () -> Void,
        exportArchiveFirst: @escaping () -> Void,
        clearDatabase: @escaping () -> Void
    ) {
        self.exportReadable = exportReadable
        self.exportOneChat = exportOneChat
        self.exportArchiveFirst = exportArchiveFirst
        self.clearDatabase = clearDatabase
    }
}

private enum CustomDatabaseEntry: ItemListNodeEntry {
    case header(Int32, String)
    case stat(Int32, Int32, String, String)
    case action(Int32, Int32, String, String)
    case info(Int32, String)

    var section: ItemListSectionId {
        switch self {
        case let .header(section, _), let .stat(section, _, _, _), let .action(section, _, _, _), let .info(section, _):
            return section
        }
    }

    var stableId: Int32 {
        switch self {
        case let .header(section, _): return section * 1000
        case let .stat(section, index, _, _): return section * 1000 + index
        case let .action(section, index, _, _): return section * 1000 + index
        case let .info(section, _): return section * 1000 + 999
        }
    }

    static func == (lhs: CustomDatabaseEntry, rhs: CustomDatabaseEntry) -> Bool {
        switch (lhs, rhs) {
        case let (.header(a, b), .header(c, d)):
            return a == c && b == d
        case let (.stat(a, b, c, d), .stat(e, f, g, h)):
            return a == e && b == f && c == g && d == h
        case let (.action(a, b, c, d), .action(e, f, g, h)):
            return a == e && b == f && c == g && d == h
        case let (.info(a, b), .info(c, d)):
            return a == c && b == d
        default:
            return false
        }
    }

    static func < (lhs: CustomDatabaseEntry, rhs: CustomDatabaseEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! CustomDatabaseArguments
        switch self {
        case let .header(_, title):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: title, sectionId: self.section)
        case let .stat(_, _, title, value):
            return ItemListDisclosureItem(
                presentationData: presentationData, systemStyle: .glass,
                title: title, label: value, labelStyle: .text,
                sectionId: self.section, style: .blocks,
                disclosureStyle: .none, action: nil
            )
        case let .action(_, _, title, action):
            return ItemListActionItem(
                presentationData: presentationData, title: title,
                kind: action == "clear" ? .destructive : .generic, alignment: .center,
                sectionId: self.section, style: .blocks,
                action: {
                    switch action {
                    case "clear":
                        arguments.clearDatabase()
                    case "exportArchive":
                        arguments.exportArchiveFirst()
                    case "exportOneChat":
                        arguments.exportOneChat()
                    default:
                        arguments.exportReadable()
                    }
                }
            )
        case let .info(_, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

public func customDatabaseController(context: AccountContext) -> ViewController {
    let accountPeerId = context.account.peerId.toInt64()

    let initialStats = customDatabaseLoadStats(accountPeerId: accountPeerId)
    let statsPromise = ValuePromise(initialStats, ignoreRepeated: true)
    let clearedAlertShown = Atomic(value: false)

    var controller: ItemListController?

    func refreshStats() {
        Queue.concurrentDefaultQueue().async {
            let stats = customDatabaseLoadStats(accountPeerId: accountPeerId)
            statsPromise.set(stats)
        }
    }

    func presentDone(_ text: String) {
        Queue.mainQueue().async {
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            let alert = textAlertController(
                context: context,
                title: presentationData.strings.custom.databaseTitle,
                text: text,
                actions: [
                    TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})
                ]
            )
            controller?.present(alert, in: .window(.root), with: nil)
        }
    }

    func presentError(_ error: Error) {
        Queue.mainQueue().async {
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            let alert = textAlertController(
                context: context,
                title: presentationData.strings.custom.databaseError,
                text: String(describing: error),
                actions: [
                    TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})
                ]
            )
            controller?.present(alert, in: .window(.root), with: nil)
        }
    }

    func presentReadableExport() {
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        Queue.concurrentDefaultQueue().async {
            do {
                CustomCaptureRecorder.flushSynchronously()
                let fileURL = try customDatabaseWriteReadableExport(accountPeerId: accountPeerId, context: context)
                Queue.mainQueue().async {
                    let picker = legacyICloudFilePicker(
                        theme: presentationData.theme,
                        mode: .export,
                        url: fileURL,
                        documentTypes: [],
                        dismissed: {
                            try? FileManager.default.removeItem(at: fileURL)
                        },
                        completion: { _ in
                            try? FileManager.default.removeItem(at: fileURL)
                        }
                    )
                    controller?.present(picker, in: .window(.root), with: nil)
                }
            } catch {
                presentError(error)
            }
        }
    }

    func presentNoEventsForChat() {
        Queue.mainQueue().async {
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            let alert = textAlertController(
                context: context,
                title: presentationData.strings.custom.databaseExportOneChatTitle,
                text: presentationData.strings.custom.databaseNoEventsForChat,
                actions: [
                    TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})
                ]
            )
            controller?.present(alert, in: .window(.root), with: nil)
        }
    }

    func presentOneChatExport() {
        Queue.mainQueue().async {
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            let picker = context.sharedContext.makePeerSelectionController(
                PeerSelectionControllerParams(
                    context: context,
                    filter: [.removeSearchHeader, .excludeRecent, .doNotSearchMessages],
                    title: presentationData.strings.custom.databaseExportChooseChat
                )
            )
            picker.peerSelected = { [weak picker, weak controller] peer, _ in
                guard let strongController = controller else { return }
                let chatPeerId = peer.id.toInt64()
                picker?.dismiss()
                Queue.concurrentDefaultQueue().async {
                    do {
                        CustomCaptureRecorder.flushSynchronously()
                        let store = CustomJSONLEventStore(rootURL: customDatabaseRootURL())
                        let chatEvents = try store.events(accountPeerId: accountPeerId, chatPeerId: chatPeerId)
                        if chatEvents.isEmpty {
                            presentNoEventsForChat()
                            return
                        }
                        let fileURL = try customDatabaseWriteReadableExport(
                            accountPeerId: accountPeerId,
                            context: context,
                            chatPeerId: chatPeerId
                        )
                        Queue.mainQueue().async {
                            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
                            let exportPicker = legacyICloudFilePicker(
                                theme: presentationData.theme,
                                mode: .export,
                                url: fileURL,
                                documentTypes: [],
                                dismissed: {
                                    try? FileManager.default.removeItem(at: fileURL)
                                },
                                completion: { _ in
                                    try? FileManager.default.removeItem(at: fileURL)
                                }
                            )
                            strongController.present(exportPicker, in: .window(.root), with: nil)
                        }
                    } catch {
                        presentError(error)
                    }
                }
            }
            controller?.push(picker)
        }
    }

    func exportThenClear() {
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        Queue.concurrentDefaultQueue().async {
            do {
                CustomCaptureRecorder.flushSynchronously()
                let fileURL = try customDatabaseWriteReadableExport(accountPeerId: accountPeerId, context: context)

                let store = CustomJSONLEventStore(rootURL: customDatabaseRootURL())
                let events = try store.events(accountPeerId: accountPeerId, chatPeerId: nil)
                let plan = CustomRetentionEngine.wipePlan(events: events)
                try CustomRetentionEngine.applyCleanup(
                    accountPeerId: accountPeerId,
                    originalEvents: events,
                    plan: plan,
                    mediaRootURL: customDatabaseRootURL(),
                    eventStore: store
                )

                Queue.mainQueue().async {
                    let showCleared = {
                        var alreadyShown = false
                        let _ = clearedAlertShown.modify { value in
                            alreadyShown = value
                            return true
                        }
                        if !alreadyShown {
                            presentDone(presentationData.strings.custom.databaseCleared)
                        }
                    }
                    let picker = legacyICloudFilePicker(
                        theme: presentationData.theme,
                        mode: .export,
                        url: fileURL,
                        documentTypes: [],
                        dismissed: {
                            try? FileManager.default.removeItem(at: fileURL)
                            Queue.mainQueue().async {
                                showCleared()
                            }
                        },
                        completion: { _ in
                            try? FileManager.default.removeItem(at: fileURL)
                            Queue.mainQueue().async {
                                showCleared()
                            }
                        }
                    )
                    controller?.present(picker, in: .window(.root), with: nil)
                    refreshStats()
                }
            } catch {
                presentError(error)
            }
        }
    }

    func confirmClear() {
        Queue.mainQueue().async {
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            let alert = textAlertController(
                context: context,
                title: presentationData.strings.custom.databaseClearConfirmTitle,
                text: presentationData.strings.custom.databaseClearConfirmText,
                actions: [
                    TextAlertAction(type: .destructiveAction, title: presentationData.strings.custom.databaseClearConfirmYes, action: {
                        exportThenClear()
                    }),
                    TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_Cancel, action: {})
                ]
            )
            controller?.present(alert, in: .window(.root), with: nil)
        }
    }

    let arguments = CustomDatabaseArguments(
        exportReadable: {
            presentReadableExport()
        },
        exportOneChat: {
            presentOneChatExport()
        },
        exportArchiveFirst: {
            confirmClear()
        },
        clearDatabase: {
            confirmClear()
        }
    )

    let signal = combineLatest(context.sharedContext.presentationData, statsPromise.get())
        |> deliverOnMainQueue
        |> map { presentationData, stats -> (ItemListControllerState, (ItemListNodeState, Any)) in
            let strings = presentationData.strings.custom
            var entries: [CustomDatabaseEntry] = [
                .header(0, strings.databaseTitle),
                .stat(0, 1, strings.databaseStatEvents, "\(stats.eventCount)"),
                .stat(0, 2, strings.databaseStatChats, "\(stats.chatCount)"),
                .stat(0, 3, strings.databaseStatMedia, stats.error == nil ? "\(stats.mediaCount)" : "—"),
            ]
            if let error = stats.error {
                entries.append(.info(0, error))
            }
            entries.append(contentsOf: [
                .header(1, strings.databaseExportTitle),
                .action(1, 1, strings.databaseExportReadable, "exportReadable"),
                .action(1, 2, strings.databaseExportOneChatTitle, "exportOneChat"),
                .action(1, 3, strings.databaseClearExportFirst, "exportArchive"),
                .info(1, strings.databaseExportHint),
                .header(2, strings.databaseClearTitle),
                .action(2, 1, strings.databaseClearAction, "clear"),
                .info(2, strings.databaseClearHint),
            ])
            return (
                ItemListControllerState(
                    presentationData: ItemListPresentationData(presentationData),
                    title: .text(strings.databaseTitle),
                    leftNavigationButton: nil, rightNavigationButton: nil,
                    backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
                ),
                (ItemListNodeState(
                    presentationData: ItemListPresentationData(presentationData),
                    entries: entries, style: .blocks, animateChanges: false
                ), arguments as Any)
            )
        }
    controller = ItemListController(context: context, state: signal)
    return controller!
}
