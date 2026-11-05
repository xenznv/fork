import Foundation
import UIKit
import Display
import SwiftSignalKit
import Postbox
import TelegramCore
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext

private final class MessageArchiveExportSettingsControllerState: Equatable {
    let endpoint: String
    let token: String
    let saved: Bool

    init(endpoint: String, token: String, saved: Bool) {
        self.endpoint = endpoint
        self.token = token
        self.saved = saved
    }

    static func ==(lhs: MessageArchiveExportSettingsControllerState, rhs: MessageArchiveExportSettingsControllerState) -> Bool {
        if lhs.endpoint != rhs.endpoint {
            return false
        }
        if lhs.token != rhs.token {
            return false
        }
        if lhs.saved != rhs.saved {
            return false
        }
        return true
    }
}

private final class MessageArchiveExportSettingsArguments {
    let context: AccountContext
    let updateEndpoint: (String) -> Void
    let updateToken: (String) -> Void
    let save: () -> Void
    let disposable = MetaDisposable()

    init(context: AccountContext, updateEndpoint: @escaping (String) -> Void, updateToken: @escaping (String) -> Void, save: @escaping () -> Void) {
        self.context = context
        self.updateEndpoint = updateEndpoint
        self.updateToken = updateToken
        self.save = save
    }

    deinit {
        self.disposable.dispose()
    }
}

private enum MessageArchiveExportSettingsSection: Int32 {
    case info
    case credentials
    case save
}

private enum MessageArchiveExportSettingsEntry: ItemListNodeEntry {
    case info(PresentationTheme, String)
    case endpoint(PresentationTheme, String, String)
    case token(PresentationTheme, String, String)
    case save(PresentationTheme, String)

    var section: ItemListSectionId {
        switch self {
            case .info:
                return MessageArchiveExportSettingsSection.info.rawValue
            case .endpoint, .token:
                return MessageArchiveExportSettingsSection.credentials.rawValue
            case .save:
                return MessageArchiveExportSettingsSection.save.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
            case .info:
                return 0
            case .endpoint:
                return 1
            case .token:
                return 2
            case .save:
                return 3
        }
    }

    static func ==(lhs: MessageArchiveExportSettingsEntry, rhs: MessageArchiveExportSettingsEntry) -> Bool {
        switch lhs {
            case let .info(lhsTheme, lhsText):
                if case let .info(rhsTheme, rhsText) = rhs, lhsTheme === rhsTheme, lhsText == rhsText {
                    return true
                }
                return false
            case let .endpoint(lhsTheme, lhsTitle, lhsText):
                if case let .endpoint(rhsTheme, rhsTitle, rhsText) = rhs, lhsTheme === rhsTheme, lhsTitle == rhsTitle, lhsText == rhsText {
                    return true
                }
                return false
            case let .token(lhsTheme, lhsTitle, lhsText):
                if case let .token(rhsTheme, rhsTitle, rhsText) = rhs, lhsTheme === rhsTheme, lhsTitle == rhsTitle, lhsText == rhsText {
                    return true
                }
                return false
            case let .save(lhsTheme, lhsTitle):
                if case let .save(rhsTheme, rhsTitle) = rhs, lhsTheme === rhsTheme, lhsTitle == rhsTitle {
                    return true
                }
                return false
        }
    }

    static func <(lhs: MessageArchiveExportSettingsEntry, rhs: MessageArchiveExportSettingsEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! MessageArchiveExportSettingsArguments
        let theme = presentationData.theme
        switch self {
            case let .info(_, text):
                return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
            case let .endpoint(_, title, text):
                return ItemListSingleLineInputItem(context: arguments.context, presentationData: presentationData, systemStyle: .glass, title: NSAttributedString(string: title, textColor: theme.list.itemPrimaryTextColor), text: text, placeholder: "https://host/events", type: .regular(capitalization: false, autocorrection: false), clearType: .always, sectionId: self.section, textUpdated: { value in
                    arguments.updateEndpoint(value)
                }, action: {})
            case let .token(_, title, text):
                return ItemListSingleLineInputItem(context: arguments.context, presentationData: presentationData, systemStyle: .glass, title: NSAttributedString(string: title, textColor: theme.list.itemPrimaryTextColor), text: text, placeholder: "", type: .password, clearType: .always, sectionId: self.section, textUpdated: { value in
                    arguments.updateToken(value)
                }, action: {})
            case let .save(_, title):
                return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                    arguments.save()
                })
        }
    }
}

private func messageArchiveExportSettingsEntries(state: MessageArchiveExportSettingsControllerState, presentationData: PresentationData) -> [MessageArchiveExportSettingsEntry] {
    var entries: [MessageArchiveExportSettingsEntry] = []
    entries.append(.info(presentationData.theme, "Deleted and edited messages are uploaded to this backend. The token is kept in the account database. Leave both fields empty to disable the upload."))
    entries.append(.endpoint(presentationData.theme, "Endpoint", state.endpoint))
    entries.append(.token(presentationData.theme, "Token", state.token))
    entries.append(.save(presentationData.theme, state.saved ? "Saved" : "Save"))
    return entries
}

public func messageArchiveExportSettingsController(context: AccountContext) -> ViewController {
    var currentState = MessageArchiveExportSettingsControllerState(endpoint: "", token: "", saved: false)
    let stateValue = ValuePromise<MessageArchiveExportSettingsControllerState>(currentState, ignoreRepeated: false)

    var presentControllerImpl: ((ViewController) -> Void)?

    let arguments = MessageArchiveExportSettingsArguments(context: context, updateEndpoint: { value in
        currentState = MessageArchiveExportSettingsControllerState(endpoint: value, token: currentState.token, saved: false)
        stateValue.set(currentState)
    }, updateToken: { value in
        currentState = MessageArchiveExportSettingsControllerState(endpoint: currentState.endpoint, token: value, saved: false)
        stateValue.set(currentState)
    }, save: {
        let settings: ArchivedMessageExportSettings?
        if currentState.endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && currentState.token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            settings = nil
        } else {
            let candidate = ArchivedMessageExportSettings(endpoint: currentState.endpoint, token: currentState.token)
            guard candidate.channel != nil else {
                let presentationData = context.sharedContext.currentPresentationData.with { $0 }
                presentControllerImpl?(standardTextAlertController(theme: AlertControllerTheme(presentationData: presentationData), title: "Message Archive Export", text: "Fill in an absolute http(s) endpoint and a non-empty token, or leave both fields empty to disable the upload.", actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})]))
                return
            }
            settings = candidate
        }
        let _ = (context.account.postbox.transaction { transaction -> Void in
            updateArchivedMessageExportSettings(transaction: transaction, settings: settings)
        }).start()
        currentState = MessageArchiveExportSettingsControllerState(endpoint: currentState.endpoint, token: currentState.token, saved: true)
        stateValue.set(currentState)
    })

    // The stored configuration fills the fields once; an edit made before the read
    // completes keeps the typed value.
    arguments.disposable.set((archivedMessageExportSettings(postbox: context.account.postbox)
    |> take(1)
    |> deliverOnMainQueue).start(next: { stored in
        guard let stored = stored else {
            return
        }
        if !currentState.saved && currentState.endpoint.isEmpty && currentState.token.isEmpty {
            currentState = MessageArchiveExportSettingsControllerState(endpoint: stored.endpoint, token: stored.token, saved: false)
            stateValue.set(currentState)
        }
    }))

    let signal = combineLatest(context.sharedContext.presentationData, stateValue.get())
    |> map { presentationData, state -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Message Archive Export"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: messageArchiveExportSettingsEntries(state: state, presentationData: presentationData), style: .blocks)
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    presentControllerImpl = { [weak controller] c in
        controller?.present(c, in: .window(.root))
    }
    return controller
}
