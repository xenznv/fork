import Foundation
import Display
import SwiftSignalKit
import TelegramPresentationData
import TelegramUIPreferences
import ItemListUI
import AccountContext
import TelegramCore
import CustomCore
import CoreLocation
import LocationUI

public func customSpoofController(context: AccountContext) -> ViewController {
    let initialState = CustomSpoofController.shared.currentState
    let statePromise = ValuePromise(initialState, ignoreRepeated: true)

    let modes: [CustomSpoofMode] = [.session, .persistent]

    final class Arguments {
        let toggle: (String, Bool) -> Void
        let action: (String) -> Void
        init(toggle: @escaping (String, Bool) -> Void, action: @escaping (String) -> Void) {
            self.toggle = toggle
            self.action = action
        }
    }

    enum Entry: ItemListNodeEntry {
        case header(Int32, String)
        case toggle(Int32, Int32, String, Bool, String)
        case input(Int32, Int32, String, String, String)
        case action(Int32, Int32, String, String, String)
        case info(Int32, String)

        var section: ItemListSectionId {
            switch self {
            case let .header(section, _), let .toggle(section, _, _, _, _), let .input(section, _, _, _, _), let .action(section, _, _, _, _), let .info(section, _):
                return section
            }
        }
        var stableId: Int32 {
            switch self {
            case let .header(section, _): return section * 1000
            case let .toggle(section, index, _, _, _), let .input(section, index, _, _, _), let .action(section, index, _, _, _): return section * 1000 + index
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
            case let .toggle(_, _, title, value, actionId):
                return ItemListSwitchItem(
                    presentationData: presentationData, systemStyle: .glass,
                    title: title, value: value, sectionId: self.section,
                    style: .blocks, updated: { arguments.toggle(actionId, $0) }
                )
            case let .input(_, _, title, text, action):
                return ItemListSingleLineInputItem(
                    presentationData: presentationData, systemStyle: .glass,
                    title: NSAttributedString(string: title, textColor: presentationData.theme.list.itemPrimaryTextColor),
                    text: text,
                    placeholder: "0.0",
                    type: .regular(capitalization: false, autocorrection: false),
                    returnKeyType: .done,
                    alignment: .right,
                    spacing: 16.0,
                    clearType: .none,
                    maxLength: 32,
                    sectionId: self.section,
                    textUpdated: { updatedText in
                        arguments.action(action + ":" + updatedText)
                    },
                    action: {}
                )
            case let .action(_, _, title, value, action):
                return ItemListDisclosureItem(
                    presentationData: presentationData, systemStyle: .glass,
                    title: title, label: value, labelStyle: .text,
                    sectionId: self.section, style: .blocks,
                    disclosureStyle: action == "cycleMode" ? .arrow : .none,
                    action: action.isEmpty ? nil : { arguments.action(action) }
                )
            case let .info(_, text):
                return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
            }
        }
    }

    func formatMode(_ mode: CustomSpoofMode, strings: CustomStrings) -> String {
        switch mode {
        case .session: return strings.spoofModeSession
        case .persistent: return strings.spoofModePersistent
        }
    }

    func entries(state: CustomSpoofState, strings: CustomStrings) -> [Entry] {
        var entries: [Entry] = [
            .header(0, strings.spoofSection),
            .toggle(0, 1, strings.spoofEnabled, state.enabled, "enabled"),
            .action(0, 2, strings.spoofChooseOnMap, String(format: "%.5f, %.5f", state.latitude, state.longitude), "chooseOnMap"),
            .input(0, 3, strings.spoofLatitude, String(format: "%.6f", state.latitude), "lat"),
            .input(0, 4, strings.spoofLongitude, String(format: "%.6f", state.longitude), "lon"),
            .action(0, 5, strings.spoofMode, formatMode(state.mode, strings: strings), "cycleMode"),
            .info(0, state.enabled ? strings.spoofActiveHint : strings.spoofHint)
        ]
        if state.enabled {
            entries.append(.action(0, 6, strings.spoofStop, "", "disable"))
        }

        return entries
    }

    var pushControllerImpl: ((ViewController) -> Void)?
    var controller: ItemListController?

    func refresh() {
        statePromise.set(CustomSpoofController.shared.currentState)
    }

    let arguments = Arguments(toggle: { actionId, value in
        switch actionId {
        case "enabled":
            CustomSpoofController.shared.setEnabled(value)
        default:
            break
        }
        refresh()
    }, action: { rawAction in
        let parts = rawAction.split(separator: ":", maxSplits: 1).map(String.init)
        let action = parts.first ?? rawAction
        let value = parts.count > 1 ? parts[1] : nil

        switch action {
        case "chooseOnMap":
            let currentState = CustomSpoofController.shared.currentState
            let picker = LocationPickerController(
                context: context,
                style: .glass,
                mode: .pick,
                initialLocation: CLLocationCoordinate2D(latitude: currentState.latitude, longitude: currentState.longitude),
                completion: { location, _, _, _, _ in
                    CustomSpoofController.shared.setCoordinate(latitude: location.latitude, longitude: location.longitude)
                    refresh()
                }
            )
            pushControllerImpl?(picker)
        case "lat":
            if let text = value, let parsed = Double(text) {
                CustomSpoofController.shared.setCoordinate(latitude: parsed, longitude: CustomSpoofController.shared.currentState.longitude)
            }
            refresh()
        case "lon":
            if let text = value, let parsed = Double(text) {
                CustomSpoofController.shared.setCoordinate(latitude: CustomSpoofController.shared.currentState.latitude, longitude: parsed)
            }
            refresh()
        case "cycleMode":
            CustomSpoofController.shared.update { state in
                let currentIndex = modes.firstIndex(of: state.mode) ?? 0
                state.mode = modes[(currentIndex + 1) % modes.count]
            }
            refresh()
        case "disable":
            CustomSpoofController.shared.setEnabled(false)
            refresh()
        default:
            break
        }
    })

    let signal = combineLatest(context.sharedContext.presentationData, statePromise.get())
    |> deliverOnMainQueue
    |> map { presentationData, state -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let strings = presentationData.strings.custom
        return (
            ItemListControllerState(
                presentationData: ItemListPresentationData(presentationData),
                title: .text(strings.spoof),
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
    controller = ItemListController(context: context, state: signal)
    pushControllerImpl = { [weak controller] c in
        (controller?.navigationController as? NavigationController)?.pushViewController(c)
    }
    return controller!
}
