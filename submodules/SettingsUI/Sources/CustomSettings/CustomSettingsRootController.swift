import Foundation
import CustomCore
import AsyncDisplayKit
import ContextUI
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import Postbox
import TelegramPresentationData
import ItemListUI
import AccountContext
import ItemListPeerItem
import BuildConfig

private enum CustomKey {
    static let profileEnabled = "custom.Profile.Enabled"
    static let showIds = "custom.Profile.ShowIds"
    static let showDCs = "custom.Profile.ShowDCs"
    static let showRegistration = "custom.Profile.ShowRegistration"

    static let readMessages = "custom.InvisibleMode.ReadMessages"
    static let storyReadReceipts = "custom.InvisibleMode.StoryReadReceipts"
    static let typingActions = "custom.InvisibleMode.TypingActions"
    static let recordingActions = "custom.InvisibleMode.HideRecording"
    static let recordingVideo = "custom.InvisibleMode.HideRecordingVideo"
    static let recordingRound = "custom.InvisibleMode.HideRecordingRound"
    static let uploadingActions = "custom.InvisibleMode.HideUploading"
    static let uploadingPhoto = "custom.InvisibleMode.HideUploadingPhoto"
    static let uploadingVideo = "custom.InvisibleMode.HideUploadingVideo"
    static let uploadingFile = "custom.InvisibleMode.HideUploadingFile"
    static let uploadingRound = "custom.InvisibleMode.HideUploadingRound"
    static let uploadingVoice = "custom.InvisibleMode.HideUploadingVoice"
    static let stickerActivity = "custom.InvisibleMode.HideStickerActivity"
    static let gameActivity = "custom.InvisibleMode.HideGameActivity"
    static let emojiActivity = "custom.InvisibleMode.HideEmojiActivity"
    static let emojiAcknowledgement = "custom.InvisibleMode.HideEmojiAcknowledgement"
    static let speakingInGroupCall = "custom.InvisibleMode.HideGroupCallSpeaking"
    static let choosingLocation = "custom.InvisibleMode.HideChoosingLocation"
    static let choosingContact = "custom.InvisibleMode.HideChoosingContact"
    static let presence = "custom.InvisibleMode.Presence"
    static let scheduledSend = "custom.InvisibleMode.ScheduledSend"

    static let saveDeleted = "custom.Messages.SaveDeleted"
    static let showDeleted = "custom.Messages.ShowDeleted"
    static let saveEditHistory = "custom.Messages.SaveEditHistory"
    static let showEditHistory = "custom.Messages.ShowEditHistory"
    static let hideBlockedMessages = "custom.Messages.HideBlockedMessages"
    static let hideBlockedReactions = "custom.Messages.HideBlockedReactions"

    static let glassEnabled = "custom.Glass.Enabled"
    static let profileAvatarBlur = "custom.ProfileBlur.Avatar"
    static let profileAnimatedBackground = "custom.ProfileBlur.Animated"
    static let profileBlurTint = "custom.ProfileBlur.Tint"
    static let profileBlurReduced = "custom.ProfileBlur.Reduced"
    static let deletedPortableReplies = "custom.Messages.DeletedPortableReplies"
    static let preserveDeletedMedia = "custom.Messages.PreserveDeletedMedia"
    static let deletedMediaCacheLimit = "custom.Messages.DeletedMediaCacheLimit"
    static let deletedMediaRetentionDays = "custom.Messages.DeletedMediaRetentionDays"
    static let messageSeconds = "custom.Appearance.MessageSeconds"
    static let messageCharacterCount = "custom.Messages.CharacterCount"
    static let hideOwnPhone = "custom.Appearance.HideOwnPhone"

    static let protectedEnabled = "custom.ProtectedContent.Enabled"
    static let protectedGalleryShare = "custom.ProtectedContent.GalleryShare"
    static let protectedGallerySave = "custom.ProtectedContent.GallerySave"
    static let protectedGalleryCopy = "custom.ProtectedContent.GalleryCopy"
    static let chatSave = "custom.ProtectedContent.ChatSave"
    static let chatCopy = "custom.ProtectedContent.ChatCopy"
    static let chatForward = "custom.ProtectedContent.ChatForward"
    static let allowScreenshots = "custom.ProtectedContent.AllowScreenshots"
    static let allowScreenRecording = "custom.ProtectedContent.AllowScreenRecording"
    static let oneTimeScreenshots = "custom.ProtectedContent.OneTimeScreenshots"
    static let oneTimeScreenRecording = "custom.ProtectedContent.OneTimeScreenRecording"
    static let oneTimeSave = "custom.ProtectedContent.OneTimeSave"
    static let storySave = "custom.Stories.Save"
    static let showRestricted = "custom.ProtectedContent.ShowRestricted"
    static let removeAds = "custom.ProtectedContent.RemoveAds"
    static let localStarsEnabled = "custom.Stars.LocalBalance.Enabled"
    static let localStarsAmount = "custom.Stars.LocalBalance.Amount"
    static let localStarsBaseAmount = "custom.Stars.LocalBalance.BaseAmount"
}

private func customBool(_ key: String, defaultValue: Bool) -> Bool {
    if let value = UserDefaults.standard.object(forKey: key) as? Bool {
        return value
    }
    return defaultValue
}

private func customString(_ key: String, defaultValue: String) -> String {
    if let value = UserDefaults.standard.object(forKey: key) as? String {
        return value
    }
    return defaultValue
}

private func customIsValidStarsAmountInput(_ text: String) -> Bool {
    var hasSeparator = false

    for (index, ch) in text.enumerated() {
        if ch == "-" || ch == "+" {
            if index != 0 {
                return false
            }
        } else if ch >= "0" && ch <= "9" {
            continue
        } else if ch == "," || ch == "." {
            if hasSeparator {
                return false
            }
            hasSeparator = true
        } else if ch == " " || ch == "\u{00a0}" {
            continue
        } else {
            return false
        }
    }

    return true
}

private func customSanitizeStarsAmount(_ text: String) -> String {
    var result = ""
    var hasSeparator = false
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

    for (index, ch) in trimmed.enumerated() {
        if ch == "-" && result.isEmpty && index == 0 {
            result.append(ch)
        } else if ch == "+" && result.isEmpty && index == 0 {
            continue
        } else if ch >= "0" && ch <= "9" {
            result.append(ch)
        } else if (ch == "," || ch == ".") && !hasSeparator {
            result.append(".")
            hasSeparator = true
        } else if ch == " " || ch == "\u{00a0}" {
            continue
        }
    }

    if result == "." || result == "-." {
        return ""
    }

    return result
}
private func customStarsInt64(_ text: String) -> Int64 {
    return Int64(customSanitizeStarsAmount(text)) ?? 0
}

private func customStarsTransactionPreview(baseAmount: String, targetAmount: String) -> String {
    let base = customStarsInt64(baseAmount)
    let target = customStarsInt64(targetAmount)
    let delta = target - base
    let sign = delta >= 0 ? "+" : ""
    return "Transaction Preview: Custom \(sign)\(delta)"
}

private let customSendTextStyleKey =
    "custom.Messages.SendTextStyle"

private enum CustomSettingsEntryTag:
    Equatable, ItemListItemTag
{
    case sendTextStyle

    func isEqual(to other: ItemListItemTag) -> Bool {
        guard let other = other as? CustomSettingsEntryTag else {
            return false
        }
        return self == other
    }
}

private func customSendStyleAttributedText(
    style: String,
    text: String,
    color: UIColor,
    size: CGFloat
) -> NSAttributedString {
    var visibleText = text

    if style == "spoiler" {
        visibleText = text.unicodeScalars.map { scalar in
            CharacterSet.alphanumerics.contains(scalar)
                ? "#"
                : String(scalar)
        }.joined()
    }

    var attributes: [NSAttributedString.Key: Any] = [
        .font: UIFont.systemFont(ofSize: size),
        .foregroundColor: color
    ]

    switch style {
    case "bold":
        attributes[.font] = UIFont.boldSystemFont(ofSize: size)
    case "italic":
        attributes[.font] = UIFont.italicSystemFont(ofSize: size)
    case "monospace":
        attributes[.font] = UIFont.monospacedSystemFont(
            ofSize: size,
            weight: .regular
        )
    case "strikethrough":
        attributes[.strikethroughStyle] =
            NSUnderlineStyle.single.rawValue
    case "underline":
        attributes[.underlineStyle] =
            NSUnderlineStyle.single.rawValue
    default:
        break
    }

    return NSAttributedString(
        string: visibleText,
        attributes: attributes
    )
}

private func customSendTextStyleTitle(
    _ value: String,
    strings: CustomStrings
) -> String {
    switch value {
    case "bold":
        return strings.sendStyleBold
    case "italic":
        return strings.sendStyleItalic
    case "monospace":
        return strings.sendStyleMonospace
    case "strikethrough":
        return strings.sendStyleStrikethrough
    case "underline":
        return strings.sendStyleUnderline
    case "spoiler":
        return strings.sendStyleSpoiler
    default:
        return strings.sendStyleNormal
    }
}

private final class CustomSendStyleContextSource:
    ContextControllerContentSource
{
    let controller: ViewController
    let navigationController: NavigationController? = nil
    let passthroughTouches: Bool = false

    weak var sourceNode: ASDisplayNode?

    init(
        controller: ViewController,
        sourceNode: ASDisplayNode
    ) {
        self.controller = controller
        self.sourceNode = sourceNode
    }

    func transitionInfo() -> ContextControllerTakeControllerInfo? {
        let sourceNode = self.sourceNode

        return ContextControllerTakeControllerInfo(
            contentAreaInScreenSpace: CGRect(
                origin: CGPoint(),
                size: CGSize(width: 10.0, height: 10.0)
            ),
            sourceNode: { [weak sourceNode] in
                if let sourceNode = sourceNode {
                    return (
                        sourceNode.view,
                        sourceNode.bounds
                    )
                } else {
                    return nil
                }
            }
        )
    }

    func animatedIn() {
    }
}

private func customSendStyleMenuItems(
    selected: String,
    strings: CustomStrings,
    select: @escaping (String) -> Void
) -> [ContextMenuItem] {
    let styles = [
        ("normal", strings.sendStyleNormal),
        ("bold", strings.sendStyleBold),
        ("italic", strings.sendStyleItalic),
        ("monospace", strings.sendStyleMonospace),
        ("strikethrough", strings.sendStyleStrikethrough),
        ("underline", strings.sendStyleUnderline),
        ("spoiler", strings.sendStyleSpoiler)
    ]

    return styles.map { value, title in
        let prefix = value == selected ? "✓ " : ""
        var displayText = prefix + title
        var entities: [MessageTextEntity] = []

        let menuFont: ContextMenuActionItemFont
        switch value {
        case "bold":
            menuFont = .custom(
                font: UIFont.boldSystemFont(ofSize: 17.0),
                height: nil,
                verticalOffset: nil
            )
        case "italic":
            menuFont = .custom(
                font: UIFont.italicSystemFont(ofSize: 17.0),
                height: nil,
                verticalOffset: nil
            )
        case "monospace":
            menuFont = .custom(
                font: UIFont.monospacedSystemFont(
                    ofSize: 17.0,
                    weight: .regular
                ),
                height: nil,
                verticalOffset: nil
            )
        default:
            menuFont = .regular
        }

        let start = (prefix as NSString).length
        let end = start + (title as NSString).length
        let titleRange = start ..< end

        switch value {
        case "bold":
            entities.append(
                MessageTextEntity(range: titleRange, type: .Bold)
            )
        case "italic":
            entities.append(
                MessageTextEntity(range: titleRange, type: .Italic)
            )
        case "monospace":
            entities.append(
                MessageTextEntity(range: titleRange, type: .Code)
            )
        case "strikethrough":
            entities.append(
                MessageTextEntity(
                    range: titleRange,
                    type: .Strikethrough
                )
            )
        case "underline":
            entities.append(
                MessageTextEntity(range: titleRange, type: .Underline)
            )
        case "spoiler":
            displayText += "  пример"

            let range = (displayText as NSString).range(
                of: "пример",
                options: .backwards
            )

            entities.append(
                MessageTextEntity(
                    range: range.location ..< NSMaxRange(range),
                    type: .Spoiler
                )
            )
        default:
            break
        }

        return .action(
            ContextMenuActionItem(
                text: displayText,
                entities: entities,
                textLayout: .singleLine,
                textFont: menuFont,
                icon: { _ in nil },
                action: { _, dismiss in
                    select(value)
                    dismiss(.default)
                }
            )
        )
    }
}

private func customScopedSettingsKey(accountPeerId: Int64, key: String) -> String {
    return "custom.account.\(accountPeerId).setting.\(key)"
}

private func customScopedBool(
    accountPeerId: Int64,
    key: String,
    defaultValue: Bool
) -> Bool {
    let scopedKey = customScopedSettingsKey(accountPeerId: accountPeerId, key: key)
    if let value = UserDefaults.standard.object(forKey: scopedKey) as? Bool {
        return value
    }
    let migrated = customBool(key, defaultValue: defaultValue)
    UserDefaults.standard.set(migrated, forKey: scopedKey)
    return migrated
}

private func customScopedString(
    accountPeerId: Int64,
    key: String,
    defaultValue: String
) -> String {
    let scopedKey = customScopedSettingsKey(accountPeerId: accountPeerId, key: key)
    if let value = UserDefaults.standard.object(forKey: scopedKey) as? String {
        return value
    }
    let migrated = customString(key, defaultValue: defaultValue)
    UserDefaults.standard.set(migrated, forKey: scopedKey)
    return migrated
}

private enum CustomSettingValue: Equatable {
    case bool(Bool)
    case string(String)

    func write(to defaults: UserDefaults, key: String) {
        switch self {
        case let .bool(value): defaults.set(value, forKey: key)
        case let .string(value): defaults.set(value, forKey: key)
        }
    }
}

private enum CustomSettingsCommitQueue {
    private static let queue = Queue(name: "CustomSettingsCommitQueue", qos: .utility)
    static func enqueue(_ work: @escaping () -> Void) {
        self.queue.async(work)
    }
}

private func customStateValues(_ state: CustomSettingsState) -> [String: CustomSettingValue] {
    return [
        CustomKey.profileEnabled: .bool(state.profileEnabled),
        CustomKey.showIds: .bool(state.showIds),
        CustomKey.showDCs: .bool(state.showDCs),
        CustomKey.showRegistration: .bool(state.showRegistration),
        CustomKey.glassEnabled: .bool(state.glassEnabled),
        CustomKey.profileAvatarBlur: .bool(state.profileAvatarBlur),
        CustomKey.profileAnimatedBackground: .bool(state.profileAnimatedBackground),
        CustomKey.profileBlurTint: .bool(state.profileBlurTint),
        CustomKey.profileBlurReduced: .bool(state.profileBlurReduced),
        CustomKey.readMessages: .bool(state.readMessages),
        CustomKey.storyReadReceipts: .bool(state.storyReadReceipts),
        CustomKey.typingActions: .bool(state.typingActions),
        CustomKey.recordingActions: .bool(state.recordingActions),
        CustomKey.recordingVideo: .bool(state.recordingVideo),
        CustomKey.recordingRound: .bool(state.recordingRound),
        CustomKey.uploadingActions: .bool(state.uploadingActions),
        CustomKey.uploadingPhoto: .bool(state.uploadingPhoto),
        CustomKey.uploadingVideo: .bool(state.uploadingVideo),
        CustomKey.uploadingFile: .bool(state.uploadingFile),
        CustomKey.uploadingRound: .bool(state.uploadingRound),
        CustomKey.uploadingVoice: .bool(state.uploadingVoice),
        CustomKey.stickerActivity: .bool(state.stickerActivity),
        CustomKey.gameActivity: .bool(state.gameActivity),
        CustomKey.emojiActivity: .bool(state.emojiActivity),
        CustomKey.emojiAcknowledgement: .bool(state.emojiAcknowledgement),
        CustomKey.speakingInGroupCall: .bool(state.speakingInGroupCall),
        CustomKey.choosingLocation: .bool(state.choosingLocation),
        CustomKey.choosingContact: .bool(state.choosingContact),
        CustomKey.presence: .bool(state.presence),
        CustomKey.scheduledSend: .bool(state.scheduledSend),
        CustomKey.saveDeleted: .bool(state.saveDeleted),
        CustomKey.showDeleted: .bool(state.showDeleted),
        CustomKey.saveEditHistory: .bool(state.saveEditHistory),
        CustomKey.showEditHistory: .bool(state.showEditHistory),
        CustomKey.hideBlockedMessages: .bool(state.hideBlockedMessages),
        CustomKey.hideBlockedReactions: .bool(state.hideBlockedReactions),
        customSendTextStyleKey: .string(state.sendTextStyle),
        CustomKey.deletedPortableReplies: .bool(state.deletedPortableReplies),
        CustomKey.preserveDeletedMedia: .bool(state.preserveDeletedMedia),
        CustomKey.messageSeconds: .bool(state.messageSeconds),
        CustomKey.messageCharacterCount: .bool(state.messageCharacterCount),
        CustomKey.hideOwnPhone: .bool(state.hideOwnPhone),
        CustomKey.protectedEnabled: .bool(state.protectedEnabled),
        CustomKey.protectedGalleryShare: .bool(state.protectedGalleryShare),
        CustomKey.protectedGallerySave: .bool(state.protectedGallerySave),
        CustomKey.protectedGalleryCopy: .bool(state.protectedGalleryCopy),
        CustomKey.chatSave: .bool(state.chatSave),
        CustomKey.chatCopy: .bool(state.chatCopy),
        CustomKey.chatForward: .bool(state.chatForward),
        CustomKey.allowScreenshots: .bool(state.allowScreenshots),
        CustomKey.allowScreenRecording: .bool(state.allowScreenRecording),
        CustomKey.oneTimeScreenshots: .bool(state.oneTimeScreenshots),
        CustomKey.oneTimeScreenRecording: .bool(state.oneTimeScreenRecording),
        CustomKey.oneTimeSave: .bool(state.oneTimeSave),
        CustomKey.storySave: .bool(state.storySave),
        CustomKey.showRestricted: .bool(state.showRestricted),
        CustomKey.removeAds: .bool(state.removeAds),
        CustomKey.localStarsEnabled: .bool(state.localStarsEnabled),
        CustomKey.localStarsAmount: .string(state.localStarsAmount),
        CustomKey.localStarsBaseAmount: .string(state.localStarsBaseAmount)
    ]
}

private func customPersistChangedSettings(
    accountPeerId: Int64,
    previous: CustomSettingsState?,
    current: CustomSettingsState
) {
    defer { CustomHotSettings.invalidate() }
    let oldValues = previous.map(customStateValues) ?? [:]
    let newValues = customStateValues(current)
    let changes = newValues.filter { oldValues[$0.key] != $0.value }
    guard !changes.isEmpty else { return }

    // These values are consumed synchronously outside Settings immediately
    // before user-visible side effects. Leaving them behind the utility queue
    // creates a real stale-state window: Scheduled Send can remain active after
    // OFF, and protected one-time media can be replaced with expired content
    // immediately after One-Time Save was switched ON.
    //
    // UserDefaults.set updates the in-process defaults domain; deliberately
    // avoid any forced defaults/filesystem synchronization here.
    let customSynchronousRuntimeSettingKeys: Set<String> = Set<String>([
        CustomKey.scheduledSend,
        CustomKey.protectedEnabled,
        CustomKey.oneTimeSave,
        CustomKey.hideBlockedMessages,
        CustomKey.hideBlockedReactions,
        CustomKey.typingActions,
        CustomKey.recordingActions,
        CustomKey.recordingVideo,
        CustomKey.recordingRound,
        CustomKey.uploadingActions,
        CustomKey.uploadingPhoto,
        CustomKey.uploadingVideo,
        CustomKey.uploadingFile,
        CustomKey.uploadingRound,
        CustomKey.uploadingVoice,
        CustomKey.stickerActivity,
        CustomKey.gameActivity,
        CustomKey.emojiActivity,
        CustomKey.emojiAcknowledgement,
        CustomKey.speakingInGroupCall,
        CustomKey.choosingLocation,
        CustomKey.choosingContact,
        CustomKey.storyReadReceipts,
        CustomKey.removeAds,
    ]).union(CustomHotSettings.keys)
    let defaults = UserDefaults.standard
    for key in customSynchronousRuntimeSettingKeys {
        guard let value = changes[key] else { continue }
        value.write(
            to: defaults,
            key: customScopedSettingsKey(accountPeerId: accountPeerId, key: key)
        )
        // Legacy Telegram/Custom runtime owners consume the active-account
        // projection directly from UserDefaults.standard.
        value.write(to: defaults, key: key)
        if key == CustomKey.scheduledSend {
            let sharedDefaults = UserDefaults(suiteName: "group.ph.telegra.Telegraph") ?? defaults
            value.write(to: sharedDefaults, key: key)
        }
    }
    CustomActivityCustomRuntime.invalidate()

    if changes[CustomKey.hideBlockedMessages] != nil
        || changes[CustomKey.hideBlockedReactions] != nil {
        CustomBlockedReactionPolicy.notifySettingsChanged()
    }

    let deferredChanges = changes.filter {
        !customSynchronousRuntimeSettingKeys.contains($0.key)
    }
    guard !deferredChanges.isEmpty else { return }

    CustomSettingsCommitQueue.enqueue {
        let defaults = UserDefaults.standard
        for (key, value) in deferredChanges {
            value.write(to: defaults, key: customScopedSettingsKey(accountPeerId: accountPeerId, key: key))
            // Non-critical compatibility projections stay off the caller thread.
            value.write(to: defaults, key: key)
        }
    }
}

private func customProjectActiveSettings(accountPeerId: Int64, state: CustomSettingsState) {
    customPersistChangedSettings(accountPeerId: accountPeerId, previous: nil, current: state)
}

// Regression sentinel: bulk defaults enumeration must never return here.


struct CustomSettingsState: Equatable {
    var profileEnabled: Bool
    var showIds: Bool
    var showDCs: Bool
    var showRegistration: Bool
    var glassEnabled: Bool
    var profileAvatarBlur: Bool
    var profileAnimatedBackground: Bool
    var profileBlurTint: Bool
    var profileBlurReduced: Bool

    var readMessages: Bool
    var storyReadReceipts: Bool
    var typingActions: Bool
    var recordingActions: Bool
    var recordingVideo: Bool
    var recordingRound: Bool
    var uploadingActions: Bool
    var uploadingPhoto: Bool
    var uploadingVideo: Bool
    var uploadingFile: Bool
    var uploadingRound: Bool
    var uploadingVoice: Bool
    var stickerActivity: Bool
    var gameActivity: Bool
    var emojiActivity: Bool
    var emojiAcknowledgement: Bool
    var speakingInGroupCall: Bool
    var choosingLocation: Bool
    var choosingContact: Bool
    var presence: Bool
    var scheduledSend: Bool

    var saveDeleted: Bool
    var showDeleted: Bool
    var saveEditHistory: Bool
    var showEditHistory: Bool
    var hideBlockedMessages: Bool
    var hideBlockedReactions: Bool
    var sendTextStyle: String

    var deletedPortableReplies: Bool
    var preserveDeletedMedia: Bool
    var messageSeconds: Bool
    var messageCharacterCount: Bool
    var hideOwnPhone: Bool

    var protectedEnabled: Bool
    var protectedGalleryShare: Bool
    var protectedGallerySave: Bool
    var protectedGalleryCopy: Bool

    var chatSave: Bool
    var chatCopy: Bool
    var chatForward: Bool
    var allowScreenshots: Bool
    var allowScreenRecording: Bool
    var oneTimeScreenshots: Bool
    var oneTimeScreenRecording: Bool
    var oneTimeSave: Bool
    var storySave: Bool
    var showRestricted: Bool
    var removeAds: Bool
    var localStarsEnabled: Bool
    var localStarsAmount: String
    var localStarsBaseAmount: String
    static func load(accountPeerId: Int64) -> CustomSettingsState {
        return CustomSettingsState(
            profileEnabled: customScopedBool(accountPeerId: accountPeerId, key: CustomKey.profileEnabled, defaultValue: true),
            showIds: customScopedBool(accountPeerId: accountPeerId, key: CustomKey.showIds, defaultValue: true),
            showDCs: customScopedBool(accountPeerId: accountPeerId, key: CustomKey.showDCs, defaultValue: true),
            showRegistration: customScopedBool(accountPeerId: accountPeerId, key: CustomKey.showRegistration, defaultValue: true),
            glassEnabled: customScopedBool(accountPeerId: accountPeerId, key: CustomKey.glassEnabled, defaultValue: true),
            profileAvatarBlur: customScopedBool(accountPeerId: accountPeerId, key: CustomKey.profileAvatarBlur, defaultValue: true),
            profileAnimatedBackground: customScopedBool(accountPeerId: accountPeerId, key: CustomKey.profileAnimatedBackground, defaultValue: true),
            profileBlurTint: customScopedBool(accountPeerId: accountPeerId, key: CustomKey.profileBlurTint, defaultValue: true),
            profileBlurReduced: customScopedBool(accountPeerId: accountPeerId, key: CustomKey.profileBlurReduced, defaultValue: false),
            readMessages: customScopedBool(accountPeerId: accountPeerId, key: CustomKey.readMessages, defaultValue: false),
            storyReadReceipts: customScopedBool(accountPeerId: accountPeerId, key: CustomKey.storyReadReceipts, defaultValue: false),
            typingActions: customScopedBool(accountPeerId: accountPeerId, key: CustomKey.typingActions, defaultValue: false),
            recordingActions: customScopedBool(accountPeerId: accountPeerId, key: CustomKey.recordingActions, defaultValue: false),
            recordingVideo: customScopedBool(accountPeerId: accountPeerId, key: CustomKey.recordingVideo, defaultValue: false),
            recordingRound: customScopedBool(accountPeerId: accountPeerId, key: CustomKey.recordingRound, defaultValue: false),
            uploadingActions: customScopedBool(accountPeerId: accountPeerId, key: CustomKey.uploadingActions, defaultValue: false),
            uploadingPhoto: customScopedBool(accountPeerId: accountPeerId, key: CustomKey.uploadingPhoto, defaultValue: false),
            uploadingVideo: customScopedBool(accountPeerId: accountPeerId, key: CustomKey.uploadingVideo, defaultValue: false),
            uploadingFile: customScopedBool(accountPeerId: accountPeerId, key: CustomKey.uploadingFile, defaultValue: false),
            uploadingRound: customScopedBool(accountPeerId: accountPeerId, key: CustomKey.uploadingRound, defaultValue: false),
            uploadingVoice: customScopedBool(accountPeerId: accountPeerId, key: CustomKey.uploadingVoice, defaultValue: false),
            stickerActivity: customScopedBool(accountPeerId: accountPeerId, key: CustomKey.stickerActivity, defaultValue: false),
            gameActivity: customScopedBool(accountPeerId: accountPeerId, key: CustomKey.gameActivity, defaultValue: false),
            emojiActivity: customScopedBool(accountPeerId: accountPeerId, key: CustomKey.emojiActivity, defaultValue: false),
            emojiAcknowledgement: customScopedBool(accountPeerId: accountPeerId, key: CustomKey.emojiAcknowledgement, defaultValue: false),
            speakingInGroupCall: customScopedBool(accountPeerId: accountPeerId, key: CustomKey.speakingInGroupCall, defaultValue: false),
            choosingLocation: customScopedBool(accountPeerId: accountPeerId, key: CustomKey.choosingLocation, defaultValue: false),
            choosingContact: customScopedBool(accountPeerId: accountPeerId, key: CustomKey.choosingContact, defaultValue: false),
            presence: customScopedBool(accountPeerId: accountPeerId, key: CustomKey.presence, defaultValue: false),
            scheduledSend: customScopedBool(accountPeerId: accountPeerId, key: CustomKey.scheduledSend, defaultValue: false),
            saveDeleted: customScopedBool(accountPeerId: accountPeerId, key: CustomKey.saveDeleted, defaultValue: true),
            showDeleted: customScopedBool(accountPeerId: accountPeerId, key: CustomKey.showDeleted, defaultValue: true),
            saveEditHistory: customScopedBool(accountPeerId: accountPeerId, key: CustomKey.saveEditHistory, defaultValue: true),
            showEditHistory: customScopedBool(accountPeerId: accountPeerId, key: CustomKey.showEditHistory, defaultValue: true),
            hideBlockedMessages: customScopedBool(accountPeerId: accountPeerId, key: CustomKey.hideBlockedMessages, defaultValue: true),
            hideBlockedReactions: customScopedBool(accountPeerId: accountPeerId, key: CustomKey.hideBlockedReactions, defaultValue: true),
            sendTextStyle: customScopedString(accountPeerId: accountPeerId, key: 
                customSendTextStyleKey,
                defaultValue: "normal"
            ),
            deletedPortableReplies: customScopedBool(accountPeerId: accountPeerId, key: 

                CustomKey.deletedPortableReplies,

                defaultValue: true

            ),

            preserveDeletedMedia: customScopedBool(accountPeerId: accountPeerId, key: 

                CustomKey.preserveDeletedMedia,

                defaultValue: true

            ),

            messageSeconds: customScopedBool(accountPeerId: accountPeerId, key: 
                CustomKey.messageSeconds,
                defaultValue: false
            ),
            messageCharacterCount: customScopedBool(accountPeerId: accountPeerId, key:
                CustomKey.messageCharacterCount,
                defaultValue: false
            ),
            hideOwnPhone: customScopedBool(accountPeerId: accountPeerId, key: 
                CustomKey.hideOwnPhone,
                defaultValue: false
            ),
            protectedEnabled: customScopedBool(accountPeerId: accountPeerId, key: CustomKey.protectedEnabled, defaultValue: true),
            protectedGalleryShare: customScopedBool(accountPeerId: accountPeerId, key: CustomKey.protectedGalleryShare, defaultValue: true),
            protectedGallerySave: customScopedBool(accountPeerId: accountPeerId, key: CustomKey.protectedGallerySave, defaultValue: true),
            protectedGalleryCopy: customScopedBool(accountPeerId: accountPeerId, key: CustomKey.protectedGalleryCopy, defaultValue: true),
            chatSave: customScopedBool(accountPeerId: accountPeerId, key: CustomKey.chatSave, defaultValue: true),
            chatCopy: customScopedBool(accountPeerId: accountPeerId, key: CustomKey.chatCopy, defaultValue: true),
            chatForward: customScopedBool(accountPeerId: accountPeerId, key: CustomKey.chatForward, defaultValue: true),
            allowScreenshots: customScopedBool(accountPeerId: accountPeerId, key: CustomKey.allowScreenshots, defaultValue: true),
            allowScreenRecording: customScopedBool(accountPeerId: accountPeerId, key: CustomKey.allowScreenRecording, defaultValue: true),
            oneTimeScreenshots: customScopedBool(accountPeerId: accountPeerId, key: CustomKey.oneTimeScreenshots, defaultValue: false),
            oneTimeScreenRecording: customScopedBool(accountPeerId: accountPeerId, key: CustomKey.oneTimeScreenRecording, defaultValue: false),
            oneTimeSave: customScopedBool(accountPeerId: accountPeerId, key: CustomKey.oneTimeSave, defaultValue: false),
            storySave: customScopedBool(accountPeerId: accountPeerId, key: CustomKey.storySave, defaultValue: false),
            showRestricted: customScopedBool(accountPeerId: accountPeerId, key: CustomKey.showRestricted, defaultValue: true),
            removeAds: customScopedBool(accountPeerId: accountPeerId, key: CustomKey.removeAds, defaultValue: false),
            localStarsEnabled: customScopedBool(accountPeerId: accountPeerId, key: CustomKey.localStarsEnabled, defaultValue: false),
            localStarsAmount: customScopedString(accountPeerId: accountPeerId, key: CustomKey.localStarsAmount, defaultValue: "0"),
            localStarsBaseAmount: customScopedString(accountPeerId: accountPeerId, key: CustomKey.localStarsBaseAmount, defaultValue: "0")
        )
    }

    func save(accountPeerId: Int64) {
        customPersistChangedSettings(accountPeerId: accountPeerId, previous: nil, current: self)
    }
}


private func customSettingsMenuIcon(
    _ name: String
) -> UIImage? {
    let background: UInt32

    switch name {
    case "Custom/Settings/Airplane":
        background = 0x53606A
    case "Chat/Context Menu/Eye":
        background = 0x4B5064
    case "Chat/Context Menu/MessageBubble":
        background = 0x4B6F83
    case "Premium/CopyProtection/NoForward":
        background = 0x87452F
    case "Item List/Icons/Stories":
        background = 0x6A5C78
    case "Chat/Context Menu/ApplyTheme":
        background = 0x676C43
    case "Chat/Context Menu/FormatCode":
        background = 0x8A6138
    case "Chat/Context Menu/Info":
        background = 0x4B4F54

    default:
        return nil
    }

    return renderSettingsIcon(
        name: name,
        scaleFactor: 1.0,
        backgroundColors: [
            UIColor(
                rgb: background
            )
        ]
    )
}

private func customAboutMenuIcon(
    _ name: String
) -> UIImage? {
    let background: UInt32

    switch name {
    case "Custom/About/GitHub":
        background = 0x4E5259
    case "Custom/About/Channel":
        background = 0x5B8FB5
    case "Custom/About/Bot":
        background = 0x6A9B72
    default:
        return nil
    }

    return renderSettingsIcon(
        name: name,
        scaleFactor: 1.0,
        backgroundColors: [
            UIColor(
                rgb: background
            )
        ]
    )
}

enum CustomSettingsPage: Equatable {
    case root
    case search
    case dataAndBackup
    case stars
    case extras
    case home
    case invisibleMode
    case messages
    case protectedContent
    case mediaStories
    case appearance
    case debugResearch
    case about
    case debugConsole
    case database

    var title: String {
        switch self {
        case .root:
            return "Settings"
        case .search:
            return "Search"
        case .dataAndBackup:
            return "Data and Backup"
        case .stars:
            return "Stars"
        case .extras:
            return "Extras"
        case .home:
            return "Info Display"
        case .invisibleMode:
            return "Invisible Mode"
        case .messages:
            return "Messages"
        case .protectedContent:
            return "Protected Content"
        case .mediaStories:
            return "Media & Stories"
        case .appearance:
            return "Appearance"
        case .debugResearch:
            return "Debug / Research"
        case .about:
            return "About"
        case .debugConsole:
            return "Debug Console"
        case .database:
            return "Database"
        }
    }


    func localizedTitle(_ strings: CustomStrings) -> String {
        switch self {
        case .root:
            return strings.settingsTitle
        case .search:
            return strings.searchSettings
        case .dataAndBackup:
            return strings.dataAndBackup
        case .extras:
            return strings.extras
        case .stars:
            return strings.starsBalance
        case .home:
            return strings.infoDisplay
        case .invisibleMode:
            return strings.invisibleMode
        case .messages:
            return strings.messages
        case .protectedContent:
            return strings.protectedContent
        case .mediaStories:
            return strings.mediaAndStories
        case .appearance:
            return strings.appearance
        case .debugResearch:
            return strings.debugResearch
        case .about:
            return strings.about
        case .debugConsole:
            return strings.debugConsole
        case .database:
            return strings.databaseTitle
        }
    }
}

private final class CustomSettingsArguments {
    let context: AccountContext
    let openAboutChannel: (EnginePeer) -> Void
    let runResearchAction: (String) -> Void
    let updateBool: (String, Bool) -> Void
    let openPage: (CustomSettingsPage) -> Void
    let openSendTextStyle: () -> Void

    init(
        context: AccountContext,
        openAboutChannel: @escaping (EnginePeer) -> Void,
        runResearchAction: @escaping (String) -> Void,
        updateBool: @escaping (String, Bool) -> Void,
        openPage: @escaping (CustomSettingsPage) -> Void,
        openSendTextStyle: @escaping () -> Void
    ) {
        self.context = context
        self.openAboutChannel = openAboutChannel
        self.runResearchAction = runResearchAction
        self.updateBool = updateBool
        self.openPage = openPage
        self.openSendTextStyle = openSendTextStyle
    }
}

private enum CustomSettingsSection: Int32 {
    case profileMetrics
    case invisibleMode
    case protectedContent
    case stars
    case debug
    case footer
}

// Shared visual contract used by every internal Custom destination.
private func CustomSettingsSectionHeaderItem(
    presentationData: ItemListPresentationData,
    text: String,
    sectionId: ItemListSectionId
) -> ListViewItem {
    return ItemListSectionHeaderItem(
        presentationData: presentationData,
        text: text.uppercased(),
        sectionId: sectionId
    )
}

private func CustomSettingsStatusItem(
    presentationData: ItemListPresentationData,
    text: String,
    sectionId: ItemListSectionId
) -> ListViewItem {
    return ItemListTextItem(
        presentationData: presentationData,
        text: .plain(text),
        sectionId: sectionId
    )
}



private enum CustomSettingsEntry: ItemListNodeEntry {
    case aboutValue(Int32, Int32, String, String)
    case header(Int32, String)
    case toggle(Int32, Int32, String, String, Bool)
    case toggleHint(Int32, Int32, String, String, String, Bool)
    case input(Int32, Int32, String, String, String)
    case disclosure(Int32, Int32, String, String, CustomSettingsPage)
    case disclosureDetail(Int32, Int32, String, String, String, CustomSettingsPage)
    case valueDisclosure(Int32, Int32, String, String, String?, CustomSettingsPage)
    case aboutLink(Int32, String, String, CustomSettingsPage)
    case aboutCard(Int32, Int32, String, String)
    case selector(Int32, Int32, String, String)
    case stylePreview(Int32, Int32, String)
    case aboutChannel(Int32, Int32, String, EnginePeer?, String, Bool)
    case researchAction(Int32, Int32, String, String)
    case actionValue(Int32, Int32, String, String, String)
    case researchInfo(Int32, Int32, String)
    case info(Int32, String)

    var section: ItemListSectionId {
        switch self {
        case let .header(section, _):
            return section
        case let .aboutValue(section, _, _, _):
            return section
        case let .toggle(section, _, _, _, _):
            return section
        case let .toggleHint(section, _, _, _, _, _):
            return section
        case let .input(section, _, _, _, _):
            return section
        case let .disclosure(section, _, _, _, _):
            return section
        case let .disclosureDetail(section, _, _, _, _, _):
            return section
        case let .valueDisclosure(section, _, _, _, _, _):
            return section
        case let .aboutLink(section, _, _, _):
            return section
        case let .aboutCard(section, _, _, _):
            return section
        case let .selector(section, _, _, _):
            return section
        case let .stylePreview(section, _, _):
            return section
        case let .aboutChannel(section, _, _, _, _, _):
            return section
        case let .researchAction(section, _, _, _):
            return section
        case let .actionValue(section, _, _, _, _):
            return section
        case let .researchInfo(section, _, _):
            return section
        case let .info(section, _):
            return section
        }
    }

    var stableId: Int32 {
        switch self {
        case let .header(section, _):
            return section * 1000
        case let .aboutValue(section, index, _, _):
            return section * 1000 + index
        case let .toggle(section, index, _, _, _):
            return section * 1000 + index
        case let .toggleHint(section, index, _, _, _, _):
            return section * 1000 + index
        case let .input(section, index, _, _, _):
            return section * 1000 + index
        case let .disclosure(section, index, _, _, _):
            return section * 1000 + index
        case let .disclosureDetail(section, index, _, _, _, _):
            return section * 1000 + index
        case let .valueDisclosure(section, index, _, _, _, _):
            return section * 1000 + index
        case let .aboutLink(section, _, _, _):
            return section * 1000 + 500
        case let .aboutCard(section, index, _, _):
            return section * 1000 + index
        case let .selector(section, index, _, _):
            return section * 1000 + index
        case let .stylePreview(section, index, _):
            return section * 1000 + index
        case let .aboutChannel(section, index, _, _, _, _):
            return section * 1000 + index
        case let .researchAction(section, index, _, _):
            return section * 1000 + index
        case let .actionValue(section, index, _, _, _):
            return section * 1000 + index
        case let .researchInfo(section, index, _):
            return section * 1000 + index
        case let .info(section, _):
            return section * 1000 + 999
        }
    }

    static func ==(lhs: CustomSettingsEntry, rhs: CustomSettingsEntry) -> Bool {
        switch lhs {
        case let .header(ls, lt):
            if case let .header(rs, rt) = rhs {
                return ls == rs && lt == rt
            }
            return false
        case let .aboutValue(ls, li, lt, lv):
            if case let .aboutValue(rs, ri, rt, rv) = rhs {
                return ls == rs && li == ri && lt == rt && lv == rv
            }
            return false
        case let .toggle(ls, li, lk, lt, lv):
            if case let .toggle(rs, ri, rk, rt, rv) = rhs {
                return ls == rs && li == ri && lk == rk && lt == rt && lv == rv
            }
            return false
        case let .toggleHint(ls, li, lk, lt, lh, lv):
            if case let .toggleHint(rs, ri, rk, rt, rh, rv) = rhs {
                return ls == rs && li == ri && lk == rk && lt == rt && lh == rh && lv == rv
            }
            return false
        case let .input(ls, li, lk, lt, lv):
            if case let .input(rs, ri, rk, rt, rv) = rhs {
                return ls == rs && li == ri && lk == rk && lt == rt && lv == rv
            } else {
                return false
            }
        case let .disclosure(ls, li, lt, lIcon, lPage):
            if case let .disclosure(rs, ri, rt, rIcon, rPage) = rhs {
                return ls == rs
                    && li == ri
                    && lt == rt
                    && lIcon == rIcon
                    && lPage.title == rPage.title
            }
            return false
        case let .disclosureDetail(ls, li, lt, lSub, lIcon, lPage):
            if case let .disclosureDetail(rs, ri, rt, rSub, rIcon, rPage) = rhs {
                return ls == rs
                    && li == ri
                    && lt == rt
                    && lSub == rSub
                    && lIcon == rIcon
                    && lPage.title == rPage.title
            }
            return false
        case let .selector(ls, li, lt, lv):
            if case let .selector(rs, ri, rt, rv) = rhs {
                return ls == rs && li == ri
                    && lt == rt && lv == rv
            }
            return false
        case let .stylePreview(ls, li, lv):
            if case let .stylePreview(rs, ri, rv) = rhs {
                return ls == rs && li == ri && lv == rv
            }
            return false
        case let .aboutChannel(ls, li, lt, lp, lv, ll):
            if case let .aboutChannel(rs, ri, rt, rp, rv, rl) = rhs {
                return ls == rs && li == ri && lt == rt
                    && lp == rp && lv == rv && ll == rl
            }
            return false
        case let .researchAction(ls, li, lt, la):
            if case let .researchAction(rs, ri, rt, ra) = rhs {
                return ls == rs && li == ri && lt == rt && la == ra
            }
            return false
        case let .actionValue(ls, li, lt, lv, la):
            if case let .actionValue(rs, ri, rt, rv, ra) = rhs {
                return ls == rs && li == ri && lt == rt && lv == rv && la == ra
            }
            return false
        case let .researchInfo(ls, li, lt):
            if case let .researchInfo(rs, ri, rt) = rhs {
                return ls == rs && li == ri && lt == rt
            }
            return false
        case let .valueDisclosure(ls, li, lt, lv, lIcon, lPage):
            if case let .valueDisclosure(rs, ri, rt, rv, rIcon, rPage) = rhs {
                return ls == rs && li == ri && lt == rt && lv == rv
                    && lIcon == rIcon && lPage.title == rPage.title
            }
            return false
        case let .aboutLink(ls, lt, lsub, lPage):
            if case let .aboutLink(rs, rt, rsub, rPage) = rhs {
                return ls == rs && lt == rt && lsub == rsub && lPage.title == rPage.title
            }
            return false
        case let .aboutCard(ls, li, lt, lIcon):
            if case let .aboutCard(rs, ri, rt, rIcon) = rhs {
                return ls == rs && li == ri && lt == rt && lIcon == rIcon
            }
            return false
        case let .info(ls, lt):
            if case let .info(rs, rt) = rhs {
                return ls == rs && lt == rt
            }
            return false
        }
    }

    static func <(lhs: CustomSettingsEntry, rhs: CustomSettingsEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! CustomSettingsArguments

        switch self {
        case let .header(_, text):
            return CustomSettingsSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)

        case let .input(_, _, _, title, text):
            return ItemListSingleLineInputItem(
                presentationData: presentationData,
                title: NSAttributedString(string: title, textColor: presentationData.theme.list.itemPrimaryTextColor),
                text: text,
                placeholder: "0",
                type: .regular(capitalization: false, autocorrection: false),
                returnKeyType: .done,
                alignment: .right,
                spacing: 16.0,
                clearType: .onFocus,
                maxLength: 20,
                selectAllOnFocus: true,
                sectionId: self.section,
                // dedicated Stars editor keeps a local draft and commits on Save.
                textUpdated: { _ in },
                shouldUpdateText: { updatedText in
                    return customIsValidStarsAmountInput(updatedText)
                },
                action: {}
            )

        case let .aboutValue(_, _, title, value):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: title,
                label: value,
                labelStyle: .text,
                sectionId: self.section,
                style: .blocks,
                disclosureStyle: .none,
                action: nil
            )

        case let .toggle(_, _, key, title, value):
            return ItemListSwitchItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: title,
                value: value,
                sectionId: self.section,
                style: .blocks,
                updated: { updatedValue in
                    arguments.updateBool(key, updatedValue)
                }
            )

        case let .toggleHint(_, _, key, title, hint, value):
            return ItemListSwitchItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: title,
                text: hint,
                value: value,
                maximumNumberOfLines: 3,
                sectionId: self.section,
                style: .blocks,
                updated: { updatedValue in
                    arguments.updateBool(key, updatedValue)
                }
            )

        case let .disclosureDetail(_, _, title, subtitle, iconName, page):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                icon: customSettingsMenuIcon(iconName),
                title: title,
                label: subtitle,
                labelStyle: .detailText,
                sectionId: self.section,
                style: .blocks,
                disclosureStyle: .arrow,
                action: {
                    arguments.openPage(page)
                }
            )

        case let .disclosure(_, _, title, iconName, page):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                icon: customSettingsMenuIcon(iconName),
                title: title,
                label: "",
                labelStyle: .text,
                sectionId: self.section,
                style: .blocks,
                disclosureStyle: .arrow,
                action: {
                    arguments.openPage(page)
                }
            )

        case let .selector(_, _, title, value):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: title,
                label: "",
                attributedLabel: customSendStyleAttributedText(
                    style: value,
                    text: customSendTextStyleTitle(
                    value,
                    strings: presentationData.strings.custom
                ),
                    color: presentationData.theme.list.itemSecondaryTextColor,
                    size: 15.0
                ),
                labelStyle: .text,
                sectionId: self.section,
                style: .blocks,
                disclosureStyle: .arrow,
                action: {
                    arguments.openSendTextStyle()
                },
                tag: CustomSettingsEntryTag.sendTextStyle
            )

        case let .stylePreview(_, _, value):
            let line = NSMutableAttributedString(
                string: presentationData.strings.custom.sendStyleExamplePrefix,
                attributes: [
                    .font: UIFont.systemFont(ofSize: 15.0),
                    .foregroundColor:
                        presentationData.theme.list.itemPrimaryTextColor
                ]
            )

            line.append(
                customSendStyleAttributedText(
                    style: value,
                    text: presentationData.strings.custom.sendStyleExampleBody,
                    color: presentationData.theme.list.itemPrimaryTextColor,
                    size: 15.0
                )
            )

            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: "",
                attributedTitle: line,
                label: "",
                labelStyle: .text,
                sectionId: self.section,
                style: .blocks,
                disclosureStyle: .none,
                action: nil
            )

        case let .aboutChannel(_, _, title, peer, preview, _):
            if let peer {
                return ItemListPeerItem(
                    presentationData: presentationData,
                    systemStyle: .glass,
                    dateTimeFormat: PresentationDateTimeFormat(),
                    nameDisplayOrder: .firstLast,
                    context: arguments.context,
                    peer: peer,
                    height: .peerList,
                    aliasHandling: .standard,
                    nameStyle: .plain,
                    presence: nil,
                    text: .text(preview, .secondary),
                    label: .none,
                    editing: ItemListPeerItemEditing(
                        editable: false,
                        editing: false,
                        revealed: false
                    ),
                    switchValue: nil,
                    enabled: true,
                    selectable: true,
                    sectionId: self.section,
                    action: {
                        arguments.openAboutChannel(peer)
                    },
                    setPeerIdWithRevealedOptions: { _, _ in },
                    removePeer: { _ in }
                )
            } else {
                return ItemListDisclosureItem(
                    presentationData: presentationData,
                    systemStyle: .glass,
                    title: title,
                    label: preview,
                    labelStyle: .text,
                    sectionId: self.section,
                    style: .blocks,
                    disclosureStyle: .none,
                    action: nil
                )
            }

        case let .researchAction(_, _, title, actionId):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: title,
                label: "",
                labelStyle: .text,
                sectionId: self.section,
                style: .blocks,
                disclosureStyle: actionId.hasPrefix("https://") ? .arrow : .none,
                action: {
                    arguments.runResearchAction(actionId)
                }
            )

        case let .actionValue(_, _, title, value, actionId):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: title,
                label: value,
                labelStyle: .text,
                sectionId: self.section,
                style: .blocks,
                disclosureStyle: .none,
                action: {
                    arguments.runResearchAction(actionId)
                }
            )

        case let .researchInfo(_, _, text):
            return CustomSettingsStatusItem(presentationData: presentationData, text: text, sectionId: self.section)

        case let .valueDisclosure(_, _, title, value, iconName, page):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                icon: iconName.flatMap { UIImage(bundleImageName: $0) },
                title: title,
                label: value,
                labelStyle: .text,
                sectionId: self.section,
                style: .blocks,
                disclosureStyle: .arrow,
                action: {
                    arguments.openPage(page)
                }
            )

        case let .aboutLink(_, title, subtitle, page):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: title,
                label: subtitle,
                labelStyle: .detailText,
                sectionId: self.section,
                style: .blocks,
                disclosureStyle: .arrow,
                action: {
                    arguments.openPage(page)
                }
            )

        case let .aboutCard(_, _, title, iconName):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                icon: customAboutMenuIcon(iconName),
                title: title,
                label: "",
                labelStyle: .text,
                sectionId: self.section,
                style: .blocks,
                disclosureStyle: .none,
                action: nil
            )

        case let .info(_, text):
            return CustomSettingsStatusItem(presentationData: presentationData, text: text, sectionId: self.section)
        }
    }
}



private let customHiddenGiftItems: [(String, Int64)] = [
    ("New Year Bear", 5956217000635139069),
    ("Christmas Tree", 5922558454332916696),
    ("Valentine Bear", 5800655655995968830),
    ("March 8 Bear", 5866352046986232958),
    ("Valentine Card", 5801108895304779062),
    ("Leprechaun Bear", 5893356958802511476),
    ("April 1 Bear", 5935895822435615975),
    ("Easter Bear", 5969796561943660080),
    ("Builder Bear", 6026193266406327981)
]

private let customHiddenGiftsPrefix =
    "custom.Research.HiddenGifts."

private struct CustomHiddenGiftFormProbeResult {
    let total: Int64?
    let text: String
}

private func customHiddenGiftCheckText(
    _ result: CanSendGiftResult
) -> String {
    switch result {
    case .available:
        return "available"
    case let .unavailable(text, _):
        return text.isEmpty
            ? "unavailable"
            : "unavailable: \(text)"
    case .failed:
        return "failed"
    }
}

private func customHiddenGiftPaymentErrorText(
    _ error: BotPaymentFormRequestError
) -> String {
    switch error {
    case .generic:
        return "generic"
    case .alreadyActive:
        return "alreadyActive"
    case .noPaymentNeeded:
        return "noPaymentNeeded"
    case .disallowedStarGift:
        return "disallowedStarGift"
    case let .starGiftResellTooEarly(timeout):
        return "starGiftResellTooEarly(\(timeout))"
    case .starGiftUserLimit:
        return "starGiftUserLimit"
    }
}

private func customHiddenGiftDateText(
    _ value: Int32?
) -> String {
    guard let value else {
        return "nil"
    }

    let date = Date(timeIntervalSince1970: TimeInterval(value))
    return "\(value) / \(ISO8601DateFormatter().string(from: date))"
}

private func customHiddenGiftCatalogText(
    index: Int,
    gift: StarGift.Gift
) -> String {
    var flags: [String] = []

    if gift.flags.contains(.isBirthdayGift) {
        flags.append("birthday")
    }
    if gift.flags.contains(.requiresPremium) {
        flags.append("requiresPremium")
    }
    if gift.flags.contains(.peerColorAvailable) {
        flags.append("peerColorAvailable")
    }
    if gift.flags.contains(.isAuction) {
        flags.append("auction")
    }

    let availability: String
    if let value = gift.availability {
        availability = """
        remains=\(value.remains)
        total=\(value.total)
        resale=\(value.resale)
        minResaleStars=\(value.minResaleStars.map(String.init) ?? "nil")
        """
    } else {
        availability = "nil"
    }

    let soldOut: String
    if let value = gift.soldOut {
        soldOut = """
        firstSale=\(customHiddenGiftDateText(value.firstSale))
        lastSale=\(customHiddenGiftDateText(value.lastSale))
        """
    } else {
        soldOut = "nil"
    }

    let perUserLimit: String
    if let value = gift.perUserLimit {
        perUserLimit =
            "remains=\(value.remains), total=\(value.total)"
    } else {
        perUserLimit = "nil"
    }

    let background: String
    if let value = gift.background {
        background = """
        center=\(value.centerColor)
        edge=\(value.edgeColor)
        text=\(value.textColor)
        """
    } else {
        background = "nil"
    }

    return """
    catalog: present
    catalogIndex: \(index)
    title: \(gift.title ?? "nil")
    fileId: \(gift.file.fileId.id)
    fileNamespace: \(gift.file.fileId.namespace)
    price: \(gift.price)
    convertStars: \(gift.convertStars)
    flags: \(flags.isEmpty ? "none" : flags.joined(separator: ","))
    availability:
    \(availability)
    soldOut:
    \(soldOut)
    upgradeStars: \(gift.upgradeStars.map(String.init) ?? "nil")
    upgradeVariantsCount: \(gift.upgradeVariantsCount.map(String.init) ?? "nil")
    releasedBy: \(gift.releasedBy.map { String(describing: $0) } ?? "nil")
    perUserLimit: \(perUserLimit)
    lockedUntilDate: \(customHiddenGiftDateText(gift.lockedUntilDate))
    auctionSlug: \(gift.auctionSlug ?? "nil")
    auctionGiftsPerRound: \(gift.auctionGiftsPerRound.map(String.init) ?? "nil")
    auctionStartDate: \(customHiddenGiftDateText(gift.auctionStartDate))
    background:
    \(background)
    """
}

private func customHiddenGiftsReport() -> String {
    let defaults = UserDefaults.standard

    let status = defaults.string(
        forKey: customHiddenGiftsPrefix + "Status"
    ) ?? "not tested"

    let target = defaults.string(
        forKey: customHiddenGiftsPrefix + "Target"
    ) ?? "none"

    let updated = defaults.string(
        forKey: customHiddenGiftsPrefix + "Updated"
    ) ?? "none"

    let report = defaults.string(
        forKey: customHiddenGiftsPrefix + "Report"
    ) ?? "Результатов пока нет."

    return """
    Status: \(status)
    Target: \(target)
    Updated: \(updated)

    \(report)
    """
}


private struct CustomHiddenGiftSendState {
    var giftName: String?
    var giftId: Int64?
    var targetPeerId: EnginePeer.Id?
    var targetLabel: String?
    var hideName: Bool = false
    var firstConfirmed: Bool = false
    var isSending: Bool = false
    var status: String = "Выберите подарок и получателя."
}

private var customHiddenGiftSendState =
    CustomHiddenGiftSendState()

private func customHiddenGiftSendSummary() -> String {
    let state = customHiddenGiftSendState

    let gift: String
    if let giftName = state.giftName,
       let giftId = state.giftId {
        gift = "\(giftName)\nID: \(giftId)"
    } else {
        gift = "не выбран"
    }

    let target =
        state.targetLabel
        ?? "не выбран"

    let anonymity =
        state.hideName
        ? "имя отправителя скрыто"
        : "имя отправителя открыто"

    let confirmation: String
    if state.isSending {
        confirmation = "выполняется платёжный запрос"
    } else if state.firstConfirmed {
        confirmation =
            "первое подтверждение принято; требуется списание"
    } else {
        confirmation = "не подтверждено"
    }

    return """
    Подарок:
    \(gift)

    Получатель:
    \(target)

    Цена:
    строго 50 XTR

    Отправитель:
    \(anonymity)

    Подтверждение:
    \(confirmation)

    Статус:
    \(state.status)
    """
}

private func customHiddenGiftSendErrorText(
    _ error: SendBotPaymentFormError
) -> String {
    switch error {
    case .generic:
        return "generic"
    case .precheckoutFailed:
        return "precheckoutFailed"
    case .paymentFailed:
        return "paymentFailed"
    case .alreadyPaid:
        return "alreadyPaid"
    case .starGiftOutOfStock:
        return "starGiftOutOfStock"
    case .disallowedStarGift:
        return "disallowedStarGift"
    case .starGiftUserLimit:
        return "starGiftUserLimit"
    case let .serverProvided(value):
        return "serverProvided: \(value)"
    }
}

private func customHiddenGiftSendResultText(
    _ result: SendBotPaymentResult
) -> String {
    switch result {
    case .done:
        return "SUCCESS: подарок отправлен, 50 Stars списаны."
    case let .externalVerificationRequired(url):
        return """
        externalVerificationRequired
        URL не открыт автоматически:
        \(url)
        """
    }
}


private let customBotCapabilityPrefix =
    "custom.Research.BotCapability."

private func customBotCapabilityReport() -> String {
    let defaults = UserDefaults.standard

    let status = defaults.string(
        forKey: customBotCapabilityPrefix + "Status"
    ) ?? "not tested"

    let updated = defaults.string(
        forKey: customBotCapabilityPrefix + "Updated"
    ) ?? "none"

    let report = defaults.string(
        forKey: customBotCapabilityPrefix + "Report"
    ) ?? "Результатов пока нет."

    return """
    Status: \(status)
    Updated: \(updated)

    \(report)
    """
}


private let customBotDifferencePrefix =
    "custom.Research.BotDifference."

private func customBotDifferenceReport() -> String {
    let defaults = UserDefaults.standard

    let status = defaults.string(
        forKey: customBotDifferencePrefix + "Status"
    ) ?? "not tested"

    let updated = defaults.string(
        forKey: customBotDifferencePrefix + "Updated"
    ) ?? "none"

    let report = defaults.string(
        forKey: customBotDifferencePrefix + "Report"
    ) ?? "Результатов пока нет."

    return """
    Status: \(status)
    Updated: \(updated)

    \(report)
    """
}


private let customProfileIntelPrefix =
    "custom.Research.ProfileIntel1."

private func customProfileIntelReport() -> String {
    let defaults = UserDefaults.standard

    let target = defaults.string(
        forKey: customProfileIntelPrefix + "Target"
    ) ?? "none"

    let status = defaults.string(
        forKey: customProfileIntelPrefix + "Status"
    ) ?? "not tested"

    let updated = defaults.string(
        forKey: customProfileIntelPrefix + "Updated"
    ) ?? "none"

    let current = defaults.string(
        forKey: customProfileIntelPrefix + "Report"
    ) ?? "Результатов пока нет."

    let previousUpdated = defaults.string(
        forKey: customProfileIntelPrefix + "PreviousUpdated"
    ) ?? "none"

    let previous = defaults.string(
        forKey: customProfileIntelPrefix + "PreviousReport"
    ) ?? "Предыдущего результата нет."

    return """
    Target: \(target)
    Status: \(status)
    Updated: \(updated)

    CURRENT
    \(current)

    PREVIOUS
    Updated: \(previousUpdated)
    \(previous)
    """
}


private let customProfileIntel2Prefix =
    "custom.Research.ProfileIntel2."

private func customProfileIntel2Report() -> String {
    let defaults = UserDefaults.standard
    let target = defaults.string(
        forKey: customProfileIntel2Prefix + "Target"
    ) ?? "none"
    let status = defaults.string(
        forKey: customProfileIntel2Prefix + "Status"
    ) ?? "not tested"
    let updated = defaults.string(
        forKey: customProfileIntel2Prefix + "Updated"
    ) ?? "none"
    let report = defaults.string(
        forKey: customProfileIntel2Prefix + "Report"
    ) ?? "Снимков пока нет."

    return """
    Target: \(target)
    Status: \(status)
    Updated: \(updated)

    \(report)
    """
}



private enum CustomAboutChannelState: Equatable {
    case loading
    case available(peer: EnginePeer, preview: String)
    case unavailable
}

private func customAboutChannelState(
    context: AccountContext,
    enabled: Bool,
    username: String?
) -> Signal<CustomAboutChannelState, NoError> {
    guard enabled, let username else {
        return .single(.unavailable)
    }

    return context.engine.peers.resolvePeerByName(name: username, referrer: nil)
    |> mapToSignal { result -> Signal<CustomAboutChannelState, NoError> in
        switch result {
        case .progress:
            return .single(.loading)
        case let .result(peer):
            guard let peer else {
                return .single(.unavailable)
            }

            let history = context.account.postbox
                .aroundMessageHistoryViewForLocation(
                    .peer(peerId: peer.id, threadId: nil),
                    anchor: .upperBound,
                    ignoreMessagesInTimestampRange: nil,
                    ignoreMessageIds: Set(),
                    count: 10,
                    clipHoles: false,
                    fixedCombinedReadStates: nil,
                    topTaggedMessageIdNamespaces: Set(),
                    tag: nil,
                    appendMessagesFromTheSameGroup: false,
                    namespaces: .not(Namespaces.Message.allNonRegular),
                    orderStatistics: []
                )
            let poll: Signal<Void, NoError> = .single(Void())
            |> then(
                context.account.viewTracker.polledChannel(peerId: peer.id)
            )

            return combineLatest(history, poll)
            |> map { viewData, _ -> CustomAboutChannelState in
                let (view, _, _) = viewData
                let raw = view.entries.last?.message.text ?? ""
                let compact = raw
                    .split(whereSeparator: { $0.isWhitespace })
                    .joined(separator: " ")
                return .available(
                    peer: peer,
                    preview: String(compact.prefix(160))
                )
            }
        }
    }
    |> distinctUntilChanged
}

private let customSettingsDidImportNotification = Notification.Name("CustomSettingsDidImport")

func customNotifySettingsImported(accountPeerId: Int64) {
    NotificationCenter.default.post(
        name: customSettingsDidImportNotification,
        object: nil,
        userInfo: ["accountPeerId": NSNumber(value: accountPeerId)]
    )
}

private func customSettingsImportRefreshSignal(
    accountPeerId: Int64,
    reload: @escaping () -> Void
) -> Signal<Void, NoError> {
    return Signal { subscriber in
        // Seed combineLatest immediately. The observer itself is retained only
        // by the controller state signal and is removed with that subscription.
        subscriber.putNext(())
        let observer = NotificationCenter.default.addObserver(
            forName: customSettingsDidImportNotification,
            object: nil,
            queue: OperationQueue.main,
            using: { notification in
                guard let rawAccountPeerId = notification.userInfo?["accountPeerId"] as? NSNumber,
                      rawAccountPeerId.int64Value == accountPeerId else {
                    return
                }
                reload()
            }
        )
        return ActionDisposable {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}

private func customSettingsEntries(
    state: CustomSettingsState,
    context: AccountContext,
    page: CustomSettingsPage,
    strings: CustomStrings,
    aboutChannelState: CustomAboutChannelState,
    aboutCommunityState: CustomAboutChannelState
) -> [CustomSettingsEntry] {
    var entries: [CustomSettingsEntry] = []

    let invisibleSection = CustomSettingsSection.invisibleMode.rawValue
    let protected = CustomSettingsSection.protectedContent.rawValue
    let stars = CustomSettingsSection.stars.rawValue
    let debug = CustomSettingsSection.debug.rawValue
    let footer = CustomSettingsSection.footer.rawValue



    if page == .root {
        // Telegram-native destination list; icons intentionally omitted.
        let version = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "12.9.2"
        return [
            .info(0, strings.appVersionLine(version)),
            .aboutLink(1, strings.about, strings.aboutHint, .about),
            .disclosureDetail(2, 0, strings.searchSettings, strings.searchSettingsHint, "", .search),
            .disclosureDetail(2, 1, strings.messages, strings.messagesHint, "", .messages),
            .disclosureDetail(2, 2, strings.invisibleMode, strings.invisibleModeHint, "", .invisibleMode),
            .disclosureDetail(2, 3, strings.extras, strings.extrasHint, "", .extras),
            .disclosureDetail(2, 4, strings.protectedContent, strings.protectedContentHint, "", .protectedContent),
            .disclosureDetail(2, 5, strings.infoDisplay, strings.infoDisplayHint, "", .home),
            .disclosureDetail(2, 6, strings.databaseTitle, strings.databaseHint, "", .database),
            .disclosureDetail(2, 7, strings.debugConsole, strings.debugConsoleHint, "", .debugConsole)
        ]
    }

    if page == .about {
        return [
            .aboutCard(0, 1, strings.aboutGithub, "Custom/About/GitHub"),
            .info(0, strings.aboutGithubNote),
            .aboutCard(1, 1, strings.aboutChannelLink, "Custom/About/Channel"),
            .info(1, strings.aboutChannelNote),
            .aboutCard(2, 1, strings.aboutBotLink, "Custom/About/Bot"),
            .info(2, strings.aboutBotNote)
        ]
    }

    if page == .home {
        return [
            .header(0, strings.profileInformation),
            .toggle(0, 1, CustomKey.profileEnabled, strings.showProfileInformation, state.profileEnabled),
            .toggle(0, 2, CustomKey.showIds, strings.telegramId, state.showIds),
            .toggle(0, 3, CustomKey.showDCs, strings.avatarDc, state.showDCs),
            .toggle(0, 4, CustomKey.showRegistration, strings.registrationDate, state.showRegistration),
            .header(1, strings.messages),
            .toggle(1, 40, CustomKey.messageSeconds, strings.messageSeconds, state.messageSeconds),
            .toggle(1, 41, CustomKey.messageCharacterCount, strings.messageCharacterCount, state.messageCharacterCount),
            .toggle(1, 42, CustomKey.hideOwnPhone, strings.hideMyPhone, state.hideOwnPhone),
            .info(1, strings.hidePhoneHint)
        ]
    }

    if page == .stars {
        let balance = state.localStarsAmount.isEmpty ? "0" : state.localStarsAmount
        return [
            .header(0, strings.starsBalance),
            .toggle(
                0, 1,
                CustomKey.localStarsEnabled,
                strings.localStarsBalance,
                state.localStarsEnabled
            ),
            .info(0, strings.starsOverrideSummary(state.localStarsEnabled, balance)),
            .header(1, strings.change),
            .input(
                1, 1,
                CustomKey.localStarsAmount,
                strings.starsBalance,
                state.localStarsAmount
            ),
            .info(1, strings.starsEditorHint)
        ]
    }

    if page == .invisibleMode {
        return [
            .header(0, strings.invisibleMode),
            .toggleHint(0, 1, CustomKey.presence, strings.hideOnline, strings.hideOnlineHint, state.presence),
            .toggleHint(0, 2, CustomKey.typingActions, strings.typing, strings.typingHint, state.typingActions),
            .toggleHint(0, 3, CustomKey.recordingActions, strings.recordingVoiceTitle, strings.recordingVoiceHint, state.recordingActions),
            .toggleHint(0, 4, CustomKey.uploadingActions, strings.uploadingVideoTitle, strings.uploadingVideoHint, state.uploadingActions),
            .toggleHint(0, 5, CustomKey.recordingVideo, strings.recordingVideoTitle, strings.recordingVideoHint, state.recordingVideo),
            .toggleHint(0, 6, CustomKey.uploadingVoice, strings.uploadingVoiceTitle, strings.uploadingVoiceHint, state.uploadingVoice),
            .toggleHint(0, 7, CustomKey.uploadingPhoto, strings.uploadingPhotoTitle, strings.uploadingPhotoHint, state.uploadingPhoto),
            .toggleHint(0, 8, CustomKey.uploadingFile, strings.uploadingFileTitle, strings.uploadingFileHint, state.uploadingFile),
            .toggleHint(0, 9, CustomKey.choosingLocation, strings.choosingLocationTitle, strings.choosingLocationHint, state.choosingLocation),
            .toggleHint(0, 10, CustomKey.choosingContact, strings.choosingContactTitle, strings.choosingContactHint, state.choosingContact),
            .toggleHint(0, 11, CustomKey.gameActivity, strings.gameActivityTitle, strings.gameActivityHint, state.gameActivity),
            .toggleHint(0, 12, CustomKey.recordingRound, strings.recordingRoundTitle, strings.recordingRoundHint, state.recordingRound),
            .toggleHint(0, 13, CustomKey.uploadingRound, strings.uploadingRoundTitle, strings.uploadingRoundHint, state.uploadingRound),
            .toggleHint(0, 14, CustomKey.speakingInGroupCall, strings.speakingGroupCallTitle, strings.speakingGroupCallHint, state.speakingInGroupCall),
            .toggleHint(0, 15, CustomKey.stickerActivity, strings.choosingStickerTitle, strings.choosingStickerHint, state.stickerActivity),
            .toggleHint(0, 16, CustomKey.emojiActivity, strings.emojiInteractionTitle, strings.emojiInteractionHint, state.emojiActivity),
            .toggleHint(0, 17, CustomKey.emojiAcknowledgement, strings.emojiAckTitle, strings.emojiAckHint, state.emojiAcknowledgement),

            .header(1, strings.readReceipts),
            .toggleHint(1, 1, CustomKey.readMessages, strings.messageReadReceipts, strings.messageReadReceiptsHint, state.readMessages),
            .toggleHint(1, 2, CustomKey.storyReadReceipts, strings.storyReadReceipts, strings.storyReadReceiptsHint, state.storyReadReceipts),

            .header(2, strings.other),
            .toggleHint(2, 1, CustomKey.scheduledSend, strings.scheduledSend, strings.scheduledSendHint, state.scheduledSend)
        ]
    }

    if page == .messages {
        return [
            .header(0, strings.deletedMessages),
            .toggle(0, 1, CustomKey.saveDeleted, strings.saveDeletedMessages, state.saveDeleted),
            .toggle(0, 2, CustomKey.showDeleted, strings.deletedMessages, state.showDeleted),

            .header(1, strings.editHistory),
            .toggle(1, 3, CustomKey.saveEditHistory, strings.saveEditHistory, state.saveEditHistory),
            .toggle(1, 4, CustomKey.showEditHistory, strings.editHistory, state.showEditHistory),

            .info(1, strings.savedDataHint),

            .header(2, strings.textSending),
            .selector(
                2,
                5,
                strings.sendStyle,
                state.sendTextStyle
            ),
            .stylePreview(
                2,
                6,
                state.sendTextStyle
            ),
            .info(
                2,
                strings.sendStyleHint
            ),
            .header(4, strings.deletedReplies),
            .toggle(
                4,
                90,
                CustomKey.deletedPortableReplies,
                strings.portableReply,
                state.deletedPortableReplies
            ),
            .toggle(
                4,
                91,
                CustomKey.preserveDeletedMedia,
                strings.saveDeletedMedia,
                state.preserveDeletedMedia
            ),
            .info(
                4,
                strings.portableReplyHint
            ),
        
            .header(5, strings.blockedUsers),
            .toggle(5, 1, CustomKey.hideBlockedMessages, strings.hideBlockedMessages, state.hideBlockedMessages),
            .toggle(5, 2, CustomKey.hideBlockedReactions, strings.hideBlockedReactions, state.hideBlockedReactions)]
    }

    if page == .protectedContent {
        return [
            .header(0, strings.protectedContent),
            .toggle(0, 1, CustomKey.protectedEnabled, strings.bypassAll, state.protectedEnabled),
            .info(0, strings.bypassAllHint),
            .toggle(0, 2, CustomKey.showRestricted, strings.showHiddenChats, state.showRestricted),
            .info(0, strings.showHiddenChatsHint),
            .toggle(0, 3, CustomKey.removeAds, strings.removeAds, state.removeAds),
            .info(0, strings.removeAdsHint)
        ]
    }

    if page == .mediaStories {
        return [
            .header(0, strings.mediaAndStories),
            .toggle(0, 1, CustomKey.oneTimeScreenshots, strings.oneTimeScreenshots, state.oneTimeScreenshots),
            .toggle(0, 2, CustomKey.oneTimeScreenRecording, strings.oneTimeScreenRecording, state.oneTimeScreenRecording),
            .toggle(0, 3, CustomKey.oneTimeSave, strings.oneTimeMedia, state.oneTimeSave),
            .toggle(0, 4, CustomKey.storySave, strings.storySave, state.storySave)
        ]
    }

    if page == .debugConsole {
        let logText = CustomDebugConsole.logText()
        // Cap the rendered text: a full log can be large, keep the most recent tail.
        let displayText = logText.count > 4000 ? "…" + String(logText.suffix(4000)) : logText
        return [
            .researchAction(0, 0, strings.debugConsoleCopy, "debug.copyLog"),
            .researchAction(0, 1, strings.debugConsoleClear, "debug.clearLog"),
            .researchInfo(1, 1, displayText.isEmpty ? strings.debugConsoleEmpty : displayText)
        ]
    }

    entries.append(.header(invisibleSection, strings.invisibleMode))
    entries.append(.toggle(invisibleSection, 1, CustomKey.readMessages, strings.readInvisible, state.readMessages))
    entries.append(.toggle(invisibleSection, 2, CustomKey.typingActions, "Hide Typing", state.typingActions))
    entries.append(.toggle(invisibleSection, 3, CustomKey.recordingActions, "Hide Recording", state.recordingActions))
    entries.append(.toggle(invisibleSection, 4, CustomKey.uploadingActions, "Hide Uploading", state.uploadingActions))
    entries.append(.toggle(invisibleSection, 5, CustomKey.stickerActivity, "Hide Sticker Activity", state.stickerActivity))
    entries.append(.toggle(invisibleSection, 6, CustomKey.gameActivity, "Hide Game Activity", state.gameActivity))
    entries.append(.toggle(invisibleSection, 7, CustomKey.emojiActivity, "Hide Emoji Activity", state.emojiActivity))
    entries.append(.toggle(invisibleSection, 8, CustomKey.presence, "Hide Online", state.presence))
    entries.append(.toggle(invisibleSection, 9, CustomKey.scheduledSend, strings.scheduledSend, state.scheduledSend))

    entries.append(.header(protected, strings.protectedContent))
    entries.append(.toggle(protected, 1, CustomKey.protectedEnabled, "Protected Content Bypass", state.protectedEnabled))
    entries.append(.toggle(protected, 2, CustomKey.protectedGalleryShare, "Gallery Share", state.protectedGalleryShare))
    entries.append(.toggle(protected, 3, CustomKey.protectedGallerySave, "Gallery Save", state.protectedGallerySave))
    entries.append(.toggle(protected, 4, CustomKey.protectedGalleryCopy, "Gallery Copy", state.protectedGalleryCopy))
    entries.append(.toggle(protected, 5, CustomKey.chatSave, "Chat Save", state.chatSave))
    entries.append(.toggle(protected, 6, CustomKey.chatCopy, "Chat Copy", state.chatCopy))
    entries.append(.toggle(protected, 7, CustomKey.chatForward, "Chat Forward", state.chatForward))
    entries.append(.toggle(protected, 8, CustomKey.allowScreenshots, strings.allowScreenshots, state.allowScreenshots))
    entries.append(.toggle(protected, 9, CustomKey.allowScreenRecording, strings.allowScreenRecording, state.allowScreenRecording))
    entries.append(.toggle(protected, 10, CustomKey.oneTimeScreenshots, "Allow One-Time Screenshots", state.oneTimeScreenshots))
    entries.append(.toggle(protected, 11, CustomKey.oneTimeScreenRecording, "One-Time Recording", state.oneTimeScreenRecording))
    entries.append(.toggle(protected, 12, CustomKey.oneTimeSave, "Allow One-Time Save", state.oneTimeSave))
    entries.append(.toggle(protected, 13, CustomKey.storySave, "Story Save", state.storySave))

    entries.append(.header(stars, "Stars"))
    entries.append(.toggle(stars, 1, CustomKey.localStarsEnabled, "Enable Local Stars Balance", state.localStarsEnabled))
    let customStarsDisplay = state.localStarsAmount.isEmpty ? "0" : state.localStarsAmount
    entries.append(.input(stars, 2, CustomKey.localStarsAmount, strings.localStarsBalance, state.localStarsAmount))
    entries.append(.info(stars, "Current visual balance: \(customStarsDisplay) ⭐"))
            let telegramId = String(context.account.peerId.id._internalGetInt64Value())
    let bundleId = Bundle.main.bundleIdentifier ?? "unknown"

    entries.append(.header(debug, "Debug"))
    let customPushPrefix = "custom..Push."
    let customPushDefaults = UserDefaults.standard

    entries.append(.info(debug, """
Main Push Registration Probe:
Total: \(customPushDefaults.integer(forKey: customPushPrefix + "Total"))
Last: \(customPushDefaults.string(forKey: customPushPrefix + "Last") ?? "none") x\(customPushDefaults.integer(forKey: customPushPrefix + "LastAmount")) @ \(customPushDefaults.integer(forKey: customPushPrefix + "LastTime"))
settingsRead: \(customPushDefaults.integer(forKey: customPushPrefix + "notificationSettingsRead.Count"))
authTrue: \(customPushDefaults.integer(forKey: customPushPrefix + "requestAuthorizationTrue.Count"))
authFalse: \(customPushDefaults.integer(forKey: customPushPrefix + "requestAuthorizationFalse.Count"))
authorizedRegister: \(customPushDefaults.integer(forKey: customPushPrefix + "authorizedRegisterForRemoteNotifications.Count"))
invalidationRegister: \(customPushDefaults.integer(forKey: customPushPrefix + "invalidationRegisterForRemoteNotifications.Count"))
didRegisterToken: \(customPushDefaults.integer(forKey: customPushPrefix + "didRegisterDeviceToken.Count"))
didFailToken: \(customPushDefaults.integer(forKey: customPushPrefix + "didFailRegisterDeviceToken.Count"))
registerDeviceEntry: \(customPushDefaults.integer(forKey: customPushPrefix + "registerDeviceEntry.Count"))
registerDeviceRequest: \(customPushDefaults.integer(forKey: customPushPrefix + "registerDeviceRequest.Count"))
registerDeviceSuccess: \(customPushDefaults.integer(forKey: customPushPrefix + "registerDeviceSuccess.Count"))
registerDeviceInvalidated: \(customPushDefaults.integer(forKey: customPushPrefix + "registerDeviceInvalidated.Count"))
registerDeviceError: \(customPushDefaults.integer(forKey: customPushPrefix + "registerDeviceError.Count"))
didReceiveRemote: \(customPushDefaults.integer(forKey: customPushPrefix + "didReceiveRemoteNotification.Count"))
remoteEncryptedPayload: \(customPushDefaults.integer(forKey: customPushPrefix + "remoteEncryptedPayload.Count"))
pushRegistryEncrypted: \(customPushDefaults.integer(forKey: customPushPrefix + "pushRegistryEncryptedPayload.Count"))
pushRegistryKeyId: \(customPushDefaults.integer(forKey: customPushPrefix + "pushRegistryKeyId.Count"))
pushRegistryKeyFound: \(customPushDefaults.integer(forKey: customPushPrefix + "pushRegistryNotificationKeyFound.Count"))
pushRegistryDecryptFailed: \(customPushDefaults.integer(forKey: customPushPrefix + "pushRegistryDecryptFailed.Count"))
pushRegistryDecrypted: \(customPushDefaults.integer(forKey: customPushPrefix + "pushRegistryDecryptedPayload.Count"))
pushRegistryJson: \(customPushDefaults.integer(forKey: customPushPrefix + "pushRegistryJson.Count"))
pushRegistryMsgId: \(customPushDefaults.integer(forKey: customPushPrefix + "pushRegistryMsgId.Count"))
LastAuthorizationStatus: \(customPushDefaults.string(forKey: customPushPrefix + "LastAuthorizationStatus") ?? "none")
LastRegisterFail: \(customPushDefaults.string(forKey: customPushPrefix + "LastRegisterFail") ?? "none")
LastRegisterDeviceType: \(customPushDefaults.string(forKey: customPushPrefix + "LastRegisterDeviceType") ?? "none")
LastRegisterDeviceSandbox: \(customPushDefaults.string(forKey: customPushPrefix + "LastRegisterDeviceSandbox") ?? "none")
LastRegisterDeviceError: \(customPushDefaults.string(forKey: customPushPrefix + "LastRegisterDeviceError") ?? "none")
LastUserInfoKeys: \(customPushDefaults.string(forKey: customPushPrefix + "LastUserInfoKeys") ?? "none")
LastAPSKeys: \(customPushDefaults.string(forKey: customPushPrefix + "LastAPSKeys") ?? "none")
LastPushRegistryKeys: \(customPushDefaults.string(forKey: customPushPrefix + "LastPushRegistryKeys") ?? "none")
LastPushRegistryPayloadKeys: \(customPushDefaults.string(forKey: customPushPrefix + "LastPushRegistryPayloadKeys") ?? "none")
Public main-app path: YES
NSE required: NO
"""))

    let customNsePrefix = "custom.V10D.NSE."
    let customNseDefaults = UserDefaults(suiteName: "group.ph.telegra.Telegraph") ?? UserDefaults.standard

    entries.append(.info(debug, """
Capture Mesh / NSE Probe:
AppGroup: \(customNseDefaults.string(forKey: customNsePrefix + "AppGroup") ?? "none")
Total: \(customNseDefaults.integer(forKey: customNsePrefix + "Total"))
Last: \(customNseDefaults.string(forKey: customNsePrefix + "Last") ?? "none") x\(customNseDefaults.integer(forKey: customNsePrefix + "LastAmount")) @ \(customNseDefaults.integer(forKey: customNsePrefix + "LastTime"))
didReceive: \(customNseDefaults.integer(forKey: customNsePrefix + "didReceive.Count"))
decryptedPayload: \(customNseDefaults.integer(forKey: customNsePrefix + "decryptedPayload.Count"))
payloadMsgId: \(customNseDefaults.integer(forKey: customNsePrefix + "payloadMsgId.Count"))
payloadPeerId: \(customNseDefaults.integer(forKey: customNsePrefix + "payloadPeerId.Count"))
initialBody: \(customNseDefaults.integer(forKey: customNsePrefix + "initialBody.Count"))
initialGenericBody: \(customNseDefaults.integer(forKey: customNsePrefix + "initialGenericBody.Count"))
finalBody: \(customNseDefaults.integer(forKey: customNsePrefix + "finalBody.Count"))
finalGenericBody: \(customNseDefaults.integer(forKey: customNsePrefix + "finalGenericBody.Count"))
LastLocKey: \(customNseDefaults.string(forKey: customNsePrefix + "LastLocKey") ?? "none")
LastPayloadKeys: \(customNseDefaults.string(forKey: customNsePrefix + "LastPayloadKeys") ?? "none")
LastFinalTitle: \(customNseDefaults.string(forKey: customNsePrefix + "LastFinalTitle") ?? "none")
LastFinalBody: \(customNseDefaults.string(forKey: customNsePrefix + "LastFinalBody") ?? "none")
"""))

    let customCorePrefix = "custom..Core."
    let customCoreDefaults = UserDefaults.standard

    entries.append(.info(debug, """
Core Difference Deep Probe:
Total: \(customCoreDefaults.integer(forKey: customCorePrefix + "Total"))
Last: \(customCoreDefaults.string(forKey: customCorePrefix + "Last") ?? "none") x\(customCoreDefaults.integer(forKey: customCorePrefix + "LastAmount")) @ \(customCoreDefaults.integer(forKey: customCorePrefix + "LastTime"))
diffRuns: \(customCoreDefaults.integer(forKey: customCorePrefix + "differenceRuns.Count"))
diffNewMessages: \(customCoreDefaults.integer(forKey: customCorePrefix + "differenceNewMessages.Count"))
diffOtherUpdates: \(customCoreDefaults.integer(forKey: customCorePrefix + "differenceOtherUpdates.Count"))
deleteEvents: \(customCoreDefaults.integer(forKey: customCorePrefix + "deleteMessagesEvents.Count"))
deleteIds: \(customCoreDefaults.integer(forKey: customCorePrefix + "deleteMessageIds.Count"))
lastDeleteIds: \(customCoreDefaults.integer(forKey: customCorePrefix + "LastDeleteIdsCount"))
lastDiffNewMessages: \(customCoreDefaults.integer(forKey: customCorePrefix + "LastDifferenceNewMessagesCount"))
lastDiffOtherUpdates: \(customCoreDefaults.integer(forKey: customCorePrefix + "LastDifferenceOtherUpdatesCount"))
lastDiffDeleteIds: \(customCoreDefaults.integer(forKey: customCorePrefix + "LastDifferenceDeleteMessageIdsCount"))
"""))


    let customRawPrefix = "custom..Raw."
    let customRawDefaults = UserDefaults.standard

    entries.append(.info(debug, """
v1.0Q Raw Delete Mapping:
QRawDeleteEvents: \(UserDefaults.standard.integer(forKey: "custom.V10Q.RawDeleteEvents"))
QLastRawDeleteSource: \(UserDefaults.standard.string(forKey: "custom.V10Q.LastRawDeleteSource") ?? "none")
QLastRawDeleteIdCount: \(UserDefaults.standard.integer(forKey: "custom.V10Q.LastRawDeleteIdCount"))
QLastMappedDeleteIdCount: \(UserDefaults.standard.integer(forKey: "custom.V10Q.LastMappedDeleteIdCount"))
QLastRawDeleteIds: \(UserDefaults.standard.string(forKey: "custom.V10Q.LastRawDeleteIds") ?? "none")
QLastMappedDeleteIds: \(UserDefaults.standard.string(forKey: "custom.V10Q.LastMappedDeleteIds") ?? "none")
QVerdict: \(UserDefaults.standard.string(forKey: "custom.V10Q.Verdict") ?? "none")

SH2 Standalone Share Scheduled:
SH2StandaloneScheduledIntercept: \(UserDefaults.standard.integer(forKey: "custom.SH2.StandaloneScheduledIntercept.Count"))
SH2LastStandalonePeerId: \(UserDefaults.standard.string(forKey: "custom.SH2.LastStandalonePeerId") ?? "none")
SH2LastStandaloneScheduleTime: \(UserDefaults.standard.integer(forKey: "custom.SH2.LastStandaloneScheduleTime"))

OT2 ViewOnce Visual Keep:
OT2ViewOnceVisibleKeep: \(UserDefaults.standard.integer(forKey: "custom.OT2.ViewOnceVisibleKeep.Count"))
OT2LastViewOnceVisibleId: \(UserDefaults.standard.string(forKey: "custom.OT2.LastViewOnceVisibleId") ?? "none")

v1.0P Pre-delete Shadow Trace:
PDeleteEvents: \(UserDefaults.standard.integer(forKey: "custom.V10P.DeleteEvents"))
PLastDeleteSource: \(UserDefaults.standard.string(forKey: "custom.V10P.LastDeleteSource") ?? "none")
PLastDeleteIdCount: \(UserDefaults.standard.integer(forKey: "custom.V10P.LastDeleteIdCount"))
PPreDeleteMessageHits: \(UserDefaults.standard.integer(forKey: "custom.V10P.PreDeleteMessageHits"))
PPreDeleteTextHits: \(UserDefaults.standard.integer(forKey: "custom.V10P.PreDeleteTextHits"))
PLastPreDeleteId: \(UserDefaults.standard.string(forKey: "custom.V10P.LastPreDeleteId") ?? "none")
PLastPreDeletePeer: \(UserDefaults.standard.string(forKey: "custom.V10P.LastPreDeletePeer") ?? "none")
PLastPreDeleteTextLength: \(UserDefaults.standard.integer(forKey: "custom.V10P.LastPreDeleteTextLength"))
PLastPreDeleteText: \(UserDefaults.standard.string(forKey: "custom.V10P.LastPreDeleteText") ?? "none")
PVerdict: \(UserDefaults.standard.string(forKey: "custom.V10P.Verdict") ?? "none")

SH1 Share Scheduled Send:
SH1ShareScheduledIntercept: \(UserDefaults.standard.integer(forKey: "custom.SH1.ShareScheduledIntercept.Count"))
SH1LastSharePeerId: \(UserDefaults.standard.string(forKey: "custom.SH1.LastSharePeerId") ?? "none")
SH1LastShareMessageCount: \(UserDefaults.standard.integer(forKey: "custom.SH1.LastShareMessageCount"))
SH1LastShareScheduleTime: \(UserDefaults.standard.integer(forKey: "custom.SH1.LastShareScheduleTime"))

OT1 Timer Media Local Keep:
OT1OutgoingKeepBlocked: \(UserDefaults.standard.integer(forKey: "custom.OT1.OutgoingKeepBlocked.Count"))
OT1AutoremoveKeepBlocked: \(UserDefaults.standard.integer(forKey: "custom.OT1.AutoremoveKeepBlocked.Count"))
OT1OutgoingKeepPath: \(UserDefaults.standard.string(forKey: "custom.OT1.OutgoingKeepPath") ?? "none")

v1.0O Persistent SourcePeer Candidate:
OSourcePeerPersistedRaw: \(UserDefaults.standard.object(forKey: "custom.V10O.Persistent.SourcePeerIdRaw") as? Int64 ?? 0)
OSourcePeerPersistedId: \(UserDefaults.standard.string(forKey: "custom.V10O.Persistent.SourcePeerId") ?? "none")
OSourcePeerPersistedSource: \(UserDefaults.standard.string(forKey: "custom.V10O.Persistent.SourcePeerSource") ?? "none")
OSourcePeerRuntimeRaw: \(customRawDefaults.string(forKey: customRawPrefix + "OSourcePeerRuntimeRaw") ?? "none")
OSourcePeerPersistedRawLastUse: \(customRawDefaults.string(forKey: customRawPrefix + "OSourcePeerPersistedRaw") ?? "none")
OSourcePeerUsedRaw: \(customRawDefaults.string(forKey: customRawPrefix + "OSourcePeerUsedRaw") ?? "none")
OSourcePeerCandidateStatus: \(customRawDefaults.string(forKey: customRawPrefix + "OSourcePeerCandidateStatus") ?? "none")

READ3 Runtime Probe:
R3UIPeerIdRaw: \(UserDefaults.standard.object(forKey: "custom.READ3.UI.PeerIdRaw") as? Int64 ?? 0)
R3UIMessageId: \(UserDefaults.standard.object(forKey: "custom.READ3.UI.MessageId") as? Int32 ?? 0)
R3UIPeerType: \(UserDefaults.standard.string(forKey: "custom.READ3.UI.PeerType") ?? "none")
R3UIParticipantCount: \(UserDefaults.standard.object(forKey: "custom.READ3.UI.ParticipantCount") as? Int ?? -2)
R3UIThreshold: \(UserDefaults.standard.object(forKey: "custom.READ3.UI.Threshold") as? Int ?? -1)
R3UIAction: \(UserDefaults.standard.string(forKey: "custom.READ3.UI.Action") ?? "none")
R3LastPeerIdRaw: \(UserDefaults.standard.object(forKey: "custom.READ3.LastPeerIdRaw") as? Int64 ?? 0)
R3LastMessageId: \(UserDefaults.standard.object(forKey: "custom.READ3.LastMessageId") as? Int32 ?? 0)
R3LastApi: \(UserDefaults.standard.string(forKey: "custom.READ3.LastApi") ?? "none")
R3LastResponse: \(UserDefaults.standard.string(forKey: "custom.READ3.LastResponse") ?? "none")
R3ForcedApiRawCount: \(UserDefaults.standard.object(forKey: "custom.READ3.ForcedApiRawCount") as? Int ?? -1)
R3ForcedCount: \(UserDefaults.standard.object(forKey: "custom.READ3.ForcedCount") as? Int ?? -1)
R3FirstUserId: \(UserDefaults.standard.object(forKey: "custom.READ3.FirstUserId") as? Int64 ?? 0)
R3FirstReadDate: \(UserDefaults.standard.object(forKey: "custom.READ3.FirstReadDate") as? Int32 ?? 0)
R3LastErrorRaw: \(UserDefaults.standard.string(forKey: "custom.READ3.LastErrorRaw") ?? "none")
R3FinalVerdict: \(UserDefaults.standard.string(forKey: "custom.READ3.FinalVerdict") ?? "none")

v1.0O SourcePeer Verdict:
NSourcePeerVerdict: \(customRawDefaults.string(forKey: customRawPrefix + "NSourcePeerVerdict") ?? "none")
NLastSourcePeerId: \(customRawDefaults.string(forKey: customRawPrefix + "NLastSourcePeerId") ?? "none")
NLastSourcePeerIdRaw: \(customRawDefaults.object(forKey: customRawPrefix + "NLastSourcePeerIdRaw") as? Int64 ?? 0)
NLastSourcePeerSource: \(customRawDefaults.string(forKey: customRawPrefix + "NLastSourcePeerSource") ?? "none")
NSourcePeerSaved: \(customRawDefaults.integer(forKey: customRawPrefix + "nSourcePeerSaved.Count"))

NSourcePeerCandidateStatus: \(customRawDefaults.string(forKey: customRawPrefix + "NSourcePeerCandidateStatus") ?? "none")
NSourcePeerPresent: \(customRawDefaults.integer(forKey: customRawPrefix + "nSourcePeerPresent.Count"))
NSourcePeerMissing: \(customRawDefaults.integer(forKey: customRawPrefix + "nSourcePeerMissing.Count"))
NSourcePeerInStatePeers: \(customRawDefaults.integer(forKey: customRawPrefix + "nSourcePeerInStatePeers.Count"))
NSourcePeerMissingFromStatePeers: \(customRawDefaults.integer(forKey: customRawPrefix + "nSourcePeerMissingFromStatePeers.Count"))

NSourcePeerHistoryResponse: \(customRawDefaults.integer(forKey: customRawPrefix + "nSourcePeerHistoryResponse.Count"))
NSourcePeerLastRequestedId: \(customRawDefaults.string(forKey: customRawPrefix + "NSourcePeerLastRequestedId") ?? "none")
NSourcePeerLastApiMessageCount: \(customRawDefaults.string(forKey: customRawPrefix + "NSourcePeerLastApiMessageCount") ?? "none")

NSourcePeerTargetHit: \(customRawDefaults.integer(forKey: customRawPrefix + "nSourcePeerTargetHit.Count"))
NSourcePeerNonExactTargetHit: \(customRawDefaults.integer(forKey: customRawPrefix + "nSourcePeerNonExactTargetHit.Count"))
NSourcePeerTargetMarker: \(customRawDefaults.string(forKey: customRawPrefix + "NSourcePeerTargetMarker") ?? "none")
NSourcePeerTargetText: \(customRawDefaults.string(forKey: customRawPrefix + "NSourcePeerTargetText") ?? "none")

NSourcePeerExactMessage: \(customRawDefaults.integer(forKey: customRawPrefix + "nSourcePeerExactMessage.Count"))
NSourcePeerExactEmpty: \(customRawDefaults.integer(forKey: customRawPrefix + "nSourcePeerExactEmpty.Count"))
NSourcePeerExactService: \(customRawDefaults.integer(forKey: customRawPrefix + "nSourcePeerExactService.Count"))
NSourcePeerExactTextLength: \(customRawDefaults.string(forKey: customRawPrefix + "NSourcePeerExactTextLength") ?? "none")
NSourcePeerExactText: \(customRawDefaults.string(forKey: customRawPrefix + "NSourcePeerExactText") ?? "none")

v1.0M Current Test Verdict:
MTargetVerdict: \(customRawDefaults.string(forKey: customRawPrefix + "MTargetVerdict") ?? "none")
MCurrentMarker: \(customRawDefaults.string(forKey: customRawPrefix + "MCurrentMarker") ?? "none")

MTargetSnapshotHit: \(customRawDefaults.integer(forKey: customRawPrefix + "mTargetSnapshotHit.Count"))
MTargetHistoryHit: \(customRawDefaults.integer(forKey: customRawPrefix + "mTargetHistoryHit.Count"))
MTargetExactHit: \(customRawDefaults.integer(forKey: customRawPrefix + "mTargetExactHit.Count"))
MTargetText: \(customRawDefaults.string(forKey: customRawPrefix + "MTargetText") ?? "none")
MTargetSnapshotText: \(customRawDefaults.string(forKey: customRawPrefix + "MTargetSnapshotText") ?? "none")

MFetchShapeCase: \(customRawDefaults.string(forKey: customRawPrefix + "MLastFetchShapeCase") ?? "none")
MFetchShapeId: \(customRawDefaults.string(forKey: customRawPrefix + "MLastFetchShapeId") ?? "none")
MFetchShapePeer: \(customRawDefaults.string(forKey: customRawPrefix + "MLastFetchShapePeer") ?? "none")
MFetchShapeTextLength: \(customRawDefaults.string(forKey: customRawPrefix + "MLastFetchShapeTextLength") ?? "none")

MExactHitWithText: \(customRawDefaults.integer(forKey: customRawPrefix + "mExactHitWithText.Count"))
MExactHitWithoutText: \(customRawDefaults.integer(forKey: customRawPrefix + "mExactHitWithoutText.Count"))
MExactCollisionCount: \(customRawDefaults.integer(forKey: customRawPrefix + "mExactIdCollision.Count"))
MExactCollisionRequestedId: \(customRawDefaults.string(forKey: customRawPrefix + "MExactCollisionRequestedId") ?? "none")
MExactCollisionPeer: \(customRawDefaults.string(forKey: customRawPrefix + "MExactCollisionPeer") ?? "none")
MExactCollisionCase: \(customRawDefaults.string(forKey: customRawPrefix + "MExactCollisionCase") ?? "none")
MExactCollisionId: \(customRawDefaults.string(forKey: customRawPrefix + "MExactCollisionId") ?? "none")
MExactCollisionText: \(customRawDefaults.string(forKey: customRawPrefix + "MExactCollisionText") ?? "none")

MExactCollisionList:
\(customRawDefaults.string(forKey: customRawPrefix + "MExactCollisionList") ?? "none")

v1.0L Target Verdict:
TargetVerdict: \(customRawDefaults.string(forKey: customRawPrefix + "TargetVerdict") ?? "none")
TargetMarker: \(customRawDefaults.string(forKey: customRawPrefix + "TargetMarker") ?? "none")
TargetSnapshotHit: \(customRawDefaults.integer(forKey: customRawPrefix + "targetSnapshotHit.Count"))
TargetHistoryHit: \(customRawDefaults.integer(forKey: customRawPrefix + "targetHistoryHit.Count"))
TargetExactHit: \(customRawDefaults.integer(forKey: customRawPrefix + "targetExactHit.Count"))
TargetText: \(customRawDefaults.string(forKey: customRawPrefix + "TargetText") ?? "none")
TargetSnapshotText: \(customRawDefaults.string(forKey: customRawPrefix + "TargetSnapshotText") ?? "none")

ExactHitCount: \(customRawDefaults.integer(forKey: customRawPrefix + "exactHitCount.Count"))
ExactHitMessage: \(customRawDefaults.integer(forKey: customRawPrefix + "exactHitMessage.Count"))
ExactHitEmpty: \(customRawDefaults.integer(forKey: customRawPrefix + "exactHitEmpty.Count"))
ExactHitService: \(customRawDefaults.integer(forKey: customRawPrefix + "exactHitService.Count"))
ExactHitWithText: \(customRawDefaults.integer(forKey: customRawPrefix + "exactHitWithText.Count"))
ExactHitWithoutText: \(customRawDefaults.integer(forKey: customRawPrefix + "exactHitWithoutText.Count"))

ExactHitRequestedId: \(customRawDefaults.string(forKey: customRawPrefix + "ExactHitRequestedId") ?? "none")
ExactHitPeer: \(customRawDefaults.string(forKey: customRawPrefix + "ExactHitPeer") ?? "none")
ExactHitCase: \(customRawDefaults.string(forKey: customRawPrefix + "ExactHitCase") ?? "none")
ExactHitId: \(customRawDefaults.string(forKey: customRawPrefix + "ExactHitId") ?? "none")
ExactHitTextLength: \(customRawDefaults.string(forKey: customRawPrefix + "ExactHitTextLength") ?? "none")
ExactHitText: \(customRawDefaults.string(forKey: customRawPrefix + "ExactHitText") ?? "none")
ExactHitMedia: \(customRawDefaults.string(forKey: customRawPrefix + "ExactHitMedia") ?? "none")

ExactHitList:
\(customRawDefaults.string(forKey: customRawPrefix + "ExactHitList") ?? "none")

Raw Difference Snapshot Probe:
Total: \(customRawDefaults.integer(forKey: customRawPrefix + "Total"))
Last: \(customRawDefaults.string(forKey: customRawPrefix + "Last") ?? "none") x\(customRawDefaults.integer(forKey: customRawPrefix + "LastAmount")) @ \(customRawDefaults.integer(forKey: customRawPrefix + "LastTime"))
snapshotSeen: \(customRawDefaults.integer(forKey: customRawPrefix + "snapshotSeen.Count"))
snapshotSaved: \(customRawDefaults.integer(forKey: customRawPrefix + "snapshotSaved.Count"))
snapshotWithText: \(customRawDefaults.integer(forKey: customRawPrefix + "snapshotWithText.Count"))
snapshotEmptyText: \(customRawDefaults.integer(forKey: customRawPrefix + "snapshotEmptyText.Count"))
snapshotWithGlobalId: \(customRawDefaults.integer(forKey: customRawPrefix + "snapshotWithGlobalId.Count"))
fromDifference: \(customRawDefaults.integer(forKey: customRawPrefix + "snapshotFromDifference.Count"))
fromUpdateNewMessage: \(customRawDefaults.integer(forKey: customRawPrefix + "snapshotFromUpdateNewMessage.Count"))
fromUpdateNewChannelMessage: \(customRawDefaults.integer(forKey: customRawPrefix + "snapshotFromUpdateNewChannelMessage.Count"))
fromChannelDifference: \(customRawDefaults.integer(forKey: customRawPrefix + "snapshotFromChannelDifference.Count"))
deleteDirectSeen: \(customRawDefaults.integer(forKey: customRawPrefix + "deleteDirectSeen.Count"))
deleteDirectIds: \(customRawDefaults.integer(forKey: customRawPrefix + "deleteDirectIds.Count"))
deleteGlobalSeen: \(customRawDefaults.integer(forKey: customRawPrefix + "deleteGlobalSeen.Count"))
deleteGlobalIds: \(customRawDefaults.integer(forKey: customRawPrefix + "deleteGlobalIds.Count"))
deleteSnapshotHit: \(customRawDefaults.integer(forKey: customRawPrefix + "deleteSnapshotHit.Count"))
deleteSnapshotMiss: \(customRawDefaults.integer(forKey: customRawPrefix + "deleteSnapshotMiss.Count"))
deleteGlobalSnapshotHit: \(customRawDefaults.integer(forKey: customRawPrefix + "deleteGlobalSnapshotHit.Count"))
deleteGlobalSnapshotMiss: \(customRawDefaults.integer(forKey: customRawPrefix + "deleteGlobalSnapshotMiss.Count"))
deleteGlobalResolverSeen: \(customRawDefaults.integer(forKey: customRawPrefix + "deleteGlobalResolverSeen.Count"))
deleteGlobalResolvedIds: \(customRawDefaults.integer(forKey: customRawPrefix + "deleteGlobalResolvedIds.Count"))
deleteGlobalResolverMiss: \(customRawDefaults.integer(forKey: customRawPrefix + "deleteGlobalResolverMiss.Count"))
deleteResolvedCurrentText: \(customRawDefaults.integer(forKey: customRawPrefix + "deleteResolvedCurrentText.Count"))
fetchRaceStarted: \(customRawDefaults.integer(forKey: customRawPrefix + "fetchRaceStarted.Count"))
fetchRaceIds: \(customRawDefaults.integer(forKey: customRawPrefix + "fetchRaceIds.Count"))
fetchRaceResponse: \(customRawDefaults.integer(forKey: customRawPrefix + "fetchRaceResponse.Count"))
fetchRaceEmpty: \(customRawDefaults.integer(forKey: customRawPrefix + "fetchRaceEmpty.Count"))
fetchRaceWithText: \(customRawDefaults.integer(forKey: customRawPrefix + "fetchRaceWithText.Count"))
fetchRaceStoreMessage: \(customRawDefaults.integer(forKey: customRawPrefix + "fetchRaceStoreMessage.Count"))
fetchRaceError: \(customRawDefaults.integer(forKey: customRawPrefix + "fetchRaceError.Count"))
fetchShapeSeen: \(customRawDefaults.integer(forKey: customRawPrefix + "fetchShapeSeen.Count"))
fetchShapeMessage: \(customRawDefaults.integer(forKey: customRawPrefix + "fetchShapeMessage.Count"))
fetchShapeMessageEmpty: \(customRawDefaults.integer(forKey: customRawPrefix + "fetchShapeMessageEmpty.Count"))
fetchShapeMessageService: \(customRawDefaults.integer(forKey: customRawPrefix + "fetchShapeMessageService.Count"))
historyProbeStarted: \(customRawDefaults.integer(forKey: customRawPrefix + "historyProbeStarted.Count"))
historyProbeInputIds: \(customRawDefaults.integer(forKey: customRawPrefix + "historyProbeInputIds.Count"))
historyProbeChatListResponse: \(customRawDefaults.integer(forKey: customRawPrefix + "historyProbeChatListResponse.Count"))
historyProbeCandidatePeers: \(customRawDefaults.integer(forKey: customRawPrefix + "historyProbeCandidatePeers.Count"))
historyProbeNoCandidates: \(customRawDefaults.integer(forKey: customRawPrefix + "historyProbeNoCandidates.Count"))
historyProbePeerTried: \(customRawDefaults.integer(forKey: customRawPrefix + "historyProbePeerTried.Count"))
historyProbeResponse: \(customRawDefaults.integer(forKey: customRawPrefix + "historyProbeResponse.Count"))
historyProbeEmpty: \(customRawDefaults.integer(forKey: customRawPrefix + "historyProbeEmpty.Count"))
historyProbeMessage: \(customRawDefaults.integer(forKey: customRawPrefix + "historyProbeMessage.Count"))
historyProbeMessageEmpty: \(customRawDefaults.integer(forKey: customRawPrefix + "historyProbeMessageEmpty.Count"))
historyProbeMessageService: \(customRawDefaults.integer(forKey: customRawPrefix + "historyProbeMessageService.Count"))
historyProbeExactId: \(customRawDefaults.integer(forKey: customRawPrefix + "historyProbeExactId.Count"))
historyProbeExactEmptyId: \(customRawDefaults.integer(forKey: customRawPrefix + "historyProbeExactEmptyId.Count"))
historyProbeWithText: \(customRawDefaults.integer(forKey: customRawPrefix + "historyProbeWithText.Count"))
historyProbeError: \(customRawDefaults.integer(forKey: customRawPrefix + "historyProbeError.Count"))
LastSnapshotSource: \(customRawDefaults.string(forKey: customRawPrefix + "LastSnapshotSource") ?? "none")
LastSnapshotKey: \(customRawDefaults.string(forKey: customRawPrefix + "LastSnapshotKey") ?? "none")
LastSnapshotGlobalId: \(customRawDefaults.string(forKey: customRawPrefix + "LastSnapshotGlobalId") ?? "none")
LastSnapshotText: \(customRawDefaults.string(forKey: customRawPrefix + "LastSnapshotText") ?? "none")
LastDeleteSource: \(customRawDefaults.string(forKey: customRawPrefix + "LastDeleteSource") ?? "none")
LastDeleteIdsCount: \(customRawDefaults.string(forKey: customRawPrefix + "LastDeleteIdsCount") ?? "none")
LastDeleteGlobalIdsCount: \(customRawDefaults.string(forKey: customRawPrefix + "LastDeleteGlobalIdsCount") ?? "none")
LastDeleteGlobalInputIdsCount: \(customRawDefaults.string(forKey: customRawPrefix + "LastDeleteGlobalInputIdsCount") ?? "none")
LastDeleteGlobalResolvedIdsCount: \(customRawDefaults.string(forKey: customRawPrefix + "LastDeleteGlobalResolvedIdsCount") ?? "none")
LastDeleteResolvedKey: \(customRawDefaults.string(forKey: customRawPrefix + "LastDeleteResolvedKey") ?? "none")
LastDeleteResolvedText: \(customRawDefaults.string(forKey: customRawPrefix + "LastDeleteResolvedText") ?? "none")
LastFetchRaceSource: \(customRawDefaults.string(forKey: customRawPrefix + "LastFetchRaceSource") ?? "none")
LastFetchRaceIdsCount: \(customRawDefaults.string(forKey: customRawPrefix + "LastFetchRaceIdsCount") ?? "none")
LastFetchRaceApiMessageCount: \(customRawDefaults.string(forKey: customRawPrefix + "LastFetchRaceApiMessageCount") ?? "none")
LastFetchRaceMessageKey: \(customRawDefaults.string(forKey: customRawPrefix + "LastFetchRaceMessageKey") ?? "none")
LastFetchRaceText: \(customRawDefaults.string(forKey: customRawPrefix + "LastFetchRaceText") ?? "none")
LastFetchRaceError: \(customRawDefaults.string(forKey: customRawPrefix + "LastFetchRaceError") ?? "none")
LastFetchShapeSource: \(customRawDefaults.string(forKey: customRawPrefix + "LastFetchShapeSource") ?? "none")
LastFetchShapeCase: \(customRawDefaults.string(forKey: customRawPrefix + "LastFetchShapeCase") ?? "none")
LastFetchShapeId: \(customRawDefaults.string(forKey: customRawPrefix + "LastFetchShapeId") ?? "none")
LastFetchShapeFlags: \(customRawDefaults.string(forKey: customRawPrefix + "LastFetchShapeFlags") ?? "none")
LastFetchShapeFlags2: \(customRawDefaults.string(forKey: customRawPrefix + "LastFetchShapeFlags2") ?? "none")
LastFetchShapePeer: \(customRawDefaults.string(forKey: customRawPrefix + "LastFetchShapePeer") ?? "none")
LastFetchShapeFrom: \(customRawDefaults.string(forKey: customRawPrefix + "LastFetchShapeFrom") ?? "none")
LastFetchShapeDate: \(customRawDefaults.string(forKey: customRawPrefix + "LastFetchShapeDate") ?? "none")
LastFetchShapeTextLength: \(customRawDefaults.string(forKey: customRawPrefix + "LastFetchShapeTextLength") ?? "none")
LastFetchShapeTextPreview: \(customRawDefaults.string(forKey: customRawPrefix + "LastFetchShapeTextPreview") ?? "none")
LastFetchShapeMedia: \(customRawDefaults.string(forKey: customRawPrefix + "LastFetchShapeMedia") ?? "none")
LastFetchShapeAction: \(customRawDefaults.string(forKey: customRawPrefix + "LastFetchShapeAction") ?? "none")
LastHistoryProbeInputIdsCount: \(customRawDefaults.string(forKey: customRawPrefix + "LastHistoryProbeInputIdsCount") ?? "none")
LastHistoryProbeStateCandidateCount: \(customRawDefaults.string(forKey: customRawPrefix + "LastHistoryProbeStateCandidateCount") ?? "none")
LastHistoryProbeChatListCount: \(customRawDefaults.string(forKey: customRawPrefix + "LastHistoryProbeChatListCount") ?? "none")
LastHistoryProbeCandidateCount: \(customRawDefaults.string(forKey: customRawPrefix + "LastHistoryProbeCandidateCount") ?? "none")
LastHistoryProbeCandidatePeers: \(customRawDefaults.string(forKey: customRawPrefix + "LastHistoryProbeCandidatePeers") ?? "none")
LastHistoryProbePeer: \(customRawDefaults.string(forKey: customRawPrefix + "LastHistoryProbePeer") ?? "none")
LastHistoryProbeRequestedId: \(customRawDefaults.string(forKey: customRawPrefix + "LastHistoryProbeRequestedId") ?? "none")
LastHistoryProbeApiMessageCount: \(customRawDefaults.string(forKey: customRawPrefix + "LastHistoryProbeApiMessageCount") ?? "none")
LastHistoryProbeCase: \(customRawDefaults.string(forKey: customRawPrefix + "LastHistoryProbeCase") ?? "none")
LastHistoryProbeId: \(customRawDefaults.string(forKey: customRawPrefix + "LastHistoryProbeId") ?? "none")
LastHistoryProbePeerFromMessage: \(customRawDefaults.string(forKey: customRawPrefix + "LastHistoryProbePeerFromMessage") ?? "none")
LastHistoryProbeDate: \(customRawDefaults.string(forKey: customRawPrefix + "LastHistoryProbeDate") ?? "none")
LastHistoryProbeTextLength: \(customRawDefaults.string(forKey: customRawPrefix + "LastHistoryProbeTextLength") ?? "none")
LastHistoryProbeText: \(customRawDefaults.string(forKey: customRawPrefix + "LastHistoryProbeText") ?? "none")
LastHistoryProbeMedia: \(customRawDefaults.string(forKey: customRawPrefix + "LastHistoryProbeMedia") ?? "none")
LastHistoryProbeAction: \(customRawDefaults.string(forKey: customRawPrefix + "LastHistoryProbeAction") ?? "none")
LastHistoryProbeError: \(customRawDefaults.string(forKey: customRawPrefix + "LastHistoryProbeError") ?? "none")

TestEpoch: \(customRawDefaults.string(forKey: customRawPrefix + "TestEpoch") ?? "none")
EpochStartedAt: \(customRawDefaults.string(forKey: customRawPrefix + "EpochStartedAt") ?? "none")
ResetMode: \(customRawDefaults.string(forKey: customRawPrefix + "ResetMode") ?? "none")

Timeline:
\(customRawDefaults.string(forKey: customRawPrefix + "Timeline") ?? "none")

LastDeleteSnapshotKey: \(customRawDefaults.string(forKey: customRawPrefix + "LastDeleteSnapshotKey") ?? "none")
LastDeleteSnapshotText: \(customRawDefaults.string(forKey: customRawPrefix + "LastDeleteSnapshotText") ?? "none")
LastDeleteSnapshotTexts: \(customRawDefaults.string(forKey: customRawPrefix + "LastDeleteSnapshotTexts") ?? "none")
"""))

    let customCorePrefix = "custom.V10B.Core."
    let customCoreDefaults = UserDefaults.standard
    let customCoreTotal = customCoreDefaults.integer(forKey: customCorePrefix + "Total")
    let customCoreLast = customCoreDefaults.string(forKey: customCorePrefix + "Last") ?? "none"
    let customCoreLastTime = customCoreDefaults.integer(forKey: customCorePrefix + "LastTime")

    entries.append(.info(debug, """
Core Difference Probe:
Total: \(customCoreTotal)
Last: \(customCoreLast) @ \(customCoreLastTime)
newMessage: \(customCoreDefaults.integer(forKey: customCorePrefix + "newMessage.Count"))
deleteMessages: \(customCoreDefaults.integer(forKey: customCorePrefix + "deleteMessages.Count"))
editMessage: \(customCoreDefaults.integer(forKey: customCorePrefix + "editMessage.Count"))
newChannelMessage: \(customCoreDefaults.integer(forKey: customCorePrefix + "newChannelMessage.Count"))
deleteChannelMessages: \(customCoreDefaults.integer(forKey: customCorePrefix + "deleteChannelMessages.Count"))
editChannelMessage: \(customCoreDefaults.integer(forKey: customCorePrefix + "editChannelMessage.Count"))
"""))

    entries.append(.info(debug, """
Telegram ID: \(telegramId)
Bundle ID: \(bundleId)
AppGroup: group.ph.telegra.Telegraph
Base: Official Telegram 12.9.2
KeychainFix: sideloadKeychainFix.dylib
Version: v1.1G-unified-recovery
"""))

    entries.append(.info(footer, "Activity Guard hides typing, recording, uploading, sticker, game and emoji activity when enabled."))

    return entries
}

public func customSettingsRootController(
    context: AccountContext
) -> ViewController {
    let rawPage = UserDefaults.standard.string(
        forKey: "custom.Settings.InitialPage"
    ) ?? "root"

    UserDefaults.standard.removeObject(
        forKey: "custom.Settings.InitialPage"
    )

    let page: CustomSettingsPage

    switch rawPage {
    case "root":
        page = .root
    case "invisibleMode":
        page = .invisibleMode
    case "messages":
        page = .messages
    case "protectedContent":
        page = .protectedContent
    case "mediaStories":
        page = .mediaStories
    case "appearance", "debugResearch", "about":
        // Design customization and research tabs are retired; land on root.
        page = .root
    default:
        page = .root
    }

    return customSettingsPageController(
        context: context,
        page: page
    )
}

private final class CustomSendStylePageArguments {
    let select: (String) -> Void

    init(select: @escaping (String) -> Void) {
        self.select = select
    }
}

private enum CustomSendStylePageEntry: ItemListNodeEntry {
    case option(Int32, String, String, Bool)

    var section: ItemListSectionId {
        return 0
    }

    var stableId: Int32 {
        switch self {
        case let .option(index, _, _, _):
            return index
        }
    }

    static func ==(
        lhs: CustomSendStylePageEntry,
        rhs: CustomSendStylePageEntry
    ) -> Bool {
        switch (lhs, rhs) {
        case let (
            .option(li, lv, lt, ls),
            .option(ri, rv, rt, rs)
        ):
            return li == ri
                && lv == rv
                && lt == rt
                && ls == rs
        }
    }

    static func <(
        lhs: CustomSendStylePageEntry,
        rhs: CustomSendStylePageEntry
    ) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(
        presentationData: ItemListPresentationData,
        arguments: Any
    ) -> ListViewItem {
        let arguments =
            arguments as! CustomSendStylePageArguments

        switch self {
        case let .option(_, value, title, selected):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: "",
                attributedTitle: customSendStyleAttributedText(
                    style: value,
                    text: title,
                    color:
                        presentationData.theme.list.itemPrimaryTextColor,
                    size: 17.0
                ),
                label: selected ? "✓" : "",
                labelStyle: .text,
                sectionId: self.section,
                style: .blocks,
                disclosureStyle: .none,
                action: {
                    arguments.select(value)
                }
            )
        }
    }
}

private func customSendStylePageEntries(
    selected: String,
    strings: CustomStrings
) -> [CustomSendStylePageEntry] {
    let styles: [(String, String)] = [
        ("normal", strings.sendStyleNormal),
        ("bold", strings.sendStyleBold),
        ("italic", strings.sendStyleItalic),
        ("monospace", strings.sendStyleMonospace),
        ("strikethrough", strings.sendStyleStrikethrough),
        ("underline", strings.sendStyleUnderline),
        ("spoiler", strings.sendStyleSpoiler)
    ]

    return styles.enumerated().map { index, item in
        return .option(
            Int32(index),
            item.0,
            item.1,
            selected == item.0
        )
    }
}

private func customSendStylePageController(
    context: AccountContext,
    selected: String,
    select: @escaping (String) -> Void
) -> ViewController {
    let selectedValue = Atomic(value: selected)
    let selectedPromise = ValuePromise(
        selected,
        ignoreRepeated: true
    )

    let arguments = CustomSendStylePageArguments(
        select: { value in
            let updated = selectedValue.modify { _ in value }
            selectedPromise.set(updated)
            select(value)
        }
    )

    let signal = combineLatest(
        context.sharedContext.presentationData,
        selectedPromise.get()
    )
    |> deliverOnMainQueue
    |> map { presentationData, value
        -> (ItemListControllerState, (ItemListNodeState, Any)) in

        let itemPresentationData =
            ItemListPresentationData(presentationData)

        let controllerState = ItemListControllerState(
            presentationData: itemPresentationData,
            title: .text(presentationData.strings.custom.sendStyle),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(
                title: presentationData.strings.Common_Back
            ),
            animateChanges: false
        )

        let listState = ItemListNodeState(
            presentationData: itemPresentationData,
            entries: customSendStylePageEntries(
                selected: value,
                strings: presentationData.strings.custom
            ),
            style: .blocks,
            ensureVisibleItemTag: nil,
            emptyStateItem: nil,
            animateChanges: false
        )

        return (
            controllerState,
            (listState, arguments as Any)
        )
    }

    return ItemListController(
        context: context,
        state: signal
    )
}

func customSettingsPageController(
    context: AccountContext,
    page: CustomSettingsPage
) -> ViewController {
    let initialState = CustomSettingsState.load(accountPeerId: context.account.peerId.toInt64())

    customProjectActiveSettings(accountPeerId: context.account.peerId.toInt64(), state: initialState)
    let statePromise = ValuePromise(initialState, ignoreRepeated: false)
    let stateValue = Atomic(value: initialState)
    let accountPeerId = context.account.peerId.toInt64()
    let customImportRefreshSignal = customSettingsImportRefreshSignal(
        accountPeerId: accountPeerId,
        reload: {
            let refreshed = CustomSettingsState.load(accountPeerId: accountPeerId)
            _ = stateValue.modify { _ in refreshed }
            statePromise.set(refreshed)
        }
    )
    // Retain the import observer through the controller's existing state
    // subscription without changing the arity or closure shape of whatever
    // combineLatest the release chain already uses.
    let customImportRefreshStateSignal = combineLatest(
        statePromise.get(),
        customImportRefreshSignal
    )
    |> map { (state: CustomSettingsState, _: Void) -> CustomSettingsState in state }

    let updateState: ((CustomSettingsState) -> CustomSettingsState) -> Void = { f in
        let updated = stateValue.modify { current in
            let next = f(current)

            customPersistChangedSettings(
                accountPeerId: context.account.peerId.toInt64(),
                previous: current,
                current: next
            )

            return next
        }

        statePromise.set(updated)
    }

    var pushController: ((ViewController) -> Void)?

    var openSendTextStyleImpl: (() -> Void)?

    let customHiddenGiftsDisposable = MetaDisposable()
    let customBotCapabilityDisposable = MetaDisposable()
    let customBotDifferenceDisposable = MetaDisposable()
    let customProfileIntelDisposable = MetaDisposable()
    let customProfileIntel2Disposable = MetaDisposable()

    let customHiddenGiftFormDisposable = MetaDisposable()
    let customHiddenGiftPaymentDisposable = MetaDisposable()

    let refreshResearchPage: () -> Void = {
        statePromise.set(stateValue.with { $0 })
    }

    let runHiddenGiftsProbe: (
        EnginePeer.Id,
        String
    ) -> Void = { targetPeerId, targetLabel in
        let defaults = UserDefaults.standard

        defaults.set(
            "running",
            forKey: customHiddenGiftsPrefix + "Status"
        )
        defaults.set(
            targetLabel,
            forKey: customHiddenGiftsPrefix + "Target"
        )
        defaults.set(
            "",
            forKey: customHiddenGiftsPrefix + "Report"
        )
        refreshResearchPage()

        let catalogSignal =
            context.engine.payments
            .customFetchStarGiftsCatalogDirect()

        customHiddenGiftsDisposable.set((
            catalogSignal
            |> mapToSignal {
                catalogResult -> Signal<[String], NoError> in

                var catalogById: [
                    Int64: (index: Int, gift: StarGift.Gift)
                ] = [:]

                let catalogHeader: String

                switch catalogResult {
                case let .catalog(list):
                    catalogHeader = """
                    DIRECT_CATALOG: success
                    hash: \(list.hashValue)
                    totalItems: \(list.items.count)
                    """

                    for (index, item) in list.items.enumerated() {
                        if case let .generic(gift) = item {
                            catalogById[gift.id] = (
                                index: index,
                                gift: gift
                            )
                        }
                    }

                case .notModified:
                    catalogHeader = """
                    DIRECT_CATALOG: notModified
                    hashRequested: 0
                    """

                case let .failed(error):
                    catalogHeader = """
                    DIRECT_CATALOG: failed
                    error: \(error)
                    """
                }

                let signals: [Signal<String, NoError>] =
                    customHiddenGiftItems.map { name, giftId in

                        let checkSignal =
                            context.engine.payments
                            .checkCanSendStarGift(giftId: giftId)
                            |> map {
                                customHiddenGiftCheckText($0)
                            }

                        let formProbe: (
                            Bool
                        ) -> Signal<
                            CustomHiddenGiftFormProbeResult,
                            NoError
                        > = { includeUpgrade in
                            return context.engine.payments
                            .fetchBotPaymentForm(
                                source: .starGift(
                                    hideName: false,
                                    includeUpgrade: includeUpgrade,
                                    peerId: targetPeerId,
                                    giftId: giftId,
                                    text: nil,
                                    entities: nil
                                ),
                                themeParams: nil
                            )
                            |> map { form in
                                let prices =
                                    form.invoice.prices.map {
                                        "\($0.label)=\($0.amount)"
                                    }.joined(separator: ", ")

                                let total =
                                    form.invoice.prices.reduce(
                                        Int64(0),
                                        { $0 + $1.amount }
                                    )

                                let paymentBot =
                                    form.paymentBotId.map {
                                        String(describing: $0)
                                    } ?? "nil"

                                let provider =
                                    form.providerId.map {
                                        String(describing: $0)
                                    } ?? "nil"

                                let nativeProvider =
                                    form.nativeProvider?.name ?? "nil"

                                return CustomHiddenGiftFormProbeResult(
                                    total: total,
                                    text: """
                                    success
                                    formId: \(form.id)
                                    currency: \(form.invoice.currency)
                                    total: \(total)
                                    prices: \(prices)
                                    isTest: \(form.invoice.isTest)
                                    passwordMissing: \(form.passwordMissing)
                                    canSaveCredentials: \(form.canSaveCredentials)
                                    paymentBotId: \(paymentBot)
                                    providerId: \(provider)
                                    nativeProvider: \(nativeProvider)
                                    urlPresent: \(form.url != nil)
                                    additionalMethods: \(form.additionalPaymentMethods.count)
                                    """
                                )
                            }
                            |> `catch` {
                                error -> Signal<
                                    CustomHiddenGiftFormProbeResult,
                                    NoError
                                > in

                                return .single(
                                    CustomHiddenGiftFormProbeResult(
                                        total: nil,
                                        text:
                                            customHiddenGiftPaymentErrorText(
                                                error
                                            )
                                    )
                                )
                            }
                        }

                        let plainForm = formProbe(false)
                        let upgradedForm = formProbe(true)

                        return combineLatest(
                            checkSignal,
                            plainForm,
                            upgradedForm
                        )
                        |> map { check, plain, upgraded in
                            let catalogText: String

                            if let entry = catalogById[giftId] {
                                catalogText =
                                    customHiddenGiftCatalogText(
                                        index: entry.index,
                                        gift: entry.gift
                                    )
                            } else {
                                catalogText = "catalog: absent"
                            }

                            let delta: String
                            if let plainTotal = plain.total,
                               let upgradedTotal = upgraded.total {
                                delta = String(
                                    upgradedTotal - plainTotal
                                )
                            } else {
                                delta = "n/a"
                            }

                            return """
                            \(name)
                            giftId: \(giftId)
                            \(catalogText)
                            checkCanSendGift: \(check)

                            plainForm:
                            \(plain.text)

                            includeUpgradeForm:
                            \(upgraded.text)

                            upgradeDelta: \(delta)
                            """
                        }
                    }

                return combineLatest(signals)
                |> map { lines in
                    return [catalogHeader] + lines
                }
            }
            |> deliverOnMainQueue
        ).start(next: { lines in
            defaults.set(
                "completed",
                forKey: customHiddenGiftsPrefix + "Status"
            )
            defaults.set(
                lines.joined(separator: "\n\n"),
                forKey: customHiddenGiftsPrefix + "Report"
            )
            defaults.set(
                ISO8601DateFormatter().string(from: Date()),
                forKey: customHiddenGiftsPrefix + "Updated"
            )
            refreshResearchPage()
        }))
    }

    let selectHiddenGiftForSend: (
        Int
    ) -> Void = { index in
        guard !customHiddenGiftSendState.isSending else {
            return
        }

        guard index >= 0,
              index < customHiddenGiftItems.count else {
            customHiddenGiftSendState.status =
                "Ошибка: индекс подарка вне диапазона."
            refreshResearchPage()
            return
        }

        let item = customHiddenGiftItems[index]

        customHiddenGiftSendState.giftName = item.0
        customHiddenGiftSendState.giftId = item.1
        customHiddenGiftSendState.firstConfirmed = false
        customHiddenGiftSendState.status =
            "Подарок выбран: \(item.0), ID \(item.1)."

        refreshResearchPage()
    }

    let runHiddenGiftRealSend: () -> Void = {
        guard !customHiddenGiftSendState.isSending else {
            return
        }

        guard customHiddenGiftSendState.firstConfirmed,
              let giftName =
                customHiddenGiftSendState.giftName,
              let giftId =
                customHiddenGiftSendState.giftId,
              let targetPeerId =
                customHiddenGiftSendState.targetPeerId else {
            customHiddenGiftSendState.status =
                "Отправка заблокирована: нет полного подтверждения."
            refreshResearchPage()
            return
        }

        let hideName =
            customHiddenGiftSendState.hideName

        let source: BotPaymentInvoiceSource = .starGift(
            hideName: hideName,
            includeUpgrade: false,
            peerId: targetPeerId,
            giftId: giftId,
            text: nil,
            entities: nil
        )

        customHiddenGiftSendState.isSending = true
        customHiddenGiftSendState.status =
            "Повторно получаем платёжную форму для \(giftName)…"
        refreshResearchPage()

        customHiddenGiftFormDisposable.set((
            context.engine.payments.fetchBotPaymentForm(
                source: source,
                themeParams: nil
            )
            |> take(1)
            |> deliverOnMainQueue
        ).start(
            next: { form in
                let total = form.invoice.prices.reduce(
                    Int64(0),
                    { current, price in
                        current + price.amount
                    }
                )

                guard form.invoice.currency == "XTR" else {
                    customHiddenGiftSendState.isSending = false
                    customHiddenGiftSendState.firstConfirmed = false
                    customHiddenGiftSendState.status =
                        "ОТМЕНЕНО: currency=\(form.invoice.currency), ожидалось XTR."
                    refreshResearchPage()
                    return
                }

                guard total == 50 else {
                    customHiddenGiftSendState.isSending = false
                    customHiddenGiftSendState.firstConfirmed = false
                    customHiddenGiftSendState.status =
                        "ОТМЕНЕНО: сервер запросил \(total) Stars вместо 50."
                    refreshResearchPage()
                    return
                }

                guard !form.invoice.isTest else {
                    customHiddenGiftSendState.isSending = false
                    customHiddenGiftSendState.firstConfirmed = false
                    customHiddenGiftSendState.status =
                        "ОТМЕНЕНО: сервер вернул тестовую форму."
                    refreshResearchPage()
                    return
                }

                customHiddenGiftSendState.status =
                    "Форма подтверждена: 50 XTR. Выполняется единственный payment RPC."
                refreshResearchPage()

                customHiddenGiftPaymentDisposable.set((
                    context.engine.payments.sendStarsPaymentForm(
                        formId: form.id,
                        source: source
                    )
                    |> take(1)
                    |> deliverOnMainQueue
                ).start(
                    next: { result in
                        customHiddenGiftSendState.isSending = false
                        customHiddenGiftSendState.firstConfirmed = false
                        customHiddenGiftSendState.status =
                            customHiddenGiftSendResultText(result)
                        refreshResearchPage()
                    },
                    error: { error in
                        customHiddenGiftSendState.isSending = false
                        customHiddenGiftSendState.firstConfirmed = false
                        customHiddenGiftSendState.status =
                            "PAYMENT ERROR: "
                            + customHiddenGiftSendErrorText(error)
                        refreshResearchPage()
                    }
                ))
            },
            error: { error in
                customHiddenGiftSendState.isSending = false
                customHiddenGiftSendState.firstConfirmed = false
                customHiddenGiftSendState.status =
                    "FORM ERROR: "
                    + customHiddenGiftPaymentErrorText(error)
                refreshResearchPage()
            }
        ))
    }

    let aboutChannelSignal = customAboutChannelState(
        context: context,
        enabled: page == .about,
        username: nil
    )
    let aboutCommunitySignal = customAboutChannelState(
        context: context,
        enabled: page == .about,
        username: nil
    )
    var openAboutChannelImpl: ((EnginePeer) -> Void)?

    let arguments = CustomSettingsArguments(
        context: context,
        openAboutChannel: { peer in
            openAboutChannelImpl?(peer)
        },
        runResearchAction: { action in
            switch action {
            case "copyExtensionDiagnostics":
                UIPasteboard.general.string = BuildConfig.customExtensionDiagnosticsReport()

            case "debug.copyLog":
                UIPasteboard.general.string = CustomDebugConsole.logText()

            case "debug.clearLog":
                CustomDebugConsole.clearLog()
                refreshResearchPage()

            case "hiddenGiftsSelf":
                runHiddenGiftsProbe(
                    context.account.peerId,
                    "self: \(String(describing: context.account.peerId))"
                )

            case "hiddenGiftsOther":
                let controller =
                    context.sharedContext.makePeerSelectionController(
                        PeerSelectionControllerParams(
                            context: context,
                            filter: [
                                .onlyPrivateChats,
                                .excludeSavedMessages,
                                .removeSearchHeader,
                                .excludeRecent,
                                .doNotSearchMessages
                            ],
                            title: "Получатель Hidden Gifts"
                        )
                    )

                controller.peerSelected = {
                    [weak controller] peer, _ in
                    controller?.dismiss()
                    runHiddenGiftsProbe(
                        peer.id,
                        "user: \(String(describing: peer.id))"
                    )
                }

                pushController?(controller)

            case "hiddenGiftSendSelect0":
                selectHiddenGiftForSend(0)

            case "hiddenGiftSendSelect1":
                selectHiddenGiftForSend(1)

            case "hiddenGiftSendSelect2":
                selectHiddenGiftForSend(2)

            case "hiddenGiftSendSelect3":
                selectHiddenGiftForSend(3)

            case "hiddenGiftSendSelect4":
                selectHiddenGiftForSend(4)

            case "hiddenGiftSendSelect5":
                selectHiddenGiftForSend(5)

            case "hiddenGiftSendSelect6":
                selectHiddenGiftForSend(6)

            case "hiddenGiftSendSelect7":
                selectHiddenGiftForSend(7)

            case "hiddenGiftSendSelect8":
                selectHiddenGiftForSend(8)

            case "hiddenGiftSendSelf":
                guard !customHiddenGiftSendState.isSending else {
                    break
                }

                customHiddenGiftSendState.targetPeerId =
                    context.account.peerId
                customHiddenGiftSendState.targetLabel =
                    "self: \(String(describing: context.account.peerId))"
                customHiddenGiftSendState.firstConfirmed = false
                customHiddenGiftSendState.status =
                    "Получатель выбран: собственный аккаунт."
                refreshResearchPage()

            case "hiddenGiftSendToggleHideName":
                guard !customHiddenGiftSendState.isSending else {
                    break
                }

                customHiddenGiftSendState.hideName.toggle()
                customHiddenGiftSendState.firstConfirmed = false

                customHiddenGiftSendState.status =
                    customHiddenGiftSendState.hideName
                    ? "Имя отправителя будет скрыто."
                    : "Имя отправителя будет открыто."

                refreshResearchPage()

            case "hiddenGiftSendRecipient":
                guard !customHiddenGiftSendState.isSending else {
                    break
                }

                let controller =
                    context.sharedContext.makePeerSelectionController(
                        PeerSelectionControllerParams(
                            context: context,
                            filter: [
                                .onlyPrivateChats,
                                .excludeSavedMessages,
                                .removeSearchHeader,
                                .excludeRecent,
                                .doNotSearchMessages
                            ],
                            title: "Получатель сезонного подарка"
                        )
                    )

                controller.peerSelected = {
                    [weak controller] peer, _ in
                    controller?.dismiss()

                    customHiddenGiftSendState.targetPeerId =
                        peer.id
                    customHiddenGiftSendState.targetLabel =
                        "user: \(String(describing: peer.id))"
                    customHiddenGiftSendState.firstConfirmed =
                        false
                    customHiddenGiftSendState.status =
                        "Получатель выбран: \(String(describing: peer.id))."

                    refreshResearchPage()
                }

                pushController?(controller)

            case "hiddenGiftSendConfirm":
                guard !customHiddenGiftSendState.isSending,
                      customHiddenGiftSendState.giftId != nil,
                      customHiddenGiftSendState.targetPeerId != nil else {
                    customHiddenGiftSendState.status =
                        "Сначала выберите подарок и получателя."
                    refreshResearchPage()
                    break
                }

                customHiddenGiftSendState.firstConfirmed = true
                customHiddenGiftSendState.status =
                    "Первое подтверждение принято. Проверьте данные и нажмите кнопку списания 50 Stars."
                refreshResearchPage()

            case "hiddenGiftSendPay":
                runHiddenGiftRealSend()

            case "hiddenGiftSendReset":
                guard !customHiddenGiftSendState.isSending else {
                    break
                }

                customHiddenGiftSendState =
                    CustomHiddenGiftSendState()
                refreshResearchPage()

            case "botCapabilityProbe":
                let defaults = UserDefaults.standard

                defaults.set(
                    "running",
                    forKey:
                        customBotCapabilityPrefix + "Status"
                )
                defaults.set(
                    "",
                    forKey:
                        customBotCapabilityPrefix + "Report"
                )
                refreshResearchPage()

                customBotCapabilityDisposable.set((
                    context.engine.peers
                    .customBotCapabilityProbe()
                    |> take(1)
                    |> deliverOnMainQueue
                ).start(next: { report in
                    defaults.set(
                        "completed",
                        forKey:
                            customBotCapabilityPrefix + "Status"
                    )
                    defaults.set(
                        report,
                        forKey:
                            customBotCapabilityPrefix + "Report"
                    )
                    defaults.set(
                        ISO8601DateFormatter()
                            .string(from: Date()),
                        forKey:
                            customBotCapabilityPrefix + "Updated"
                    )
                    refreshResearchPage()
                }))

            case "botDifferenceProbe":
                let defaults = UserDefaults.standard

                defaults.set(
                    "running",
                    forKey: customBotDifferencePrefix + "Status"
                )
                defaults.set(
                    "",
                    forKey: customBotDifferencePrefix + "Report"
                )
                refreshResearchPage()

                customBotDifferenceDisposable.set((
                    context.engine.peers
                    .customBotDifferenceProbe()
                    |> take(1)
                    |> deliverOnMainQueue
                ).start(next: { report in
                    defaults.set(
                        "completed",
                        forKey:
                            customBotDifferencePrefix + "Status"
                    )
                    defaults.set(
                        report,
                        forKey:
                            customBotDifferencePrefix + "Report"
                    )
                    defaults.set(
                        ISO8601DateFormatter()
                            .string(from: Date()),
                        forKey:
                            customBotDifferencePrefix + "Updated"
                    )
                    refreshResearchPage()
                }))

            case "profileIntel1Probe":
                let defaults = UserDefaults.standard
                let rawTarget = UIPasteboard.general.string ?? ""
                let target = rawTarget.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )

                guard !target.isEmpty else {
                    defaults.set(
                        "failed: clipboard empty",
                        forKey: customProfileIntelPrefix + "Status"
                    )
                    refreshResearchPage()
                    break
                }

                if let current = defaults.string(
                    forKey: customProfileIntelPrefix + "Report"
                ), !current.isEmpty {
                    defaults.set(
                        current,
                        forKey:
                            customProfileIntelPrefix
                            + "PreviousReport"
                    )
                    defaults.set(
                        defaults.string(
                            forKey:
                                customProfileIntelPrefix + "Updated"
                        ) ?? "none",
                        forKey:
                            customProfileIntelPrefix
                            + "PreviousUpdated"
                    )
                }

                defaults.set(
                    target,
                    forKey: customProfileIntelPrefix + "Target"
                )
                defaults.set(
                    "running",
                    forKey: customProfileIntelPrefix + "Status"
                )
                defaults.set(
                    "",
                    forKey: customProfileIntelPrefix + "Report"
                )
                refreshResearchPage()

                customProfileIntelDisposable.set((
                    context.engine.peers
                    .customProfileIntelProbe(username: target)
                    |> take(1)
                    |> deliverOnMainQueue
                ).start(next: { report in
                    defaults.set(
                        "completed",
                        forKey:
                            customProfileIntelPrefix + "Status"
                    )
                    defaults.set(
                        report,
                        forKey:
                            customProfileIntelPrefix + "Report"
                    )
                    defaults.set(
                        ISO8601DateFormatter().string(from: Date()),
                        forKey:
                            customProfileIntelPrefix + "Updated"
                    )
                    refreshResearchPage()
                }))

            case "profileIntel2Snapshot":
                let defaults = UserDefaults.standard
                let rawTarget = UIPasteboard.general.string ?? ""
                let target = rawTarget.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )

                guard !target.isEmpty else {
                    defaults.set(
                        "failed: clipboard empty",
                        forKey: customProfileIntel2Prefix + "Status"
                    )
                    refreshResearchPage()
                    break
                }

                defaults.set(
                    target,
                    forKey: customProfileIntel2Prefix + "Target"
                )
                defaults.set(
                    "running",
                    forKey: customProfileIntel2Prefix + "Status"
                )
                refreshResearchPage()

                customProfileIntel2Disposable.set((
                    context.engine.peers
                    .customProfileIntel2Snapshot(username: target)
                    |> take(1)
                    |> deliverOnMainQueue
                ).start(next: { report in
                    defaults.set(
                        "completed",
                        forKey: customProfileIntel2Prefix + "Status"
                    )
                    defaults.set(
                        report,
                        forKey: customProfileIntel2Prefix + "Report"
                    )
                    defaults.set(
                        ISO8601DateFormatter().string(from: Date()),
                        forKey: customProfileIntel2Prefix + "Updated"
                    )
                    refreshResearchPage()
                }))

            default:
                break
            }
        },
        updateBool: { key, value in
        updateState { state in
            var updated = state

            switch key {
            case CustomKey.profileEnabled:
                updated.profileEnabled = value
            case CustomKey.showIds:
                updated.showIds = value
                if value {
                    updated.profileEnabled = true
                }
            case CustomKey.showDCs:
                updated.showDCs = value
                if value {
                    updated.profileEnabled = true
                }
            case CustomKey.showRegistration:
                updated.showRegistration = value
                if value {
                    updated.profileEnabled = true
                }

            case CustomKey.saveDeleted:
                updated.saveDeleted = value
            case CustomKey.showDeleted:
                updated.showDeleted = value
            case CustomKey.saveEditHistory:
                updated.saveEditHistory = value
            case CustomKey.showEditHistory:
                updated.showEditHistory = value
            case CustomKey.hideBlockedMessages:
                updated.hideBlockedMessages = value
            case CustomKey.hideBlockedReactions:
                updated.hideBlockedReactions = value

            case CustomKey.deletedPortableReplies:
                updated.deletedPortableReplies = value
                UserDefaults.standard.set(
                    value,
                    forKey: CustomKey.deletedPortableReplies
                )

            case CustomKey.preserveDeletedMedia:
                updated.preserveDeletedMedia = value
                UserDefaults.standard.set(
                    value,
                    forKey: CustomKey.preserveDeletedMedia
                )

            case CustomKey.messageSeconds:
                updated.messageSeconds = value
                UserDefaults.standard.set(
                    value,
                    forKey: CustomKey.messageSeconds
                )

            case CustomKey.messageCharacterCount:
                updated.messageCharacterCount = value
                UserDefaults.standard.set(
                    value,
                    forKey: CustomKey.messageCharacterCount
                )
                NotificationCenter.default.post(
                    name: Notification.Name("custom.MessageDecorationsDidChange"),
                    object: nil
                )

            case CustomKey.hideOwnPhone:
                updated.hideOwnPhone = value
                UserDefaults.standard.set(
                    value,
                    forKey: CustomKey.hideOwnPhone
                )

            case CustomKey.chatSave:
                updated.chatSave = value
            case CustomKey.chatCopy:
                updated.chatCopy = value
            case CustomKey.chatForward:
                updated.chatForward = value
            case CustomKey.allowScreenshots:
                updated.allowScreenshots = value
            case CustomKey.allowScreenRecording:
                updated.allowScreenRecording = value
            case CustomKey.oneTimeScreenshots:
                updated.oneTimeScreenshots = value
            case CustomKey.oneTimeScreenRecording:
                updated.oneTimeScreenRecording = value
            case CustomKey.oneTimeSave:
                updated.oneTimeSave = value
            case CustomKey.storySave:
                updated.storySave = value
            case CustomKey.showRestricted:
                updated.showRestricted = value
            case CustomKey.localStarsEnabled:
                updated.localStarsEnabled = value
            case CustomKey.readMessages:
                updated.readMessages = value

            case CustomKey.typingActions:
                updated.typingActions = value
            case CustomKey.recordingActions:
                updated.recordingActions = value
            case CustomKey.recordingVideo:
                updated.recordingVideo = value
            case CustomKey.recordingRound:
                updated.recordingRound = value
            case CustomKey.uploadingActions:
                updated.uploadingActions = value
            case CustomKey.uploadingPhoto:
                updated.uploadingPhoto = value
            case CustomKey.uploadingVideo:
                updated.uploadingVideo = value
            case CustomKey.uploadingFile:
                updated.uploadingFile = value
            case CustomKey.uploadingRound:
                updated.uploadingRound = value
            case CustomKey.uploadingVoice:
                updated.uploadingVoice = value
            case CustomKey.stickerActivity:
                updated.stickerActivity = value
            case CustomKey.gameActivity:
                updated.gameActivity = value
            case CustomKey.emojiActivity:
                updated.emojiActivity = value
            case CustomKey.emojiAcknowledgement:
                updated.emojiAcknowledgement = value
            case CustomKey.speakingInGroupCall:
                updated.speakingInGroupCall = value
            case CustomKey.choosingLocation:
                updated.choosingLocation = value
            case CustomKey.choosingContact:
                updated.choosingContact = value
            case CustomKey.storyReadReceipts:
                updated.storyReadReceipts = value
            case CustomKey.removeAds:
                updated.removeAds = value

            case CustomKey.presence:
                updated.presence = value
                if value {
                    context.account.shouldKeepOnlinePresence.set(.single(false))
                } else {
                    context.account.shouldKeepOnlinePresence.set(.single(false))
                    context.account.shouldKeepOnlinePresence.set(.single(true))
                }

            case CustomKey.scheduledSend:
                updated.scheduledSend = value

            case CustomKey.protectedEnabled:
                updated.protectedEnabled = value
                updated.protectedGalleryShare = value
                updated.protectedGallerySave = value
                updated.protectedGalleryCopy = value
                updated.chatSave = value
                updated.chatCopy = value
                updated.chatForward = value
                updated.allowScreenshots = value
                updated.allowScreenRecording = value
                updated.oneTimeScreenshots = value
                updated.oneTimeScreenRecording = value
                updated.oneTimeSave = value
                updated.storySave = value

            default:
                break
            }

            return updated
        }
    }, openPage: { selectedPage in
        if selectedPage == .dataAndBackup {
            pushController?(customDataAndBackupController(context: context))
        } else if selectedPage == .database {
            pushController?(customDatabaseController(context: context))
        } else if selectedPage == .stars {
            pushController?(customStarsEditorController(context: context))
        } else if selectedPage == .search {
            pushController?(customSettingsSearchController(context: context))
        } else if selectedPage == .extras {
            pushController?(customExtrasController(context: context))
        } else {
            pushController?(
                customSettingsPageController(
                    context: context,
                    page: selectedPage
                )
            )
        }
    }, openSendTextStyle: {
        openSendTextStyleImpl?()
    })

    let signal = combineLatest(
        context.sharedContext.presentationData,
        customImportRefreshStateSignal,
        aboutChannelSignal,
        aboutCommunitySignal
    )
    |> deliverOnMainQueue
    |> map { presentationData, state, aboutChannelState, aboutCommunityState
        -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text(page.localizedTitle(presentationData.strings.custom)),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
        )

        let listState = ItemListNodeState(
            presentationData: ItemListPresentationData(presentationData),
            entries: customSettingsEntries(
                state: state,
                context: context,
                page: page,
                strings: presentationData.strings.custom,
                aboutChannelState: aboutChannelState,
                aboutCommunityState: aboutCommunityState
            ),
            style: .blocks,
            animateChanges: false
        )

        return (controllerState, (listState, arguments as Any))
    }

    let controller = ItemListController(
        context: context,
        state: signal
    )

    openAboutChannelImpl = { [weak controller] peer in
        guard let navigationController = controller?.navigationController
            as? NavigationController else {
            return
        }
        context.sharedContext.navigateToChatController(
            NavigateToChatControllerParams(
                navigationController: navigationController,
                context: context,
                chatLocation: .peer(peer)
            )
        )
    }

    openSendTextStyleImpl = { [weak controller] in
        let selected = stateValue.with {
            $0.sendTextStyle
        }

        let styleController =
            customSendStylePageController(
                context: context,
                selected: selected,
                select: { style in
                    updateState { current in
                        var updated = current
                        updated.sendTextStyle = style
                        return updated
                    }
                }
            )

        controller?.push(styleController)
    }

    pushController = { [weak controller] target in
        controller?.push(target)
    }

    return controller
}
