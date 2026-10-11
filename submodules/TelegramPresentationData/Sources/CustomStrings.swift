import Foundation
import PresentationStrings

//
// Custom user-facing text follows Telegram's selected interface language,
// never the device locale. English is the canonical source and universal
// fallback. Persisted Custom data stores semantic values, not translations.
public enum CustomStringKey: String, CaseIterable {
    case settingsTitle
    case searchSettings
    case searchSettingsHint
    case searchNothingFound
    case extras
    case basicFunctions
    case infoDisplay
    case bypassAll
    case bypassAllHint
    case removeAds
    case removeAdsHint
    case showHiddenChats
    case showHiddenChatsHint
    case invisibleMode
    case messages
    case protectedContent
    case mediaAndStories
    case appearance
    case debugResearch
    case about

    case debugConsole
    case debugConsoleHint
    case debugConsoleCopy
    case debugConsoleClear
    case debugConsoleEmpty
    case extrasHint
    case extrasMetadataSection
    case extrasMetadataToggle
    case extrasAnonymizeNames
    case extrasMetadataHint
    case extrasPrioritySection
    case extrasPriorityHint
    case basicFunctionsHint
    case infoDisplayHint
    case invisibleModeHint
    case messagesHint
    case protectedContentHint
    case mediaAndStoriesHint
    case appearanceHint
    case debugResearchHint
    case dataAndBackupHint
    case databaseTitle
    case databaseHint
    case databaseClearTitle
    case databaseClearHint
    case databaseClearAction
    case databaseClearConfirmTitle
    case databaseClearConfirmText
    case databaseClearConfirmYes
    case databaseCleared
    case databaseExportTitle
    case databaseExportHint
    case databaseExportReadable
    case databaseExportReadableDone
    case databaseError
    case databaseStatEvents
    case databaseStatChats
    case databaseStatMedia
    case databaseClearExportFirst
    case databaseExportOneChatTitle
    case databaseExportChooseChat
    case databaseNoEventsForChat
    case aboutHint
    case aboutGithub
    case aboutGithubNote
    case aboutChannelLink
    case aboutChannelNote
    case aboutBotLink
    case aboutBotNote
    case profileCard
    case showIds
    case showDcs
    case registrationDate
    case localStarsBalance
    case starsBalance
    case currentVisualBalance

    case readInvisible
    case typing
    case recording
    case uploading
    case choosingSticker
    case gameActivity
    case choosingEmoji
    case hideOnline
    case scheduledSend
    case readReceipts
    case other
    case hideOnlineHint
    case typingHint
    case recordingVoiceTitle
    case recordingVoiceHint
    case recordingVideoTitle
    case recordingVideoHint
    case recordingRoundTitle
    case recordingRoundHint
    case uploadingVideoTitle
    case uploadingVideoHint
    case uploadingVoiceTitle
    case uploadingVoiceHint
    case uploadingPhotoTitle
    case uploadingPhotoHint
    case uploadingFileTitle
    case uploadingFileHint
    case uploadingRoundTitle
    case uploadingRoundHint
    case choosingLocationTitle
    case choosingLocationHint
    case choosingContactTitle
    case choosingContactHint
    case gameActivityTitle
    case gameActivityHint
    case speakingGroupCallTitle
    case speakingGroupCallHint
    case choosingStickerTitle
    case choosingStickerHint
    case emojiInteractionTitle
    case emojiInteractionHint
    case emojiAckTitle
    case emojiAckHint
    case messageReadReceipts
    case messageReadReceiptsHint
    case storyReadReceipts
    case storyReadReceiptsHint
    case scheduledSendHint

    case deletedMessages
    case saveDeletedMessages
    case showDeletedMessages
    case editHistory
    case saveEditHistory
    case showEditHistory
    case savedDataHint
    case textSending
    case sendStyle
    case sendStyleHint
    case deletedReplies
    case portableReply
    case saveDeletedMedia
    case portableReplyHint

    case protectionEnabled
    case shareFromGallery
    case saveFromGallery
    case copyFromGallery
    case saveFromChat
    case copyFromChat
    case forwardFromChat
    case allowScreenshots
    case allowScreenRecording

    case oneTimeScreenshots
    case oneTimeScreenRecording
    case oneTimeSave
    case oneTimeMedia
    case storySave
    case appearancePlaceholder
    case profileBackground
    case profileBackgroundEffect
    case blurProfileAvatar
    case preferAvatarAsBackground
    case animatedBackground
    case colorTint
    case reducedBlur
    case animatedBackgroundHint
    case profileEffectDisabledHint
    case interface
    case messageSeconds
    case messageCharacterCount
    case hideMyPhone
    case showRamUnderClock
    case hidePhoneHint
    case presenceHistoryEmpty
    case knownUsersNoData
    case recentEvents
    case eventsEmpty
    case diagnosticsBufferHint

    case information
    case telegramId
    case rawIdNamespace
    case profile
    case mainMenu

    case deletedMessage
    case editedMessage
    case sticker
    case photo
    case video
    case gif
    case audio
    case voiceMessage
    case videoMessage
    case document
    case attachment
    case album
    case poll
    case location
    case contact
    case dice
    case taskList
    case user

    case importSettings
    case exportSettings
    case importArchive
    case exportArchive

    case sendStyleNormal
    case sendStyleBold
    case sendStyleItalic
    case sendStyleMonospace
    case sendStyleStrikethrough
    case sendStyleUnderline
    case sendStyleSpoiler
    case sendStyleExamplePrefix
    case sendStyleExampleBody
    case community
    case communityHint
    case copyExtensionDiagnostics
    case communityLoading
    case communityUnavailable
    case communityNoPosts
    case profileHistoryTab
    case presenceHistoryTab
    case giftHistoryTab
    case personalChannelTab
    case profileReportLoading
}

public struct CustomStrings {
    public let languageCode: String

    public init(baseLanguageCode: String) {
        var value = baseLanguageCode.lowercased()

        let rawSuffix = "-raw"
        if value.hasSuffix(rawSuffix) {
            value = String(value.dropLast(rawSuffix.count))
        }

        if let separator = value.firstIndex(where: { character in
            character == "-" || character == "_"
        }) {
            value = String(value[..<separator])
        }

        self.languageCode = value
    }

    public func text(_ key: CustomStringKey) -> String {
        if self.languageCode == "ru",
           let value = Self.russian[key] {
            return value
        }

        return Self.english[key]!
    }

    public var settingsTitle: String { self.text(.settingsTitle) }
    public var searchSettings: String { self.text(.searchSettings) }
    public var searchSettingsHint: String { self.text(.searchSettingsHint) }
    public var searchNothingFound: String { self.text(.searchNothingFound) }
    public var extras: String { self.text(.extras) }
    public var basicFunctions: String { self.text(.basicFunctions) }
    public var infoDisplay: String { self.text(.infoDisplay) }
    public var infoDisplayHint: String { self.text(.infoDisplayHint) }
    public var bypassAll: String { self.text(.bypassAll) }
    public var bypassAllHint: String { self.text(.bypassAllHint) }
    public var removeAds: String { self.text(.removeAds) }
    public var removeAdsHint: String { self.text(.removeAdsHint) }
    public var showHiddenChats: String { self.text(.showHiddenChats) }
    public var showHiddenChatsHint: String { self.text(.showHiddenChatsHint) }
    public var invisibleMode: String { self.text(.invisibleMode) }
    public var messages: String { self.text(.messages) }
    public var protectedContent: String { self.text(.protectedContent) }
    public var mediaAndStories: String { self.text(.mediaAndStories) }
    public var appearance: String { self.text(.appearance) }
    public var debugResearch: String { self.text(.debugResearch) }
    public var about: String { self.text(.about) }

    public var debugConsole: String { self.text(.debugConsole) }
    public var debugConsoleHint: String { self.text(.debugConsoleHint) }
    public var debugConsoleCopy: String { self.text(.debugConsoleCopy) }
    public var debugConsoleClear: String { self.text(.debugConsoleClear) }
    public var debugConsoleEmpty: String { self.text(.debugConsoleEmpty) }
    public var extrasHint: String { self.text(.extrasHint) }
    public var extrasMetadataSection: String { self.text(.extrasMetadataSection) }
    public var extrasMetadataToggle: String { self.text(.extrasMetadataToggle) }
    public var extrasAnonymizeNames: String { self.text(.extrasAnonymizeNames) }
    public var extrasMetadataHint: String { self.text(.extrasMetadataHint) }
    public var extrasPrioritySection: String { self.text(.extrasPrioritySection) }
    public var extrasPriorityHint: String { self.text(.extrasPriorityHint) }
    public var basicFunctionsHint: String { self.text(.basicFunctionsHint) }
    public var invisibleModeHint: String { self.text(.invisibleModeHint) }
    public var messagesHint: String { self.text(.messagesHint) }
    public var protectedContentHint: String { self.text(.protectedContentHint) }
    public var mediaAndStoriesHint: String { self.text(.mediaAndStoriesHint) }
    public var appearanceHint: String { self.text(.appearanceHint) }
    public var debugResearchHint: String { self.text(.debugResearchHint) }
    public var dataAndBackupHint: String { self.text(.dataAndBackupHint) }
    public var databaseTitle: String { self.text(.databaseTitle) }
    public var databaseHint: String { self.text(.databaseHint) }
    public var databaseClearTitle: String { self.text(.databaseClearTitle) }
    public var databaseClearHint: String { self.text(.databaseClearHint) }
    public var databaseClearAction: String { self.text(.databaseClearAction) }
    public var databaseClearConfirmTitle: String { self.text(.databaseClearConfirmTitle) }
    public var databaseClearConfirmText: String { self.text(.databaseClearConfirmText) }
    public var databaseClearConfirmYes: String { self.text(.databaseClearConfirmYes) }
    public var databaseCleared: String { self.text(.databaseCleared) }
    public var databaseExportTitle: String { self.text(.databaseExportTitle) }
    public var databaseExportHint: String { self.text(.databaseExportHint) }
    public var databaseExportReadable: String { self.text(.databaseExportReadable) }
    public var databaseExportReadableDone: String { self.text(.databaseExportReadableDone) }
    public var databaseError: String { self.text(.databaseError) }
    public var databaseStatEvents: String { self.text(.databaseStatEvents) }
    public var databaseStatChats: String { self.text(.databaseStatChats) }
    public var databaseStatMedia: String { self.text(.databaseStatMedia) }
    public var databaseClearExportFirst: String { self.text(.databaseClearExportFirst) }
    public var databaseExportOneChatTitle: String { self.text(.databaseExportOneChatTitle) }
    public var databaseExportChooseChat: String { self.text(.databaseExportChooseChat) }
    public var databaseNoEventsForChat: String { self.text(.databaseNoEventsForChat) }
    public var aboutHint: String { self.text(.aboutHint) }

    public var aboutGithub: String { self.text(.aboutGithub) }
    public var aboutGithubNote: String { self.text(.aboutGithubNote) }
    public var aboutChannelLink: String { self.text(.aboutChannelLink) }
    public var aboutChannelNote: String { self.text(.aboutChannelNote) }
    public var aboutBotLink: String { self.text(.aboutBotLink) }
    public var aboutBotNote: String { self.text(.aboutBotNote) }

    public var profileCard: String { self.text(.profileCard) }
    public var showIds: String { self.text(.showIds) }
    public var showDcs: String { self.text(.showDcs) }
    public var registrationDate: String { self.text(.registrationDate) }
    public var localStarsBalance: String { self.text(.localStarsBalance) }
    public var starsBalance: String { self.text(.starsBalance) }
    public func currentVisualBalance(_ balance: String) -> String {
        return self.text(.currentVisualBalance).replacingOccurrences(
            of: "{balance}",
            with: balance
        )
    }

    public var readInvisible: String { self.text(.readInvisible) }
    public var typing: String { self.text(.typing) }
    public var recording: String { self.text(.recording) }
    public var uploading: String { self.text(.uploading) }
    public var choosingSticker: String { self.text(.choosingSticker) }
    public var gameActivity: String { self.text(.gameActivity) }
    public var choosingEmoji: String { self.text(.choosingEmoji) }
    public var hideOnline: String { self.text(.hideOnline) }
    public var scheduledSend: String { self.text(.scheduledSend) }
    public var readReceipts: String { self.text(.readReceipts) }
    public var other: String { self.text(.other) }
    public var hideOnlineHint: String { self.text(.hideOnlineHint) }
    public var typingHint: String { self.text(.typingHint) }
    public var recordingVoiceTitle: String { self.text(.recordingVoiceTitle) }
    public var recordingVoiceHint: String { self.text(.recordingVoiceHint) }
    public var recordingVideoTitle: String { self.text(.recordingVideoTitle) }
    public var recordingVideoHint: String { self.text(.recordingVideoHint) }
    public var recordingRoundTitle: String { self.text(.recordingRoundTitle) }
    public var recordingRoundHint: String { self.text(.recordingRoundHint) }
    public var uploadingVideoTitle: String { self.text(.uploadingVideoTitle) }
    public var uploadingVideoHint: String { self.text(.uploadingVideoHint) }
    public var uploadingVoiceTitle: String { self.text(.uploadingVoiceTitle) }
    public var uploadingVoiceHint: String { self.text(.uploadingVoiceHint) }
    public var uploadingPhotoTitle: String { self.text(.uploadingPhotoTitle) }
    public var uploadingPhotoHint: String { self.text(.uploadingPhotoHint) }
    public var uploadingFileTitle: String { self.text(.uploadingFileTitle) }
    public var uploadingFileHint: String { self.text(.uploadingFileHint) }
    public var uploadingRoundTitle: String { self.text(.uploadingRoundTitle) }
    public var uploadingRoundHint: String { self.text(.uploadingRoundHint) }
    public var choosingLocationTitle: String { self.text(.choosingLocationTitle) }
    public var choosingLocationHint: String { self.text(.choosingLocationHint) }
    public var choosingContactTitle: String { self.text(.choosingContactTitle) }
    public var choosingContactHint: String { self.text(.choosingContactHint) }
    public var gameActivityTitle: String { self.text(.gameActivityTitle) }
    public var gameActivityHint: String { self.text(.gameActivityHint) }
    public var speakingGroupCallTitle: String { self.text(.speakingGroupCallTitle) }
    public var speakingGroupCallHint: String { self.text(.speakingGroupCallHint) }
    public var choosingStickerTitle: String { self.text(.choosingStickerTitle) }
    public var choosingStickerHint: String { self.text(.choosingStickerHint) }
    public var emojiInteractionTitle: String { self.text(.emojiInteractionTitle) }
    public var emojiInteractionHint: String { self.text(.emojiInteractionHint) }
    public var emojiAckTitle: String { self.text(.emojiAckTitle) }
    public var emojiAckHint: String { self.text(.emojiAckHint) }
    public var messageReadReceipts: String { self.text(.messageReadReceipts) }
    public var messageReadReceiptsHint: String { self.text(.messageReadReceiptsHint) }
    public var storyReadReceipts: String { self.text(.storyReadReceipts) }
    public var storyReadReceiptsHint: String { self.text(.storyReadReceiptsHint) }
    public var scheduledSendHint: String { self.text(.scheduledSendHint) }

    public var deletedMessages: String { self.text(.deletedMessages) }
    public var saveDeletedMessages: String { self.text(.saveDeletedMessages) }
    public var showDeletedMessages: String { self.text(.showDeletedMessages) }
    public var editHistory: String { self.text(.editHistory) }
    public var saveEditHistory: String { self.text(.saveEditHistory) }
    public var showEditHistory: String { self.text(.showEditHistory) }
    public var savedDataHint: String { self.text(.savedDataHint) }
    public var textSending: String { self.text(.textSending) }
    public var sendStyle: String { self.text(.sendStyle) }
    public var sendStyleHint: String { self.text(.sendStyleHint) }
    public var deletedReplies: String { self.text(.deletedReplies) }
    public var portableReply: String { self.text(.portableReply) }
    public var saveDeletedMedia: String { self.text(.saveDeletedMedia) }
    public var portableReplyHint: String { self.text(.portableReplyHint) }

    public var protectionEnabled: String { self.text(.protectionEnabled) }
    public var shareFromGallery: String { self.text(.shareFromGallery) }
    public var saveFromGallery: String { self.text(.saveFromGallery) }
    public var copyFromGallery: String { self.text(.copyFromGallery) }
    public var saveFromChat: String { self.text(.saveFromChat) }
    public var copyFromChat: String { self.text(.copyFromChat) }
    public var forwardFromChat: String { self.text(.forwardFromChat) }
    public var allowScreenshots: String { self.text(.allowScreenshots) }
    public var allowScreenRecording: String { self.text(.allowScreenRecording) }

    public var oneTimeScreenshots: String { self.text(.oneTimeScreenshots) }
    public var oneTimeScreenRecording: String { self.text(.oneTimeScreenRecording) }
    public var oneTimeSave: String { self.text(.oneTimeSave) }
    public var oneTimeMedia: String { self.text(.oneTimeMedia) }
    public var storySave: String { self.text(.storySave) }
    public var appearancePlaceholder: String { self.text(.appearancePlaceholder) }
    public var profileBackground: String { self.text(.profileBackground) }
    public var profileBackgroundEffect: String { self.text(.profileBackgroundEffect) }
    public var blurProfileAvatar: String { self.text(.blurProfileAvatar) }
    public var preferAvatarAsBackground: String { self.text(.preferAvatarAsBackground) }
    public var animatedBackground: String { self.text(.animatedBackground) }
    public var colorTint: String { self.text(.colorTint) }
    public var reducedBlur: String { self.text(.reducedBlur) }
    public var animatedBackgroundHint: String { self.text(.animatedBackgroundHint) }
    public var profileEffectDisabledHint: String { self.text(.profileEffectDisabledHint) }
    public var interface: String { self.text(.interface) }
    public var messageSeconds: String { self.text(.messageSeconds) }
    public var messageCharacterCount: String { self.text(.messageCharacterCount) }
    public var hideMyPhone: String { self.text(.hideMyPhone) }
    public var showRamUnderClock: String { self.text(.showRamUnderClock) }
    public var hidePhoneHint: String { self.text(.hidePhoneHint) }
    public var presenceHistoryEmpty: String { self.text(.presenceHistoryEmpty) }
    public var knownUsersNoData: String { self.text(.knownUsersNoData) }
    public var recentEvents: String { self.text(.recentEvents) }
    public var eventsEmpty: String { self.text(.eventsEmpty) }
    public var diagnosticsBufferHint: String { self.text(.diagnosticsBufferHint) }

    public var information: String { self.text(.information) }
    public var telegramId: String { self.text(.telegramId) }
    public var rawIdNamespace: String { self.text(.rawIdNamespace) }
    public var profile: String { self.text(.profile) }
    public var mainMenu: String { self.text(.mainMenu) }

    public var deletedMessage: String { self.text(.deletedMessage) }
    public var editedMessage: String { self.text(.editedMessage) }
    public var sticker: String { self.text(.sticker) }
    public var photo: String { self.text(.photo) }
    public var video: String { self.text(.video) }
    public var gif: String { self.text(.gif) }
    public var audio: String { self.text(.audio) }
    public var voiceMessage: String { self.text(.voiceMessage) }
    public var videoMessage: String { self.text(.videoMessage) }
    public var document: String { self.text(.document) }
    public var attachment: String { self.text(.attachment) }
    public var album: String { self.text(.album) }
    public var poll: String { self.text(.poll) }
    public var location: String { self.text(.location) }
    public var contact: String { self.text(.contact) }
    public var dice: String { self.text(.dice) }
    public var taskList: String { self.text(.taskList) }
    public var user: String { self.text(.user) }

    public var importSettings: String { self.text(.importSettings) }
    public var exportSettings: String { self.text(.exportSettings) }
    public var importArchive: String { self.text(.importArchive) }
    public var exportArchive: String { self.text(.exportArchive) }

    public var sendStyleNormal: String { self.text(.sendStyleNormal) }
    public var sendStyleBold: String { self.text(.sendStyleBold) }
    public var sendStyleItalic: String { self.text(.sendStyleItalic) }
    public var sendStyleMonospace: String { self.text(.sendStyleMonospace) }
    public var sendStyleStrikethrough: String { self.text(.sendStyleStrikethrough) }
    public var sendStyleUnderline: String { self.text(.sendStyleUnderline) }
    public var sendStyleSpoiler: String { self.text(.sendStyleSpoiler) }
    public var sendStyleExamplePrefix: String { self.text(.sendStyleExamplePrefix) }
    public var sendStyleExampleBody: String { self.text(.sendStyleExampleBody) }
    public var community: String { self.text(.community) }
    public var communityHint: String { self.text(.communityHint) }
    public var copyExtensionDiagnostics: String { self.text(.copyExtensionDiagnostics) }
    public var communityLoading: String { self.text(.communityLoading) }
    public var communityUnavailable: String { self.text(.communityUnavailable) }
    public var communityNoPosts: String { self.text(.communityNoPosts) }
    public var profileHistoryTab: String { self.text(.profileHistoryTab) }
    public var presenceHistoryTab: String { self.text(.presenceHistoryTab) }
    public var giftHistoryTab: String { self.text(.giftHistoryTab) }
    public var personalChannelTab: String { self.text(.personalChannelTab) }
    public var profileReportLoading: String { self.text(.profileReportLoading) }

    public func localizedProfileReport(_ raw: String) -> String {
        guard self.languageCode != "ru" else {
            return raw
        }

        let exact: [String: String] = [
            "История изменений профиля": "Profile change history",
            "Изменений после первого наблюдения пока нет.": "No changes since first observation.",
            "История личного канала": "Personal channel history",
            "История подарков пока пуста.": "Gift history is empty.",
            "История подарков": "Gift history",
            "История присутствия пока пуста.": "Presence history is empty.",
            "История профиля пока пуста.": "Profile history is empty.",
            "Личный канал": "Personal channel",
            "Личный канал не найден.": "Personal channel was not found.",
            "онлайн": "online",
            "был недавно": "last seen recently",
            "был на этой неделе": "last seen within a week",
            "был в этом месяце": "last seen within a month",
            "скрытый статус": "hidden status",
            "видимый": "visible",
            "исчез из публичного профиля": "removed from public profile",
            "скрытый владельцем": "hidden by owner",
            "анонимно": "anonymous",
            "Мишка": "Teddy Bear"
        ]
        let prefixes: [(String, String)] = [
            ("История присутствия:", "Presence history:"),
            ("Зафиксировано изменений:", "Recorded changes:"),
            ("Первое наблюдение:", "First observed:"),
            ("Последнее наблюдение:", "Last observed:"),
            ("Последние сообщения:", "Latest messages:"),
            ("Имя:", "Name:"),
            ("Юзернейм:", "Username:"),
            ("Описание:", "Bio:"),
            ("Эмодзи-статус:", "Emoji status:"),
            ("Аватар: установлен", "Avatar: set"),
            ("Аватар: удалён", "Avatar: removed"),
            ("Аватар: изменён", "Avatar: changed"),
            ("Личный канал: откреплён", "Personal channel: detached"),
            ("Личный канал: прикреплён", "Personal channel: attached"),
            ("Канал ID:", "Channel ID:"),
            ("Название:", "Title:"),
            ("Ссылка:", "Link:"),
            ("Подписчики:", "Subscribers:"),
            ("Последний message ID:", "Latest message ID:"),
            ("Записей:", "Entries:"),
            ("ID подарка:", "Gift ID:"),
            ("Уникальный ID:", "Unique ID:"),
            ("Номер:", "Number:"),
            ("Отправитель:", "Sender:"),
            ("ID отправителя:", "Sender ID:"),
            ("Сообщение:", "Message:"),
            ("Статус: видимый", "Status: visible"),
            ("Подарок ", "Gift "),
            ("до ", "until ")
        ]

        func translateSegment(_ segment: String) -> String {
            if let value = exact[segment] {
                return value
            }
            for (source, target) in prefixes where segment.hasPrefix(source) {
                return target + String(segment.dropFirst(source.count))
            }
            return segment
        }

        return raw.components(separatedBy: "\n").map { line in
            let bullet = line.hasPrefix("• ") ? "• " : ""
            let content = bullet.isEmpty ? line : String(line.dropFirst(2))
            let translated = content.components(separatedBy: " · ")
                .map(translateSegment)
                .joined(separator: " · ")
            return bullet + translated
        }.joined(separator: "\n")
    }

    private static let english: [CustomStringKey: String] = [
        .settingsTitle: "Settings",
        .searchSettings: "Search settings",
        .searchSettingsHint: "Find a setting",
        .searchNothingFound: "Nothing Found",
        .basicFunctions: "Basic Functions",
        .infoDisplay: "Info Display",
        .infoDisplayHint: "Profile info, messages, phone",
        .bypassAll: "Bypass all Telegram restrictions",
        .bypassAllHint: "One switch for everything: saving, copying and forwarding protected content, screenshots, screen recording, and saving or capturing view-once media.",
        .removeAds: "Remove Ads",
        .removeAdsHint: "Hide all sponsored posts in channels and all ads across Telegram without a Premium subscription.",
        .debugConsole: "Debug Console",
        .debugConsoleHint: "App event log for diagnosing crashes and errors",
        .debugConsoleCopy: "Copy Log",
        .debugConsoleClear: "Clear Log",
        .debugConsoleEmpty: "No events recorded yet. When the app crashes or hits an error, the details will appear here.",
        .showHiddenChats: "Open chats hidden by Telegram rules",
        .showHiddenChatsHint: "Channels, groups and individual messages can be flagged as restricted by Telegram's rules, App Store requirements or local law. The server still sends the content in full — it is the app that hides it, so the flag can be ignored. Does not apply to child abuse material, and does not help with channels Telegram has deleted or banned: there the server sends nothing at all.",
        .invisibleMode: "Invisible Mode",
        .messages: "Messages",
        .protectedContent: "Protected Content",
        .mediaAndStories: "Media & Stories",
        .appearance: "Appearance",
        .debugResearch: "Debug / Research",
        .about: "About",
        .extras: "Extras",
        .extrasHint: "Metadata stripping and privacy extras",
        .extrasMetadataSection: "Outgoing Metadata",
        .extrasMetadataToggle: "Strip Metadata Before Sending",
        .extrasAnonymizeNames: "Anonymize File Names",
        .extrasMetadataHint: "Removes EXIF/GPS, ICC profiles, XMP and other metadata from photos, videos, PDF and Office documents before they are uploaded.",
        .extrasPrioritySection: "Notes",
        .extrasPriorityHint: "If a file cannot be processed it is sent unchanged.",
        .basicFunctionsHint: "Profile info, stars, backup",
        .invisibleModeHint: "Hide online, reads and typing",
        .messagesHint: "Deleted, edited, cache",
        .protectedContentHint: "Screenshots and saving protection",
        .mediaAndStoriesHint: "Stories, media and downloads",
        .appearanceHint: "Avatars, message bubbles, effects",
        .debugResearchHint: "Diagnostics and research tools",
        .dataAndBackupHint: "Archive, export, retention",
        .databaseTitle: "Database",
        .databaseHint: "Captured deleted/edited messages, media and settings",
        .databaseClearTitle: "Clear Database",
        .databaseClearHint: "Events are captured deleted/edited messages and recovered media",
        .databaseClearAction: "Delete All Events and Media",
        .databaseClearConfirmTitle: "Clear Database",
        .databaseClearConfirmText: "Delete all captured events (deleted/edited messages) and their media? A readable export will be saved first. This cannot be undone.",
        .databaseClearConfirmYes: "Delete Everything",
        .databaseCleared: "Database cleared",
        .databaseExportTitle: "Export Chat (Readable)",
        .databaseExportReadable: "Export Chat History (HTML)",
        .databaseExportOneChatTitle: "Export One Chat (HTML)",
        .databaseExportChooseChat: "Choose Chat",
        .databaseNoEventsForChat: "No events recorded for this chat yet.",
        .databaseExportHint: "Creates a readable HTML file with deleted messages, edits and embedded media (files up to 10 MB are embedded)",
        .databaseExportReadableDone: "Export saved. Use the Files app or share sheet to save it.",
        .databaseError: "Operation failed",
        .databaseStatEvents: "Events",
        .databaseStatChats: "Chats",
        .databaseStatMedia: "Media files",
        .databaseClearExportFirst: "Export First (HTML)",
        .aboutHint: "Version, channel, developer",
        .aboutGithub: "GitHub",
        .aboutGithubNote: "New releases are published on GitHub.",
        .aboutChannelLink: "Telegram Channel",
        .aboutChannelNote: "News about new builds and updates are posted in the Telegram channel.",
        .aboutBotLink: "Telegram Bot",
        .aboutBotNote: "You can reach the developer and share feedback in the Telegram bot.",

        .profileCard: "Profile Card",
        .showIds: "Show IDs",
        .showDcs: "Show DCs",
        .registrationDate: "Registration Date",
        .localStarsBalance: "Local Stars Balance",
        .starsBalance: "Stars Balance",
        .currentVisualBalance: "Current visual balance: {balance} ⭐",

        .readInvisible: "Don't Mark as Read",
        .typing: "Typing",
        .recording: "Recording",
        .uploading: "Uploading",
        .choosingSticker: "Choosing Sticker",
        .gameActivity: "Game Activity",
        .choosingEmoji: "Choosing Emoji",
        .hideOnline: "Online Status",
        .scheduledSend: "Scheduled Send",
        .readReceipts: "Read Receipts",
        .other: "Other",
        .hideOnlineHint: "Prevent others from seeing you online.",
        .typingHint: "Hide when you're typing messages.",
        .recordingVoiceTitle: "Disable Voice Message Recording Status",
        .recordingVoiceHint: "Hide when you're recording a voice message.",
        .recordingVideoTitle: "Disable Recording Video Status",
        .recordingVideoHint: "Hide when you're recording a video.",
        .recordingRoundTitle: "Disable Recording Round Video Status",
        .recordingRoundHint: "Hide when you're recording a round video.",
        .uploadingVideoTitle: "Disable Uploading Video Status",
        .uploadingVideoHint: "Hide when you're uploading a video.",
        .uploadingVoiceTitle: "Disable Voice Message Uploading Status",
        .uploadingVoiceHint: "Hide when you're uploading a voice message.",
        .uploadingPhotoTitle: "Disable Uploading Photo Status",
        .uploadingPhotoHint: "Hide when you're uploading a Photo.",
        .uploadingFileTitle: "Disable Uploading File Status",
        .uploadingFileHint: "Hide when you're uploading a file.",
        .uploadingRoundTitle: "Disable Uploading Round Video Status",
        .uploadingRoundHint: "Disable Uploading Round Video Status",
        .choosingLocationTitle: "Disable Choosing Location Status",
        .choosingLocationHint: "Hide when you're choosing a location.",
        .choosingContactTitle: "Disable Choosing Contact",
        .choosingContactHint: "Hide when you're choosing a contact.",
        .gameActivityTitle: "Disable Playing Game Status",
        .gameActivityHint: "Hide when you're playing a game.",
        .speakingGroupCallTitle: "Disable Speaking in Group Call Status",
        .speakingGroupCallHint: "Hide when you're speaking in a group call.",
        .choosingStickerTitle: "Disable Choosing Sticker Status",
        .choosingStickerHint: "Hide when you're picking a sticker.",
        .emojiInteractionTitle: "Disable Emoji Interaction Status",
        .emojiInteractionHint: "Hide when you interact with emoji.",
        .emojiAckTitle: "Disable Emoji Acknowledgement Status",
        .emojiAckHint: "Hide when you react with emoji to a message.",
        .messageReadReceipts: "Disable Message Read Receipts",
        .messageReadReceiptsHint: "Prevent others from seeing you've read their messages.",
        .storyReadReceipts: "Disable Story Read Receipts",
        .storyReadReceiptsHint: "Prevent others from seeing you've viewed their stories.",
        .scheduledSendHint: "Delay outgoing messages.",

        .deletedMessages: "Deleted Messages",
        .saveDeletedMessages: "Save Deleted",
        .showDeletedMessages: "Show Deleted Messages",
        .editHistory: "Edit History",
        .saveEditHistory: "Save Edit History",
        .showEditHistory: "Show Edit History",
        .savedDataHint: "Disabling these features does not remove already saved data.",
        .textSending: "Text Sending",
        .sendStyle: "Send Style",
        .sendStyleHint: "The style is applied after tapping the send button.",
        .deletedReplies: "Deleted Replies",
        .portableReply: "Portable Reply",
        .saveDeletedMedia: "Save Deleted Media",
        .portableReplyHint: "The reply is materialized only after Send. Media is kept only in the app's internal cache: up to 1 GB for 30 days; if bytes are unavailable, a text fallback is used.",

        .protectionEnabled: "Bypass Protection",
        .shareFromGallery: "Share from Gallery",
        .saveFromGallery: "Save from Gallery",
        .copyFromGallery: "Copy from Gallery",
        .saveFromChat: "Save from Chat",
        .copyFromChat: "Copy from Chat",
        .forwardFromChat: "Forward from Chat",
        .allowScreenshots: "Allow Screenshots",
        .allowScreenRecording: "Allow Screen Recording",

        .oneTimeScreenshots: "One-Time Media Screenshots",
        .oneTimeScreenRecording: "One-Time Media Screen Recording",
        .oneTimeSave: "Save One-Time Media",
        .oneTimeMedia: "One-Time Media",
        .storySave: "Save Stories",
        .appearancePlaceholder: "Appearance settings will be added here.",
        .profileBackground: "Profile Background",
        .profileBackgroundEffect: "Profile Background Effect",
        .blurProfileAvatar: "Blur Profile Avatar",
        .preferAvatarAsBackground: "Prefer Avatar as Background",
        .animatedBackground: "Animated Background",
        .colorTint: "Color Tint",
        .reducedBlur: "Reduced Blur",
        .animatedBackgroundHint: "The video avatar loops and uses Telegram's cache. In Low Power Mode or with Reduced Blur, a static frame is used.",
        .profileEffectDisabledHint: "When the main effect is disabled, the app creates no additional profile views, observers, or image/palette pipeline. New values apply the next time the profile opens.",
        .interface: "Interface",
        .messageSeconds: "Message Seconds",
        .messageCharacterCount: "Character Count",
        .hideMyPhone: "Hide My Phone Number",
        .showRamUnderClock: "Show RAM Under Clock",
        .hidePhoneHint: "Your phone number is hidden only locally. Profile editing and number changing remain available.",
        .presenceHistoryEmpty: "Presence history is empty",
        .knownUsersNoData: "Known users: no data",
        .recentEvents: "Recent Events",
        .eventsEmpty: "No events yet",
        .diagnosticsBufferHint: "The buffer is limited to 200 lines. Collection does not start when this page opens.",

        .information: "Information",
        .telegramId: "Telegram ID",
        .rawIdNamespace: "Raw ID / Namespace",
        .profile: "Profile",
        .mainMenu: "Main Menu",

        .deletedMessage: "Deleted Message",
        .editedMessage: "Edited Message",
        .sticker: "Sticker",
        .photo: "Photo",
        .video: "Video",
        .gif: "GIF",
        .audio: "Audio",
        .voiceMessage: "Voice Message",
        .videoMessage: "Video Message",
        .document: "Document",
        .attachment: "Attachment",
        .album: "Album",
        .poll: "Poll",
        .location: "Location",
        .contact: "Contact",
        .dice: "Dice",
        .taskList: "Task List",
        .user: "User",

        .importSettings: "Import Settings",
        .exportSettings: "Export Settings",
        .importArchive: "Import Archive",
        .exportArchive: "Export Archive",

        .sendStyleNormal: "Normal",
        .sendStyleBold: "Bold",
        .sendStyleItalic: "Italic",
        .sendStyleMonospace: "Monospace",
        .sendStyleStrikethrough: "Strikethrough",
        .sendStyleUnderline: "Underline",
        .sendStyleSpoiler: "Spoiler",
        .sendStyleExamplePrefix: "Example: ",
        .sendStyleExampleBody: "this is how your text will look",
        .community: "Community",
        .communityHint: "News, builds and updates",
        .copyExtensionDiagnostics: "Copy Extension Diagnostics",
        .communityLoading: "Loading channel…",
        .communityUnavailable: "Channel information is temporarily unavailable",
        .communityNoPosts: "No posts yet",
        .profileHistoryTab: "History",
        .presenceHistoryTab: "Presence",
        .giftHistoryTab: "Gift History",
        .personalChannelTab: "Channel",
        .profileReportLoading: "Loading…"
    ]

    private static let russian: [CustomStringKey: String] = [
        .settingsTitle: "Настройки",
        .searchSettings: "Поиск настроек",
        .searchSettingsHint: "Найти настройку",
        .searchNothingFound: "Ничего не найдено",
        .basicFunctions: "Основные функции",
        .infoDisplay: "Отображение информации",
        .infoDisplayHint: "Профиль, сообщения, телефон",
        .bypassAll: "Обход всех ограничений Telegram",
        .bypassAllHint: "Один переключатель для всего: сохранение, копирование и пересылка защищённого контента, скриншоты, запись экрана, а также сохранение и захват медиа с одиночным просмотром.",
        .removeAds: "Убирать рекламу",
        .removeAdsHint: "Скрывает все спонсорские посты в каналах и всю рекламу в Telegram без подписки Premium.",
        .debugConsole: "Дебаг-консоль",
        .debugConsoleHint: "Журнал событий приложения для диагностики сбоев",
        .debugConsoleCopy: "Скопировать журнал",
        .debugConsoleClear: "Очистить журнал",
        .debugConsoleEmpty: "Событий пока нет. Когда приложение упадёт или возникнет ошибка, подробности появятся здесь.",
        .showHiddenChats: "Открывать чаты, скрытые по правилам Telegram",
        .showHiddenChatsHint: "Каналы, группы и отдельные сообщения могут быть помечены как ограниченные правилами Telegram, требованиями App Store или местным законодательством. Сервер присылает контент полностью — скрывает его само приложение, поэтому флаг можно игнорировать. Не относится к материалам с несовершеннолетними и не помогает с удалёнными или забаненными каналами: там сервер не присылает ничего.",
        .invisibleMode: "Режим призрака",
        .messages: "Сообщения",
        .protectedContent: "Защищённый контент",
        .mediaAndStories: "Медиа и истории",
        .appearance: "Оформление",
        .debugResearch: "Отладка / Исследования",
        .about: "О приложении",

        .basicFunctionsHint: "Информация профиля, звёзды, бэкап",
        .invisibleModeHint: "Скрытие онлайн, прочтений и набора",
        .messagesHint: "Удалённые, изменённые, кэш",
        .protectedContentHint: "Защита от скриншотов и сохранения",
        .mediaAndStoriesHint: "Истории, медиа и загрузки",
        .appearanceHint: "Аватары, пузыри сообщений, эффекты",
        .debugResearchHint: "Диагностика и инструменты исследования",
        .dataAndBackupHint: "Архив, экспорт, хранение",
        .databaseTitle: "База данных",
        .databaseHint: "Захваченные удалённые/изменённые сообщения, медиа и настройки",
        .databaseClearTitle: "Очистка базы",
        .databaseClearHint: "События — это захваченные удалённые/изменённые сообщения и восстановленные медиа",
        .databaseClearAction: "Удалить все события и медиа",
        .databaseClearConfirmTitle: "Очистка базы",
        .databaseClearConfirmText: "Удалить все захваченные события (удалённые/изменённые сообщения) и их медиа? Сначала будет сохранён читаемый экспорт. Действие необратимо.",
        .databaseClearConfirmYes: "Удалить всё",
        .databaseCleared: "База очищена",
        .databaseExportTitle: "Экспорт чата (читаемый)",
        .databaseExportReadable: "Экспорт истории чата (HTML)",
        .databaseExportOneChatTitle: "Экспорт одного чата (HTML)",
        .databaseExportChooseChat: "Выберите чат",
        .databaseNoEventsForChat: "Для этого чата пока нет сохранённых событий.",
        .databaseExportHint: "Создаёт читаемый HTML-файл с удалёнными сообщениями, правками и встроенными медиа (файлы до 10 МБ встраиваются)",
        .databaseExportReadableDone: "Экспорт готов. Сохраните его через приложение «Файлы» или меню «Поделиться».",
        .databaseError: "Операция не удалась",
        .databaseStatEvents: "События",
        .databaseStatChats: "Чаты",
        .databaseStatMedia: "Медиа-файлы",
        .databaseClearExportFirst: "Сначала экспорт (HTML)",
        .aboutHint: "Версия, канал, разработчик",
        .aboutGithub: "GitHub",
        .aboutGithubNote: "На GitHub будут выходить новые релизы.",
        .aboutChannelLink: "Телеграм-канал",
        .aboutChannelNote: "В Телеграм-канале выходят новости о новых сборках и обновлениях.",
        .aboutBotLink: "Телеграм-бот",
        .aboutBotNote: "В Телеграм-боте можно поддерживать связь с разработчиком.",

        .profileCard: "Карточка профиля",
        .showIds: "Показывать ID",
        .showDcs: "Показывать DC",
        .registrationDate: "Дата регистрации",
        .localStarsBalance: "Локальный баланс Stars",
        .starsBalance: "Баланс Stars",
        .currentVisualBalance: "Текущий визуальный баланс: {balance} ⭐",

        .readInvisible: "Не отмечать прочитанным",
        .typing: "Набор текста",
        .recording: "Запись",
        .uploading: "Загрузка",
        .choosingSticker: "Выбор стикера",
        .gameActivity: "Игровая активность",
        .choosingEmoji: "Выбор эмодзи",
        .hideOnline: "Онлайн-статус",
        .scheduledSend: "Отложенная отправка",
        .readReceipts: "Отметки о прочтении",
        .hideOnlineHint: "Никто не видит, что вы онлайн.",
        .typingHint: "Скрывает набор текста.",
        .recordingVoiceTitle: "Скрыть запись голосовых",
        .recordingVoiceHint: "Скрывает запись голосового сообщения.",
        .recordingVideoTitle: "Скрыть запись видео",
        .recordingVideoHint: "Скрывает запись видео.",
        .recordingRoundTitle: "Скрыть запись круговых видео",
        .recordingRoundHint: "Скрывает запись кругового видео.",
        .uploadingVideoTitle: "Скрыть загрузку видео",
        .uploadingVideoHint: "Скрывает загрузку видео.",
        .uploadingVoiceTitle: "Скрыть загрузку голосовых",
        .uploadingVoiceHint: "Скрывает загрузку голосового сообщения.",
        .uploadingPhotoTitle: "Скрыть загрузку фото",
        .uploadingPhotoHint: "Скрывает загрузку фото.",
        .uploadingFileTitle: "Скрыть загрузку файлов",
        .uploadingFileHint: "Скрывает загрузку файла.",
        .uploadingRoundTitle: "Скрыть загрузку круговых видео",
        .uploadingRoundHint: "Скрывает загрузку кругового видео.",
        .choosingLocationTitle: "Скрыть выбор геолокации",
        .choosingLocationHint: "Скрывает выбор геолокации.",
        .choosingContactTitle: "Скрыть выбор контакта",
        .choosingContactHint: "Скрывает выбор контакта.",
        .gameActivityTitle: "Скрыть игровой статус",
        .gameActivityHint: "Скрывает статус игры.",
        .speakingGroupCallTitle: "Скрыть разговор в звонке",
        .speakingGroupCallHint: "Скрывает разговор в групповом звонке.",
        .choosingStickerTitle: "Скрыть выбор стикера",
        .choosingStickerHint: "Скрывает выбор стикера.",
        .emojiInteractionTitle: "Скрыть взаимодействие с эмодзи",
        .emojiInteractionHint: "Скрывает взаимодействие с эмодзи.",
        .emojiAckTitle: "Скрыть реакции эмодзи",
        .emojiAckHint: "Скрывает реакции эмодзи на сообщения.",
        .messageReadReceipts: "Не отмечать сообщения прочитанными",
        .messageReadReceiptsHint: "Собеседник не видит, что вы прочитали его сообщения.",
        .storyReadReceipts: "Не отмечать истории просмотренными",
        .storyReadReceiptsHint: "Автор не видит, что вы смотрели его истории.",
        .scheduledSendHint: "Задержка отправки исходящих сообщений.",

        .deletedMessages: "Удалённые сообщения",
        .saveDeletedMessages: "Сохранять удалённые",
        .showDeletedMessages: "Показывать удалённые сообщения",
        .editHistory: "История изменений",
        .saveEditHistory: "Сохранять историю изменений",
        .showEditHistory: "Показывать историю изменений",
        .savedDataHint: "Выключение функций не удаляет уже сохранённые данные.",
        .textSending: "Отправка текста",
        .sendStyle: "Стиль отправки",
        .sendStyleHint: "Стиль применяется после нажатия кнопки отправки.",
        .deletedReplies: "Удалённые ответы",
        .portableReply: "Переносимый ответ",
        .saveDeletedMedia: "Сохранять удалённые медиа",
        .portableReplyHint: "Ответ материализуется только после Send. Медиа хранится только во внутреннем кэше приложения: до 1 ГБ, 30 дней; если bytes недоступны, используется текстовый fallback.",

        .protectionEnabled: "Включить обход защиты",
        .shareFromGallery: "Поделиться из галереи",
        .saveFromGallery: "Сохранить из галереи",
        .copyFromGallery: "Копировать из галереи",
        .saveFromChat: "Сохранить из чата",
        .copyFromChat: "Копировать из чата",
        .forwardFromChat: "Переслать из чата",
        .allowScreenshots: "Разрешить скриншоты",
        .allowScreenRecording: "Разрешить запись экрана",

        .oneTimeScreenshots: "Скриншоты одноразовых медиа",
        .oneTimeScreenRecording: "Запись одноразовых медиа",
        .oneTimeSave: "Сохранение одноразовых медиа",
        .oneTimeMedia: "Одноразовые медиа",
        .storySave: "Сохранение историй",
        .appearancePlaceholder: "Настройки оформления будут добавляться в этот раздел.",
        .profileBackground: "Фон профиля",
        .profileBackgroundEffect: "Эффект фона профиля",
        .blurProfileAvatar: "Размывать аватар в профиле",
        .preferAvatarAsBackground: "Предпочитать аватар как фон",
        .animatedBackground: "Анимированный фон",
        .colorTint: "Цветовой оттенок",
        .reducedBlur: "Облегчённое размытие",
        .animatedBackgroundHint: "Видеоаватар зацикливается и использует кэш Telegram. В режиме энергосбережения или облегчённого размытия используется статический кадр.",
        .profileEffectDisabledHint: "Когда главный эффект выключен, приложение не создаёт дополнительные profile views, observers или image/palette pipeline. Новые значения применяются при следующем открытии профиля.",
        .other: "Прочее",
        .interface: "Интерфейс",
        .messageSeconds: "Секунды в сообщениях",
        .messageCharacterCount: "Счётчик символов",
        .hideMyPhone: "Скрывать мой номер",
        .showRamUnderClock: "Показывать RAM под часами",
        .hidePhoneHint: "Номер скрывается только локально. Экран изменения профиля и смены номера остаётся доступен.",
        .presenceHistoryEmpty: "История присутствия пока пуста",
        .knownUsersNoData: "Известные пользователи: нет данных",
        .recentEvents: "Последние события",
        .eventsEmpty: "Событий пока нет",
        .diagnosticsBufferHint: "Буфер ограничен 200 строками. Сбор не запускается при открытии этой страницы.",

        .information: "Сведения",
        .telegramId: "Telegram ID",
        .rawIdNamespace: "Raw ID / Namespace",
        .profile: "Профиль",
        .mainMenu: "Главное меню",

        .deletedMessage: "Удалённое сообщение",
        .editedMessage: "Изменённое сообщение",
        .sticker: "Стикер",
        .photo: "Фото",
        .video: "Видео",
        .gif: "GIF",
        .audio: "Аудио",
        .voiceMessage: "Голосовое сообщение",
        .videoMessage: "Видеосообщение",
        .document: "Документ",
        .attachment: "Вложение",
        .album: "Альбом",
        .poll: "Опрос",
        .location: "Геолокация",
        .contact: "Контакт",
        .dice: "Бросок кубика",
        .taskList: "Список задач",
        .user: "Пользователь",

        .importSettings: "Импорт настроек",
        .exportSettings: "Экспорт настроек",
        .importArchive: "Импорт архива",
        .exportArchive: "Экспорт архива",

        .sendStyleNormal: "Обычный",
        .sendStyleBold: "Жирный",
        .sendStyleItalic: "Курсив",
        .sendStyleMonospace: "Моноширинный",
        .sendStyleStrikethrough: "Зачёркнутый",
        .sendStyleUnderline: "Подчёркнутый",
        .sendStyleSpoiler: "Спойлер",
        .sendStyleExamplePrefix: "Пример: ",
        .sendStyleExampleBody: "так будет выглядеть ваш текст",
        .community: "Сообщество",
        .communityHint: "Новости, сборки и обновления",
        .copyExtensionDiagnostics: "Копировать диагностику расширений",
        .communityLoading: "Загрузка канала…",
        .communityUnavailable: "Информация о канале временно недоступна",
        .communityNoPosts: "Публикаций пока нет",
        .profileHistoryTab: "История",
        .presenceHistoryTab: "Присутствие",
        .giftHistoryTab: "Подарки · история",
        .personalChannelTab: "Канал",
        .profileReportLoading: "Загрузка…"
    ]
}

public extension PresentationStrings {
    var custom: CustomStrings {
        return CustomStrings(
            baseLanguageCode: self.baseLanguageCode
        )
    }
}


public extension CustomStrings {
    var dataAndBackup: String { self.languageCode == "ru" ? "Данные и резервная копия" : "Data and Backup" }
    var retentionRules: String { self.languageCode == "ru" ? "Правила хранения" : "Retention Rules" }
    var historyDuration: String { self.languageCode == "ru" ? "Хранить историю" : "Keep History" }
    var recoveredMediaLimit: String { self.languageCode == "ru" ? "Лимит восстановленных медиа" : "Recovered Media Limit" }
    var archiveSecretChats: String { self.languageCode == "ru" ? "Архивировать Secret Chats" : "Archive Secret Chats" }
    var perChatRules: String { self.languageCode == "ru" ? "Правила по чатам" : "Per-Chat Rules" }
    var cleanupExpired: String { self.languageCode == "ru" ? "Очистить истёкшие данные" : "Clean Up Expired Data" }
    var backup: String { self.languageCode == "ru" ? "Резервная копия" : "Backup" }
    var disabled: String { self.languageCode == "ru" ? "Не сохранять" : "Do Not Save" }
    var forever: String { self.languageCode == "ru" ? "Бессрочно" : "Forever" }
    var unlimited: String { self.languageCode == "ru" ? "Без лимита" : "Unlimited" }
    var foreverUnlimitedWarning: String { self.languageCode == "ru" ? "Бессрочное хранение без лимита может занять всё свободное место." : "Forever with no size limit can use all available storage." }
    func days(_ value: Int) -> String { self.languageCode == "ru" ? "\(value) дней" : "\(value) days" }
    func databaseExportStats(_ events: Int, _ chats: Int, _ attachedMedia: Int) -> String {
        if self.languageCode == "ru" {
            return "\(events) событий · \(chats) чатов · медиа-файлов: \(attachedMedia)"
        } else {
            return "\(events) events · \(chats) chats · media files: \(attachedMedia)"
        }
    }
    func backupAccountHint(_ accountPeerId: Int64) -> String { self.languageCode == "ru" ? "Архив относится только к аккаунту Telegram ID \(accountPeerId)." : "This archive belongs only to Telegram account ID \(accountPeerId)." }
    func importSettingsConfirmation(_ accountPeerId: Int64) -> String { self.languageCode == "ru" ? "Применить тумблеры и правила хранения для Telegram ID \(accountPeerId)?" : "Apply toggles and retention rules for Telegram ID \(accountPeerId)?" }
    var saveThisChat: String { self.languageCode == "ru" ? "Сохранять этот чат" : "Save This Chat" }
    func chatRuleHint(_ chatPeerId: Int64) -> String { self.languageCode == "ru" ? "Правило относится только к чату ID \(chatPeerId) текущего аккаунта." : "This rule applies only to chat ID \(chatPeerId) in the current account." }
}



public extension CustomStrings {
    var build119Summary: String {
        self.languageCode == "ru"
            ? "Build 119 · Official Telegram 12.9.2"
            : "Build 119 · Official Telegram 12.9.2"
    }
    var features: String {
        self.languageCode == "ru" ? "Функции" : "Features"
    }
    var change: String {
        self.languageCode == "ru" ? "Изменить" : "Change"
    }
    func starsOverrideSummary(_ enabled: Bool, _ balance: String) -> String {
        if self.languageCode == "ru" {
            return enabled ? "Локально · \(balance) ⭐" : "Выключено · \(balance) ⭐"
        } else {
            return enabled ? "Local · \(balance) ⭐" : "Off · \(balance) ⭐"
        }
    }
    var starsEditorHint: String {
        self.languageCode == "ru"
            ? "Это только локальное отображение баланса. Реальный баланс Telegram не изменяется."
            : "This changes only the local displayed balance. Your real Telegram balance is not modified."
    }
    func appVersionLine(_ version: String) -> String {
        self.languageCode == "ru" ? "Версия \(version)" : "Version \(version)"
    }
    var aboutBuild119Summary: String {            "Official Telegram 12.9.2\nBuild 119"
    }
    func build119DataSummary(_ duration: String, _ mediaLimit: String, _ accountPeerId: Int64) -> String {
        if self.languageCode == "ru" {
            return "\(duration) · \(mediaLimit) · ID \(accountPeerId)"
        } else {
            return "\(duration) · \(mediaLimit) · ID \(accountPeerId)"
        }
    }
    func build119TimeMachineSummary(_ loaded: Int, _ activeKinds: Int, _ authorScoped: Bool) -> String {
        if self.languageCode == "ru" {
            let author = authorScoped ? "автор выбран" : "все авторы"
            return "Загружено \(loaded) · фильтров \(activeKinds) · \(author)"
        } else {
            let author = authorScoped ? "author selected" : "all authors"
            return "\(loaded) loaded · \(activeKinds) filters · \(author)"
        }
    }
}


public extension CustomStrings {
    private func build124StateWord(_ enabled: Bool) -> String {
        if self.languageCode == "ru" {
            return enabled ? "вкл." : "выкл."
        } else {
            return enabled ? "on" : "off"
        }
    }

    func build124HomeSummary(_ profile: Bool, _ glass: Bool, _ stars: Bool) -> String {
        if self.languageCode == "ru" {
            return "Профиль: \(build124StateWord(profile)) · Glass: \(build124StateWord(glass)) · Stars: \(build124StateWord(stars))"
        } else {
            return "Profile: \(build124StateWord(profile)) · Glass: \(build124StateWord(glass)) · Stars: \(build124StateWord(stars))"
        }
    }

    func build124CustomSummary(_ read: Bool, _ typing: Bool, _ presence: Bool, _ scheduled: Bool) -> String {
        let active = [read, typing, presence, scheduled].filter { $0 }.count
        if self.languageCode == "ru" {
            return "Активно базовых режимов: \(active) из 4"
        } else {
            return "Core privacy modes active: \(active) of 4"
        }
    }

    func build124MessagesSummary(_ deleted: Bool, _ edits: Bool, _ media: Bool) -> String {
        if self.languageCode == "ru" {
            return "Удалённые: \(build124StateWord(deleted)) · Правки: \(build124StateWord(edits)) · Медиа: \(build124StateWord(media))"
        } else {
            return "Deleted: \(build124StateWord(deleted)) · Edits: \(build124StateWord(edits)) · Media: \(build124StateWord(media))"
        }
    }

    func build124ProtectedSummary(_ enabled: Bool, _ oneTime: Bool) -> String {
        if self.languageCode == "ru" {
            return "Защита: \(build124StateWord(enabled)) · Одноразовые медиа: \(build124StateWord(oneTime))"
        } else {
            return "Protection: \(build124StateWord(enabled)) · One-time media: \(build124StateWord(oneTime))"
        }
    }

    func build124MediaSummary(_ oneTime: Bool, _ stories: Bool) -> String {
        if self.languageCode == "ru" {
            return "Одноразовые медиа: \(build124StateWord(oneTime)) · Истории: \(build124StateWord(stories))"
        } else {
            return "One-time media: \(build124StateWord(oneTime)) · Stories: \(build124StateWord(stories))"
        }
    }

    func build124AppearanceSummary(_ glass: Bool, _ ram: Bool, _ seconds: Bool) -> String {
        if self.languageCode == "ru" {
            return "Glass: \(build124StateWord(glass)) · RAM: \(build124StateWord(ram)) · Секунды: \(build124StateWord(seconds))"
        } else {
            return "Glass: \(build124StateWord(glass)) · RAM: \(build124StateWord(ram)) · Seconds: \(build124StateWord(seconds))"
        }
    }

    var build124DiagnosticsSummary: String {
        if self.languageCode == "ru" {
            return "Диагностика и исследовательские инструменты"
        } else {
            return "Diagnostics and research tools"
        }
    }

    var build124AboutSummary: String {
        return CustomReleaseIdentity.aboutText
    }

    func build124DataSummary(_ duration: String, _ mediaLimit: String, _ accountPeerId: Int64) -> String {
        if self.languageCode == "ru" {
            return "\(duration) · \(mediaLimit) · аккаунт \(accountPeerId)"
        } else {
            return "\(duration) · \(mediaLimit) · account \(accountPeerId)"
        }
    }

    func build124TimeMachineSummary(_ loaded: Int, _ activeKinds: Int, _ authorScoped: Bool) -> String {
        if self.languageCode == "ru" {
            let author = authorScoped ? "автор выбран" : "все авторы"
            return "Загружено \(loaded) · фильтров \(activeKinds) · \(author)"
        } else {
            let author = authorScoped ? "author selected" : "all authors"
            return "\(loaded) loaded · \(activeKinds) filters · \(author)"
        }
    }
}

// Bot-account UI follows Telegram's selected interface language through the
// same CustomStrings owner as the rest of Custom. Persisted diagnostic
// status values remain semantic English tokens and are translated only here.
public extension CustomStrings {
    private var botIsRussian: Bool { self.languageCode == "ru" }

    var botCapabilityTitle: String { self.botIsRussian ? "Возможности бот-аккаунта" : "Bot Account Capabilities" }
    var botCapabilityAction: String { self.botIsRussian ? "Проверить RPC бот-аккаунта" : "Check Bot Account RPC" }
    var botDifferenceAction: String { self.botIsRussian ? "Проверить updates.getDifference" : "Check updates.getDifference" }
    var botNoResults: String { self.botIsRussian ? "Результатов пока нет." : "No results yet." }

    func botDiagnosticReport(status: String, updated: String, report: String) -> String {
        let localizedStatus: String
        switch status {
        case "not tested": localizedStatus = self.botIsRussian ? "не проверено" : "not tested"
        case "running": localizedStatus = self.botIsRussian ? "выполняется" : "running"
        case "completed": localizedStatus = self.botIsRussian ? "завершено" : "completed"
        default: localizedStatus = status
        }
        let localizedUpdated = updated == "none" ? (self.botIsRussian ? "нет" : "none") : updated
        let statusLabel = self.botIsRussian ? "Статус" : "Status"
        let updatedLabel = self.botIsRussian ? "Обновлено" : "Updated"
        return "\(statusLabel): \(localizedStatus)\n\(updatedLabel): \(localizedUpdated)\n\n\(report)"
    }
}



public extension CustomStrings {
    var version: String { self.languageCode == "ru" ? "ВЕРСИЯ" : "VERSION" }
    var privacy: String { self.languageCode == "ru" ? "КОНФИДЕНЦИАЛЬНОСТЬ" : "PRIVACY" }
    var customVersion: String { self.languageCode == "ru" ? "Версия" : "Version" }
    var build: String { self.languageCode == "ru" ? "Сборка" : "Build" }
    var telegramBase: String { self.languageCode == "ru" ? "База Telegram" : "Telegram Base" }
}

public extension CustomStrings {
    var blockedUsers: String {
        self.languageCode == "ru" ? "ЗАБЛОКИРОВАННЫЕ" : "BLOCKED USERS"
    }

    var hideBlockedMessages: String {
        self.languageCode == "ru"
            ? "Скрывать сообщения заблокированных"
            : "Hide Blocked Messages"
    }

    var hideBlockedReactions: String {
        self.languageCode == "ru"
            ? "Скрывать реакции заблокированных"
            : "Hide Blocked Reactions"
    }
}

public enum CustomReleaseIdentity {
    public static let displayVersion = "1.0.2"
    public static let technicalVersion = "1.0.2"
    public static let build = "138"
    public static let telegramBase = "12.9.2"

    public static var aboutText: String {
        return "Version \(displayVersion)\nBuild \(build)\nTelegram Base \(telegramBase)"
    }
}


// These labels follow Telegram's selected interface language through
// PresentationStrings.baseLanguageCode. English remains the fallback.
public extension CustomStrings {
    var messageHistory: String {
        return self.languageCode == "ru" ? "История" : "History"
    }
}
