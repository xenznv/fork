import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import AccountContext
import ItemListUI
import PresentationDataUtils
import Postbox
import TextFormat

private final class ChatMessageHistoryArguments {
    let dismiss: () -> Void

    init(dismiss: @escaping () -> Void) {
        self.dismiss = dismiss
    }
}

private enum ChatMessageHistoryEntry: ItemListNodeEntry {
    case version(index: Int, kind: MessageArchiveKind, label: String, text: String)
    case empty(text: String)

    var section: ItemListSectionId {
        switch self {
        case let .version(index, _, _, _):
            return Int32(index)
        case .empty:
            return 0
        }
    }

    var stableId: Int32 {
        switch self {
        case let .version(index, _, _, _):
            return Int32(index)
        case .empty:
            return 0
        }
    }

    static func ==(lhs: ChatMessageHistoryEntry, rhs: ChatMessageHistoryEntry) -> Bool {
        switch lhs {
        case let .version(lhsIndex, lhsKind, lhsLabel, lhsText):
            if case let .version(rhsIndex, rhsKind, rhsLabel, rhsText) = rhs, lhsIndex == rhsIndex, lhsKind == rhsKind, lhsLabel == rhsLabel, lhsText == rhsText {
                return true
            }
            return false
        case let .empty(lhsText):
            if case let .empty(rhsText) = rhs, lhsText == rhsText {
                return true
            }
            return false
        }
    }

    static func <(lhs: ChatMessageHistoryEntry, rhs: ChatMessageHistoryEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        switch self {
        case let .version(_, _, label, text):
            return ItemListTextWithLabelItem(presentationData: presentationData, label: label, text: text, style: .blocks, enabledEntityTypes: [], multiline: true, sectionId: self.section, action: nil)
        case let .empty(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

private func chatMessageHistoryEntries(presentationData: PresentationData, versions: [ArchivedMessageVersion]) -> [ChatMessageHistoryEntry] {
    if versions.isEmpty {
        return [.empty(text: presentationData.strings.Chat_History_Empty)]
    }

    var entries: [ChatMessageHistoryEntry] = []
    // The most recent version goes first: it is the one the user is most likely looking for.
    for (index, version) in versions.reversed().enumerated() {
        let kindText: String
        switch version.kind {
        case .deleted:
            kindText = presentationData.strings.Chat_History_Deleted
        case .editedVersion:
            kindText = presentationData.strings.Chat_History_Edited
        }
        let dateText = stringForShortDate(timestamp: version.captureTimestamp, strings: presentationData.strings, dateTimeFormat: presentationData.dateTimeFormat)

        var text = version.message.text
        if text.isEmpty {
            if !version.message.media.isEmpty {
                text = presentationData.strings.Chat_History_Media
            } else {
                text = "\u{2014}"
            }
        }

        entries.append(.version(index: index, kind: version.kind, label: "\(kindText) \u{00b7} \(dateText)", text: text))
    }
    return entries
}

func chatMessageHistoryController(context: AccountContext, messageId: MessageId) -> ViewController {
    var dismissImpl: (() -> Void)?

    let arguments = ChatMessageHistoryArguments(dismiss: {
        dismissImpl?()
    })

    let signal = combineLatest(
        context.sharedContext.presentationData,
        context.account.postbox.transaction { transaction -> [ArchivedMessageVersion] in
            return transaction.archivedMessageVersions(messageId)
        }
    )
    |> deliverOnMainQueue
    |> map { value -> (ItemListControllerState, (ItemListNodeState, ChatMessageHistoryArguments)) in
        let (presentationData, versions) = value
        let listPresentationData = ItemListPresentationData(presentationData)

        let leftNavigationButton = ItemListNavigationButton(content: .text(presentationData.strings.Common_Done), style: .bold, enabled: true, action: {
            arguments.dismiss()
        })
        let controllerState = ItemListControllerState(presentationData: listPresentationData, title: .text(presentationData.strings.Chat_History_Title), leftNavigationButton: leftNavigationButton, rightNavigationButton: nil, backNavigationButton: nil)
        let listState = ItemListNodeState(presentationData: listPresentationData, entries: chatMessageHistoryEntries(presentationData: presentationData, versions: versions), style: .blocks, animateChanges: false)

        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    dismissImpl = { [weak controller] in
        controller?.dismiss()
    }
    return controller
}
