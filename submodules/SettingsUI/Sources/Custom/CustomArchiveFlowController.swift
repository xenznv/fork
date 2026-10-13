import Foundation
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import PresentationDataUtils
import AccountContext
import AlertUI
import LegacyMediaPickerUI
import CustomCore
import ZipArchive

private let customPortableBooleanKeys: [String] = [
    "custom.Profile.Enabled", "custom.Profile.ShowIds", "custom.Profile.ShowDCs",
    "custom.Profile.ShowRegistration", "custom.Glass.Enabled",
    "custom.ProfileBlur.Avatar", "custom.ProfileBlur.Animated",
    "custom.ProfileBlur.Tint", "custom.ProfileBlur.Reduced",
    "custom.InvisibleMode.ReadMessages", "custom.InvisibleMode.TypingActions",
    "custom.InvisibleMode.HideRecording", "custom.InvisibleMode.HideUploading",
    "custom.InvisibleMode.HideStickerActivity", "custom.InvisibleMode.HideGameActivity",
    "custom.InvisibleMode.HideEmojiActivity", "custom.InvisibleMode.Presence",
    "custom.InvisibleMode.ScheduledSend", "custom.Messages.SaveDeleted",
    "custom.Messages.ShowDeleted", "custom.Messages.SaveEditHistory",
    "custom.Messages.ShowEditHistory", "custom.Messages.DeletedPortableReplies",
    "custom.Messages.PreserveDeletedMedia", "custom.Appearance.ShowRamUnderClock",
    "custom.Appearance.MessageSeconds", "custom.Appearance.HideOwnPhone",
    "custom.ProtectedContent.Enabled", "custom.ProtectedContent.GalleryShare",
    "custom.ProtectedContent.GallerySave", "custom.ProtectedContent.GalleryCopy",
    "custom.ProtectedContent.ChatSave", "custom.ProtectedContent.ChatCopy",
    "custom.ProtectedContent.ChatForward", "custom.ProtectedContent.AllowScreenshots",
    "custom.ProtectedContent.AllowScreenRecording",
    "custom.ProtectedContent.OneTimeScreenshots",
    "custom.ProtectedContent.OneTimeScreenRecording",
    "custom.ProtectedContent.OneTimeSave", "custom.Stories.Save",
    "custom.Stars.LocalBalance.Enabled",
]

private let customPortableStringKeys = [
    "custom.Messages.SendTextStyle",
    "custom.Stars.LocalBalance.Amount",
    "custom.Stars.LocalBalance.BaseAmount",
]

private let customPortableIntegerKeys = [
    "custom.Messages.DeletedMediaCacheLimit",
    "custom.Messages.DeletedMediaRetentionDays",
]

private func customCoreRootURL() -> URL {
    return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Custom", isDirectory: true)
}

private func customSettingsSnapshot(accountPeerId: Int64) -> CustomSettingsSnapshot {
    var toggles: [String: Bool] = [:]
    var strings: [String: String] = [:]
    var integers: [String: Int64] = [:]
    for key in customPortableBooleanKeys {
        let scoped = "custom.account.\(accountPeerId).setting.\(key)"
        if let value = UserDefaults.standard.object(forKey: scoped) as? Bool {
            toggles[key] = value
        } else if let value = UserDefaults.standard.object(forKey: key) as? Bool {
            toggles[key] = value
        }
    }
    for key in customPortableStringKeys {
        let scoped = "custom.account.\(accountPeerId).setting.\(key)"
        if let value = UserDefaults.standard.string(forKey: scoped) {
            strings[key] = value
        } else if let value = UserDefaults.standard.string(forKey: key) {
            strings[key] = value
        }
    }
    for key in customPortableIntegerKeys {
        let scoped = "custom.account.\(accountPeerId).setting.\(key)"
        if let value = UserDefaults.standard.object(forKey: scoped) as? NSNumber {
            integers[key] = value.int64Value
        } else if let value = UserDefaults.standard.object(forKey: key) as? NSNumber {
            integers[key] = value.int64Value
        }
    }
    return CustomSettingsSnapshot(
        accountPeerId: accountPeerId,
        toggles: toggles,
        integerValues: integers,
        stringValues: strings
    )
}

private func customWritePayload<T: Encodable>(
    _ value: T,
    component: CustomArchiveComponent,
    relativePath: String,
    rootURL: URL,
    recordCount: Int
) throws -> CustomArchivePayloadDescriptor {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(value)
    let url = rootURL.appendingPathComponent(relativePath)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: url, options: .atomic)
    return CustomArchivePayloadDescriptor(
        component: component,
        relativePath: relativePath,
        recordCount: recordCount,
        uncompressedBytes: Int64(data.count),
        sha256: CustomSHA256.hex(data)
    )
}

private func customPresentArchiveExportError(
    context: AccountContext,
    controller: ViewController,
    text: String
) {
    Queue.mainQueue().async {
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let alert = textAlertController(
            context: context,
            title: presentationData.strings.custom.exportArchive,
            text: text,
            actions: [
                TextAlertAction(
                    type: .defaultAction,
                    title: presentationData.strings.Common_OK,
                    action: {}
                )
            ]
        )
        controller.present(alert, in: .window(.root), with: nil)
    }
}

public func customPresentArchiveExport(
    context: AccountContext,
    controller: ViewController
) {
    let accountPeerId = context.account.peerId.toInt64()

    // Full event snapshotting, JSON encoding and ZIP creation are intentionally
    // kept off the UI thread. Flush the recorder on this worker first so the
    // archive does not race the 250 ms capture buffer and silently miss the
    // newest deleted/edited events.
    Queue.concurrentDefaultQueue().async {
        let workURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("custom-export-\(UUID().uuidString)", isDirectory: true)
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Custom-\(accountPeerId).custom")
        do {
            CustomCaptureRecorder.flushSynchronously()
            try FileManager.default.createDirectory(at: workURL, withIntermediateDirectories: true)
            let base = "accounts/\(accountPeerId)"
            let settings = customSettingsSnapshot(accountPeerId: accountPeerId)
            let retention = CustomRetentionRuntime.configuration(accountPeerId: accountPeerId)
            let eventStore = CustomJSONLEventStore(rootURL: customCoreRootURL())

            // Never convert a canonical-store failure into an apparently valid
            // empty archive. If reading history fails, surface that failure and
            // leave the user's canonical store untouched.
            let events = try eventStore.events(accountPeerId: accountPeerId, chatPeerId: nil)
            let descriptors = try [
                customWritePayload(
                    settings,
                    component: .settingsSnapshot,
                    relativePath: "\(base)/settings.json",
                    rootURL: workURL,
                    recordCount: settings.toggles.count + settings.stringValues.count
                ),
                customWritePayload(
                    retention,
                    component: .retentionPolicies,
                    relativePath: "\(base)/retention.json",
                    rootURL: workURL,
                    recordCount: retention.chatOverrides.count + 1
                ),
                customWritePayload(
                    events,
                    component: .canonicalEvents,
                    relativePath: "\(base)/events.json",
                    rootURL: workURL,
                    recordCount: events.count
                ),
            ]
            let manifest = CustomArchiveManifestV2(
                createdAtMs: Int64(Date().timeIntervalSince1970 * 1000.0),
                accounts: [
                    CustomArchiveAccountManifest(
                        accountPeerId: accountPeerId,
                        payloads: descriptors
                    )
                ]
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            try encoder.encode(manifest).write(
                to: workURL.appendingPathComponent("manifest.json"),
                options: .atomic
            )
            try? FileManager.default.removeItem(at: outputURL)
            guard SSZipArchive.createZipFile(
                atPath: outputURL.path,
                withContentsOfDirectory: workURL.path
            ) else {
                throw CocoaError(.fileWriteUnknown)
            }

            Queue.mainQueue().async {
                let presentationData = context.sharedContext.currentPresentationData.with { $0 }
                let picker = legacyICloudFilePicker(
                    theme: presentationData.theme,
                    mode: .export,
                    url: outputURL,
                    documentTypes: [],
                    dismissed: {
                        try? FileManager.default.removeItem(at: workURL)
                        try? FileManager.default.removeItem(at: outputURL)
                    },
                    completion: { _ in
                        try? FileManager.default.removeItem(at: workURL)
                        try? FileManager.default.removeItem(at: outputURL)
                    }
                )
                controller.present(picker, in: .window(.root), with: nil)
            }
        } catch {
            try? FileManager.default.removeItem(at: workURL)
            try? FileManager.default.removeItem(at: outputURL)
            customPresentArchiveExportError(
                context: context,
                controller: controller,
                text: String(describing: error)
            )
        }
    }
}

private final class CustomRuntimeRetentionStore: CustomRetentionConfigurationStore {
    func configuration(accountPeerId: Int64) throws -> CustomRetentionConfiguration {
        return CustomRetentionRuntime.configuration(accountPeerId: accountPeerId)
    }

    func replace(_ configuration: CustomRetentionConfiguration) throws {
        try CustomRetentionRuntime.save(configuration)
    }
}

private final class CustomUserDefaultsSnapshotStore: CustomSettingsSnapshotStore {
    func snapshot(accountPeerId: Int64) throws -> CustomSettingsSnapshot {
        return customSettingsSnapshot(accountPeerId: accountPeerId)
    }

    func replace(_ snapshot: CustomSettingsSnapshot) throws {
        // Replacement is exact so a failed transaction can restore absence as
        // well as values; otherwise newly introduced keys would leak past rollback.
        for key in customPortableBooleanKeys + customPortableStringKeys + customPortableIntegerKeys {
            let scoped = "custom.account.\(snapshot.accountPeerId).setting.\(key)"
            UserDefaults.standard.removeObject(forKey: scoped)
        }
        for (key, value) in snapshot.toggles {
            UserDefaults.standard.set(value, forKey: "custom.account.\(snapshot.accountPeerId).setting.\(key)")
        }
        for (key, value) in snapshot.stringValues {
            UserDefaults.standard.set(value, forKey: "custom.account.\(snapshot.accountPeerId).setting.\(key)")
        }
        for (key, value) in snapshot.integerValues {
            UserDefaults.standard.set(value, forKey: "custom.account.\(snapshot.accountPeerId).setting.\(key)")
        }
    }
}

private func customProjectImportedSettingsToActiveDefaults(_ snapshot: CustomSettingsSnapshot) {
    defer {
        CustomHotSettings.invalidate()
        CustomActivityCustomRuntime.invalidate()
        CustomBlockedReactionPolicy.notifySettingsChanged()
        CustomGlassStyle.reloadFromDefaults()
        Queue.mainQueue().async {
            NotificationCenter.default.post(name: Notification.Name("CustomRamOverlayPreferenceChanged"), object: nil)
        }
    }
    let defaults = UserDefaults.standard
    for (key, value) in snapshot.toggles {
        defaults.set(value, forKey: key)
    }
    for (key, value) in snapshot.stringValues {
        defaults.set(value, forKey: key)
    }
    for (key, value) in snapshot.integerValues {
        defaults.set(value, forKey: key)
    }

    // Archive v2 originally used Custom-prefixed portable names while a few
    // Project both spellings for the three synchronous side-effect settings.
    let legacyRuntimeKeys: [String: String] = [
        "custom.InvisibleMode.ScheduledSend": "Custom.InvisibleMode.ScheduledSend",
        "custom.ProtectedContent.Enabled": "Custom.ProtectedContent.Enabled",
        "custom.ProtectedContent.OneTimeSave": "Custom.ProtectedContent.OneTimeSave",
    ]
    for (portableKey, legacyKey) in legacyRuntimeKeys {
        if let value = snapshot.toggles[portableKey] {
            defaults.set(value, forKey: legacyKey)
            if legacyKey == "Custom.InvisibleMode.ScheduledSend" {
                (UserDefaults(suiteName: "group.ph.telegra.Telegraph") ?? defaults).set(value, forKey: legacyKey)
            }
        }
    }
}

private func customPresentArchiveImportError(
    context: AccountContext,
    controller: ViewController,
    presentationData: PresentationData,
    text: String
) {
    Queue.mainQueue().async {
        let alert = textAlertController(
            context: context,
            title: presentationData.strings.custom.importArchive,
            text: text,
            actions: [
                TextAlertAction(
                    type: .defaultAction,
                    title: presentationData.strings.Common_OK,
                    action: {}
                )
            ]
        )
        controller.present(alert, in: .window(.root), with: nil)
    }
}

public func customPresentArchiveImport(
    context: AccountContext,
    controller: ViewController
) {
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    let picker = legacyICloudFilePicker(
        theme: presentationData.theme,
        mode: .import,
        documentTypes: ["public.zip-archive", "public.data"],
        completion: { urls in
            guard let sourceURL = urls.first else { return }
            let didAccess = sourceURL.startAccessingSecurityScopedResource()

            // ZIP enumeration/unzip, payload reads and JSON validation are all
            // potentially unbounded file I/O. Never execute them in the file
            // picker/UI callback.
            Queue.concurrentDefaultQueue().async {
                defer {
                    if didAccess {
                        sourceURL.stopAccessingSecurityScopedResource()
                    }
                }
                let workURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("custom-import-\(UUID().uuidString)", isDirectory: true)
                defer { try? FileManager.default.removeItem(at: workURL) }

                do {
                    try FileManager.default.createDirectory(at: workURL, withIntermediateDirectories: true)
                    guard let entries = SSZipArchive.getEntriesForFile(atPath: sourceURL.path),
                          entries.count <= CustomArchiveV2.maximumPayloadCount + 1 else {
                        throw CocoaError(.fileReadCorruptFile)
                    }
                    for entry in entries {
                        let normalizedPath = entry.path.hasSuffix("/")
                            ? String(entry.path.dropLast())
                            : entry.path
                        if !normalizedPath.isEmpty {
                            try CustomArchiveV2.validateRelativePath(normalizedPath)
                        }
                    }
                    guard SSZipArchive.unzipFile(atPath: sourceURL.path, toDestination: workURL.path) else {
                        throw CocoaError(.fileReadCorruptFile)
                    }

                    let decoder = JSONDecoder()
                    let manifest = try decoder.decode(
                        CustomArchiveManifestV2.self,
                        from: Data(contentsOf: workURL.appendingPathComponent("manifest.json"))
                    )
                    let accountPeerId = context.account.peerId.toInt64()
                    guard let account = manifest.accounts.first(where: { $0.accountPeerId == accountPeerId }) else {
                        throw CustomArchiveValidationError.unavailableAccount(accountPeerId)
                    }

                    var payloads: [String: Data] = [:]
                    for descriptor in account.payloads {
                        payloads[descriptor.relativePath] = try Data(
                            contentsOf: workURL.appendingPathComponent(descriptor.relativePath)
                        )
                    }
                    try CustomArchiveV2.validateExtractedPayloads(
                        manifest: CustomArchiveManifestV2(
                            createdAtMs: manifest.createdAtMs,
                            accounts: [account]
                        ),
                        payloads: payloads
                    )

                    let base = "accounts/\(accountPeerId)"
                    guard let settingsData = payloads["\(base)/settings.json"],
                          let retentionData = payloads["\(base)/retention.json"],
                          let eventsData = payloads["\(base)/events.json"] else {
                        throw CustomArchiveValidationError.missingPayload(base)
                    }
                    let settings = try decoder.decode(CustomSettingsSnapshot.self, from: settingsData)
                    let retention = try decoder.decode(CustomRetentionConfiguration.self, from: retentionData)
                    let events = try decoder.decode([CustomCanonicalEvent].self, from: eventsData)

                    Queue.mainQueue().async {
                        let strings = presentationData.strings.custom
                        let alert = textAlertController(
                            context: context,
                            title: strings.importArchive,
                            text: strings.importSettingsConfirmation(accountPeerId),
                            actions: [
                                TextAlertAction(
                                    type: .genericAction,
                                    title: presentationData.strings.Common_Cancel,
                                    action: {}
                                ),
                                TextAlertAction(
                                    type: .defaultAction,
                                    title: strings.importSettings,
                                    action: {
                                        // ArchiveTransaction loads/merges and may atomically
                                        // rewrite the complete canonical account store. Keep
                                        // that transaction and its rollback away from UI.
                                        Queue.concurrentDefaultQueue().async {
                                            do {
                                                let eventStore = CustomJSONLEventStore(
                                                    rootURL: customCoreRootURL()
                                                )
                                                let settingsStore = CustomUserDefaultsSnapshotStore()
                                                try CustomArchiveTransaction.apply(
                                                    selectedAccountPeerIds: [accountPeerId],
                                                    availableAccountPeerIds: [context.account.peerId.toInt64()],
                                                    incomingEvents: [accountPeerId: events],
                                                    incomingSettings: [accountPeerId: settings],
                                                    confirmSettingsChanges: true,
                                                    eventStore: eventStore,
                                                    settingsStore: settingsStore
                                                )
                                                try CustomRetentionRuntime.save(retention)
                                                customProjectImportedSettingsToActiveDefaults(settings)
                                                Queue.mainQueue().async {
                                                    customNotifySettingsImported(accountPeerId: accountPeerId)
                                                }
                                            } catch {
                                                customPresentArchiveImportError(
                                                    context: context,
                                                    controller: controller,
                                                    presentationData: presentationData,
                                                    text: String(describing: error)
                                                )
                                            }
                                        }
                                    }
                                ),
                            ]
                        )
                        controller.present(alert, in: .window(.root), with: nil)
                    }
                } catch {
                    customPresentArchiveImportError(
                        context: context,
                        controller: controller,
                        presentationData: presentationData,
                        text: String(describing: error)
                    )
                }
            }
        }
    )
    controller.present(picker, in: .window(.root), with: nil)
}

private func customPresentArchiveImportPicker(
    context: AccountContext,
    controller: ViewController,
    availableAccountPeerIds: Set<Int64>
) {
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    let picker = legacyICloudFilePicker(
        theme: presentationData.theme,
        mode: .import,
        documentTypes: ["public.zip-archive", "public.data"],
        completion: { urls in
            guard let sourceURL = urls.first else { return }
            let didAccess = sourceURL.startAccessingSecurityScopedResource()
            defer { if didAccess { sourceURL.stopAccessingSecurityScopedResource() } }
            let workURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("custom-import-\(UUID().uuidString)", isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: workURL, withIntermediateDirectories: true)
                guard let entries = SSZipArchive.getEntriesForFile(atPath: sourceURL.path),
                      entries.count <= CustomArchiveV2.maximumPayloadCount + 1 else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                for entry in entries {
                    let normalizedPath = entry.path.hasSuffix("/")
                        ? String(entry.path.dropLast())
                        : entry.path
                    if !normalizedPath.isEmpty {
                        try CustomArchiveV2.validateRelativePath(normalizedPath)
                    }
                }
                guard SSZipArchive.unzipFile(atPath: sourceURL.path, toDestination: workURL.path) else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                let decoder = JSONDecoder()
                let manifest = try decoder.decode(
                    CustomArchiveManifestV2.self,
                    from: Data(contentsOf: workURL.appendingPathComponent("manifest.json"))
                )
                var payloads: [String: Data] = [:]
                for descriptor in manifest.accounts.flatMap(\.payloads) {
                    payloads[descriptor.relativePath] = try Data(contentsOf: workURL.appendingPathComponent(descriptor.relativePath))
                }
                try CustomArchiveV2.validateExtractedPayloads(manifest: manifest, payloads: payloads)

                let matchingAccounts = manifest.accounts.filter { availableAccountPeerIds.contains($0.accountPeerId) }
                guard !matchingAccounts.isEmpty else {
                    throw CustomArchiveValidationError.unavailableAccount(manifest.accounts.first?.accountPeerId ?? 0)
                }
                let selectedAccountPeerIds = Set(matchingAccounts.map(\.accountPeerId))
                let disconnected = manifest.accounts.map(\.accountPeerId).filter { !availableAccountPeerIds.contains($0) }.sorted()
                var incomingSettings: [Int64: CustomSettingsSnapshot] = [:]
                var incomingRetention: [Int64: CustomRetentionConfiguration] = [:]
                var incomingEvents: [Int64: [CustomCanonicalEvent]] = [:]
                for account in matchingAccounts {
                    let accountPeerId = account.accountPeerId
                    let base = "accounts/\(accountPeerId)"
                    guard let settingsData = payloads["\(base)/settings.json"],
                          let retentionData = payloads["\(base)/retention.json"],
                          let eventsData = payloads["\(base)/events.json"] else {
                        throw CustomArchiveValidationError.missingPayload(base)
                    }
                    let settings = try decoder.decode(CustomSettingsSnapshot.self, from: settingsData)
                    let retention = try decoder.decode(CustomRetentionConfiguration.self, from: retentionData)
                    let events = try decoder.decode([CustomCanonicalEvent].self, from: eventsData)
                    guard settings.accountPeerId == accountPeerId, retention.accountPeerId == accountPeerId,
                          events.allSatisfy({ $0.accountPeerId == accountPeerId }) else {
                        throw CustomArchiveValidationError.unavailableAccount(accountPeerId)
                    }
                    incomingSettings[accountPeerId] = settings
                    incomingRetention[accountPeerId] = retention
                    incomingEvents[accountPeerId] = events
                }
                let strings = presentationData.strings.custom
                let connectedLines = selectedAccountPeerIds.sorted().map { "✓ Telegram ID \($0)" }
                let disconnectedSuffix = strings.languageCode == "ru" ? "не подключён — пропущен" : "not connected — skipped"
                let disconnectedLines = disconnected.map { "— Telegram ID \($0) (\(disconnectedSuffix))" }
                let importPreview = (connectedLines + disconnectedLines).joined(separator: "\\n")
                let alert = textAlertController(
                    context: context,
                    title: strings.importArchive,
                    text: importPreview,
                    actions: [
                        TextAlertAction(type: .genericAction, title: presentationData.strings.Common_Cancel, action: {}),
                        TextAlertAction(type: .defaultAction, title: strings.importSettings, action: {
                            let eventStore = CustomJSONLEventStore(rootURL: customCoreRootURL())
                            let settingsStore = CustomUserDefaultsSnapshotStore()
                            let retentionStore = CustomRuntimeRetentionStore()
                            do {
                                try CustomArchiveTransaction.apply(
                                    selectedAccountPeerIds: selectedAccountPeerIds,
                                    availableAccountPeerIds: availableAccountPeerIds,
                                    incomingEvents: incomingEvents,
                                    incomingSettings: incomingSettings,
                                    confirmSettingsChanges: true,
                                    eventStore: eventStore,
                                    settingsStore: settingsStore,
                                    incomingRetention: incomingRetention,
                                    retentionStore: retentionStore
                                )
                                let result = textAlertController(
                                    context: context,
                                    title: strings.importArchive,
                                    text: strings.languageCode == "ru" ? "Импорт завершён." : "Import completed.",
                                    actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})]
                                )
                                controller.present(result, in: .window(.root), with: nil)
                            } catch {
                                let result = textAlertController(
                                    context: context,
                                    title: strings.importArchive,
                                    text: String(describing: error),
                                    actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})]
                                )
                                controller.present(result, in: .window(.root), with: nil)
                            }
                        }),
                    ]
                )
                controller.present(alert, in: .window(.root), with: nil)
            } catch {
                let alert = textAlertController(
                    context: context,
                    title: presentationData.strings.custom.importArchive,
                    text: String(describing: error),
                    actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})]
                )
                controller.present(alert, in: .window(.root), with: nil)
            }
            try? FileManager.default.removeItem(at: workURL)
        }
    )
    controller.present(picker, in: .window(.root), with: nil)
}
