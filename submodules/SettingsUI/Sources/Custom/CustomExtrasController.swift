import Foundation
import Display
import SwiftSignalKit
import TelegramPresentationData
import ItemListUI
import AccountContext
import CustomCore

private struct CustomExtrasUIState: Equatable {
    var sanitization: Bool
    var anonymize: Bool
}

public func customExtrasController(context: AccountContext) -> ViewController {
    let initialState = CustomExtrasUIState(
        sanitization: CustomExtrasSettings.metadataSanitizationEnabled,
        anonymize: CustomExtrasSettings.anonymizeFileNamesEnabled
    )
    let stateValue = Atomic(value: initialState)
    let statePromise = ValuePromise(initialState, ignoreRepeated: true)

    final class Arguments {
        let toggle: (String, Bool) -> Void
        init(toggle: @escaping (String, Bool) -> Void) {
            self.toggle = toggle
        }
    }

    enum Entry: ItemListNodeEntry {
        case header(Int32, String)
        case toggle(Int32, Int32, String, String, Bool)
        case info(Int32, String)

        var section: ItemListSectionId {
            switch self {
            case let .header(section, _), let .toggle(section, _, _, _, _), let .info(section, _):
                return section
            }
        }
        var stableId: Int32 {
            switch self {
            case let .header(section, _): return section * 1000
            case let .toggle(section, index, _, _, _): return section * 1000 + index
            case let .info(section, _): return section * 1000 + 999
            }
        }
        static func == (lhs: Entry, rhs: Entry) -> Bool {
            return lhs.stableId == rhs.stableId && String(describing: lhs) == String(describing: rhs)
        }
        static func < (lhs: Entry, rhs: Entry) -> Bool {
            return lhs.stableId < rhs.stableId
        }
        func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
            let arguments = arguments as! Arguments
            switch self {
            case let .header(_, title):
                return ItemListSectionHeaderItem(presentationData: presentationData, text: title, sectionId: self.section)
            case let .toggle(_, _, title, action, value):
                return ItemListSwitchItem(
                    presentationData: presentationData, systemStyle: .glass,
                    title: title, value: value, sectionId: self.section,
                    style: .blocks, updated: { arguments.toggle(action, $0) }
                )
            case let .info(_, text):
                return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
            }
        }
    }

    func entries(state: CustomExtrasUIState, strings: CustomStrings) -> [Entry] {
        return [
            .header(0, strings.extrasMetadataSection),
            .toggle(0, 1, strings.extrasMetadataToggle, "sanitize", state.sanitization),
            .toggle(0, 2, strings.extrasAnonymizeNames, "anonymize", state.anonymize),
            .info(0, strings.extrasMetadataHint),
            .header(1, strings.extrasPrioritySection),
            .info(1, strings.extrasPriorityHint)
        ]
    }

    let arguments = Arguments(toggle: { action, value in
        let updated = stateValue.modify { current in
            var current = current
            if action == "sanitize" {
                current.sanitization = value
                CustomExtrasSettings.metadataSanitizationEnabled = value
            } else if action == "anonymize" {
                current.anonymize = value
                CustomExtrasSettings.anonymizeFileNamesEnabled = value
            }
            return current
        }
        statePromise.set(updated)
    })

    let signal = combineLatest(context.sharedContext.presentationData, statePromise.get())
    |> deliverOnMainQueue
    |> map { presentationData, state -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let strings = presentationData.strings.custom
        return (
            ItemListControllerState(
                presentationData: ItemListPresentationData(presentationData),
                title: .text(strings.extras),
                leftNavigationButton: nil, rightNavigationButton: nil,
                backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
            ),
            (ItemListNodeState(
                presentationData: ItemListPresentationData(presentationData),
                entries: entries(state: state, strings: strings),
                style: .blocks, animateChanges: false
            ), arguments as Any)
        )
    }
    return ItemListController(context: context, state: signal)
}
