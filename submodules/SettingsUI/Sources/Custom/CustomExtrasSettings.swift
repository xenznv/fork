import Foundation

// "Extras" settings-tab switches used by the outbound metadata sanitizer.
// Stored in standard defaults so CustomCore can read them without any
// dependency on Postbox or the account layer.

public enum CustomExtrasSettings {
    private static let sanitizeKey = "custom.Extras.MetadataSanitization"
    private static let anonymizeNamesKey = "custom.Extras.AnonymizeFileNames"

    public static var metadataSanitizationEnabled: Bool {
        get {
            // Enabled unless explicitly disabled.
            if UserDefaults.standard.object(forKey: sanitizeKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: sanitizeKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: sanitizeKey)
        }
    }

    public static var anonymizeFileNamesEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: anonymizeNamesKey) == nil {
                return false
            }
            return UserDefaults.standard.bool(forKey: anonymizeNamesKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: anonymizeNamesKey)
        }
    }

    private static let genericNames: [String] = ["photo.jpg", "video.mp4", "document.pdf", "file"]

    /// Maps an attachment file name to a generic one when anonymization is
    /// enabled; keeps the extension so iOS preview still works.
    public static func anonymizedFileName(_ name: String?) -> String? {
        guard anonymizeFileNamesEnabled, let name else {
            return name
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return name
        }
        let lowercased = trimmed.lowercased()
        if lowercased.hasPrefix("photo") || lowercased.hasPrefix("img") {
            return "photo.jpg"
        }
        if lowercased.hasPrefix("video") || lowercased.hasPrefix("vid") {
            return "video.mp4"
        }
        if lowercased.hasSuffix(".pdf") {
            return "document.pdf"
        }
        if lowercased.hasSuffix(".png") {
            return "image.png"
        }
        if let dotIndex = trimmed.lastIndex(of: "."), dotIndex > trimmed.startIndex {
            return "file." + trimmed[trimmed.index(after: dotIndex)...]
        }
        return "file"
    }
}
