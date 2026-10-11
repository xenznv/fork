import Foundation
#if os(iOS)
import UIKit
#endif
import Postbox

// Turns media files downloaded from the archive API into real Telegram media
// objects, so messages restored from the archive show a photo or a playable
// video instead of bare text.
//
// The archive hands over plain files, not Telegram media, so everything a chat
// bubble needs is reconstructed here: the storage location the media pipeline
// reads from (LocalFileReferenceMediaResource), the dimensions a photo bubble
// lays out with, and the attributes that decide which bubble is used.

/// Directory holding archived media.
///
/// Application Support rather than Caches: these files are the only surviving
/// copy of media Telegram has already deleted, so the system must not purge them.
public func customArchiveMediaDirectory() -> URL {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    return base.appendingPathComponent("custom-archive-media", isDirectory: true)
}

/// Where one archived media file lives locally, mirroring the archive's naming.
public func customArchiveMediaLocalFile(
    chatId: Int64,
    messageId: Int32,
    mediaType: String?,
    relativePath: String
) -> URL {
    let pathExtension = (relativePath as NSString).pathExtension
    let type = (mediaType ?? "file").lowercased()
    let name = pathExtension.isEmpty
        ? "\(messageId)_\(type)"
        : "\(messageId)_\(type).\(pathExtension)"
    return customArchiveMediaDirectory()
        .appendingPathComponent("\(chatId)", isDirectory: true)
        .appendingPathComponent(name)
}

/// Builds the media object for one downloaded archive file.
///
/// Returns `nil` for media that cannot be represented (for example a photo whose
/// file turns out not to be readable as an image); the caller then keeps the
/// message text-only instead of failing the whole restore.
public func customArchiveMediaObject(
    mediaType: String?,
    relativePath: String,
    localFile: URL,
    byteSize: Int64?,
    emoji: String? = nil,
    setName: String? = nil
) -> Media? {
    let fileSize = byteSize ?? customArchiveFileSize(localFile)
    let type = (mediaType ?? "").lowercased()
    let resource = LocalFileReferenceMediaResource(
        localFilePath: localFile.path,
        randomId: Int64.random(in: Int64.min ... Int64.max),
        isUniquelyReferencedTemporaryFile: false,
        size: fileSize
    )

    if type == "photo", let dimensions = customArchiveImageDimensions(localFile) {
        return TelegramMediaImage(
            imageId: MediaId(
                namespace: Namespaces.Media.LocalImage,
                id: MediaId.Id.random(in: Int64.min ... Int64.max)
            ),
            representations: [
                TelegramMediaImageRepresentation(
                    dimensions: dimensions,
                    resource: resource,
                    progressiveSizes: [],
                    immediateThumbnailData: nil
                )
            ],
            immediateThumbnailData: nil,
            reference: nil,
            partialReference: nil,
            flags: []
        )
    }

    // Stickers are real stickers, not files: the .Sticker attribute makes
    // the bubble render without a filename and resends arrive as a sticker.
    // Emoji comes from the archive metadata (falls back to a smiley). The
    // set short name travels as the pack reference, so tapping the sticker
    // opens its set, exactly like a live sticker does.
    if type == "sticker" {
        let dimensions = customArchiveImageDimensions(localFile)
            ?? PixelDimensions(width: 512, height: 512)
        let packReference: StickerPackReference? = setName.flatMap { name in
            name.isEmpty ? nil : .name(name)
        }
        var attributes: [TelegramMediaFileAttribute] = [
            .ImageSize(size: dimensions),
            .Sticker(displayText: emoji ?? "🙂", packReference: packReference, maskData: nil)
        ]
        let ext = (relativePath as NSString).pathExtension.lowercased()
        var mimeType = "image/webp"
        if ext == "tgs" {
            mimeType = "application/x-tgsticker"
            attributes.append(.Animated)
        } else if ext == "webm" {
            mimeType = "video/webm"
            attributes.append(.Video(
                duration: 0.0,
                size: dimensions,
                flags: [],
                preloadSize: nil,
                coverTime: nil,
                videoCodec: nil
            ))
        }
        return TelegramMediaFile(
            fileId: MediaId(
                namespace: Namespaces.Media.LocalFile,
                id: MediaId.Id.random(in: Int64.min ... Int64.max)
            ),
            partialReference: nil,
            resource: resource,
            previewRepresentations: [],
            videoThumbnails: [],
            immediateThumbnailData: nil,
            mimeType: mimeType,
            size: fileSize,
            attributes: attributes,
            alternativeRepresentations: []
        )
    }

    var attributes: [TelegramMediaFileAttribute] = [
        .FileName(fileName: localFile.lastPathComponent)
    ]
    if type == "video" || type == "animation" || type == "video_note" {
        // Without video metadata the bubble falls back to a 16:9 preview; the
        // file itself plays from the local resource.
        let dimensions = PixelDimensions(width: 640, height: 360)
        var flags: TelegramMediaVideoFlags = []
        if type == "video_note" {
            flags.insert(.instantRoundVideo)
        }
        attributes.append(.ImageSize(size: dimensions))
        attributes.append(.Video(
            duration: 0.0,
            size: dimensions,
            flags: flags,
            preloadSize: nil,
            coverTime: nil,
            videoCodec: nil
        ))
        if type == "animation" {
            attributes.append(.Animated)
        }
    } else if type == "voice" || type == "audio" {
        attributes.append(.Audio(
            isVoice: type == "voice",
            duration: 0,
            title: nil,
            performer: nil,
            waveform: Data()
        ))
    } else if let dimensions = customArchiveImageDimensions(localFile) {
        attributes.append(.ImageSize(size: dimensions))
    }

    return TelegramMediaFile(
        fileId: MediaId(
            namespace: Namespaces.Media.LocalFile,
            id: MediaId.Id.random(in: Int64.min ... Int64.max)
        ),
        partialReference: nil,
        resource: resource,
        previewRepresentations: [],
        videoThumbnails: [],
        immediateThumbnailData: nil,
        mimeType: customArchiveMimeType(mediaType: type, path: relativePath),
        size: fileSize,
        attributes: attributes,
        alternativeRepresentations: []
    )
}

public func customArchiveFileSize(_ file: URL) -> Int64 {
    let attributes = try? FileManager.default.attributesOfItem(atPath: file.path)
    return (attributes?[.size] as? NSNumber)?.int64Value ?? 0
}

private func customArchiveImageDimensions(_ file: URL) -> PixelDimensions? {
#if os(iOS)
    guard let image = UIImage(contentsOfFile: file.path),
          image.size.width > 0.0,
          image.size.height > 0.0 else {
        return nil
    }
    let scale = image.scale
    return PixelDimensions(
        width: Int32((image.size.width * scale).rounded()),
        height: Int32((image.size.height * scale).rounded())
    )
#else
    return nil
#endif
}

private func customArchiveMimeType(mediaType: String, path: String) -> String {
    switch (path as NSString).pathExtension.lowercased() {
    case "jpg", "jpeg":
        return "image/jpeg"
    case "png":
        return "image/png"
    case "webp":
        return "image/webp"
    case "gif":
        return "image/gif"
    case "heic":
        return "image/heic"
    case "mp4", "mov", "m4v":
        return "video/mp4"
    case "ogg", "opus":
        return "audio/ogg"
    case "mp3":
        return "audio/mpeg"
    case "m4a":
        return "audio/mp4"
    case "pdf":
        return "application/pdf"
    default:
        break
    }
    switch mediaType {
    case "photo":
        return "image/jpeg"
    case "video", "animation", "video_note":
        return "video/mp4"
    case "voice":
        return "audio/ogg"
    case "audio":
        return "audio/mpeg"
    default:
        return "application/octet-stream"
    }
}
