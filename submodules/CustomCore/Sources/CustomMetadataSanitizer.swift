import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
#if canImport(Compression)
import Compression
#endif

// Custom outbound metadata sanitization ("Extras" settings tab).
//
// Hooked into multipartUpload for `.resource` sources: any bytes that leave
// the app pass through customSanitizeUploadData first. The sanitizer
// rewrites files without metadata-bearing structures and never blocks a
// send: if a file cannot be parsed, the original bytes are returned.

public struct CustomSanitizeReport: Equatable {
    public var format: String
    public var originalSize: Int
    public var outputSize: Int
    public var changed: Bool

    public init(format: String, originalSize: Int, outputSize: Int, changed: Bool) {
        self.format = format
        self.originalSize = originalSize
        self.outputSize = outputSize
        self.changed = changed
    }
}

public enum CustomSanitizeError: Error {
    case notSanitizable
}

private enum CustomSanitizeFormat: String {
    case jpeg
    case png
    case heic
    case mp4
    case pdf
    case officeZip
}

private func customSanitizeDetectFormat(_ data: Data) -> CustomSanitizeFormat? {
    guard data.count > 12 else {
        return nil
    }
    let bytes = [UInt8](data.prefix(16))
    // JPEG: FF D8 FF
    if bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF {
        return .jpeg
    }
    // PNG signature
    if bytes.elementsEqual([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) {
        return .png
    }
    // ISO-BMFF container (HEIC/HEIF/AVIF) or plain MP4/MOV: check ftyp brand.
    if data.count > 12 {
        let brand = String(bytes: bytes[8 ..< 12], encoding: .ascii) ?? ""
        if brand == "ftyp" {
            let major = String(bytes: bytes[4 ..< 8], encoding: .ascii) ?? ""
            switch major {
            case "heic", "heix", "hevc", "hevx", "mif1", "msf1", "avif":
                return .heic
            case "isom", "iso2", "mp41", "mp42", "mp4v", "avc1", "qt  ":
                return .mp4
            default:
                return nil
            }
        }
    }
    // PDF
    if data.starts(with: [0x25, 0x50, 0x44, 0x46]) { // %PDF
        return .pdf
    }
    // ZIP-based office documents (and plain zip archives are left alone)
    if bytes.elementsEqual([0x50, 0x4B, 0x03, 0x04]) {
        return .officeZip
    }
    return nil
}

private func customSanitizeIsOfficePath(_ path: String) -> Bool {
    let lowercased = path.lowercased()
    return lowercased.hasSuffix(".docx") || lowercased.hasSuffix(".xlsx") || lowercased.hasSuffix(".pptx")
        || lowercased.hasSuffix(".odt") || lowercased.hasSuffix(".ods") || lowercased.hasSuffix(".odp")
}

// MARK: - JPEG

// Copies JPEG segments, dropping APP1 (EXIF/XMP), APP13 (IPTC/Photoshop),
// APP2 (ICC profile) and COM markers. A minimal APP1 carrying only the
// EXIF orientation tag is re-emitted so images keep the correct rotation.
private func customSanitizeJPEG(_ data: Data) throws -> Data {
    let bytes = [UInt8](data)
    var offset = 2 // skip SOI
    var output: [UInt8] = [0xFF, 0xD8]
    var exifOrientation: Int? = nil

    func readU16(_ at: Int) -> Int? {
        guard at + 1 < bytes.count else { return nil }
        return (Int(bytes[at]) << 8) | Int(bytes[at + 1])
    }

    while offset + 4 <= bytes.count {
        guard bytes[offset] == 0xFF else {
            throw CustomSanitizeError.notSanitizable
        }
        let marker = bytes[offset + 1]
        if marker == 0xFF {
            offset += 1
            continue
        }
        // Standalone markers without payload
        if marker == 0xD8 || marker == 0x01 || (0xD0 ... 0xD7).contains(marker) {
            offset += 2
            continue
        }
        if marker == 0xD9 { // EOI
            output.append(contentsOf: [0xFF, 0xD9])
            return Data(output)
        }
        guard let length = readU16(offset + 2), length >= 2 else {
            throw CustomSanitizeError.notSanitizable
        }
        let segmentEnd = offset + 2 + length
        guard segmentEnd <= bytes.count else {
            throw CustomSanitizeError.notSanitizable
        }

        let isAPP1 = marker == 0xE1
        let isAPP13 = marker == 0xED
        let isAPP2 = marker == 0xE2
        let isCOM = marker == 0xFE

        if isAPP1 && exifOrientation == nil {
            // Detect EXIF (not XMP) and extract the orientation tag.
            let headerRange = (offset + 4) ..< min(offset + 10, segmentEnd)
            let header = String(bytes: bytes[headerRange], encoding: .ascii) ?? ""
            if header.hasPrefix("Exif") {
                exifOrientation = customSanitizeExifOrientation(bytes: bytes, segmentStart: offset + 4, segmentLength: length)
            }
        }

        if isAPP1 || isAPP13 || isAPP2 || isCOM {
            // Dropped, along with its payload.
            offset = segmentEnd
            continue
        }

        // Entropy-coded scan: copy through to EOI verbatim.
        if marker == 0xDA { // SOS
            output.append(contentsOf: [0xFF, marker])
            output.append(contentsOf: bytes[(offset + 2) ..< segmentEnd])
            var scan = segmentEnd
            while scan + 1 < bytes.count {
                if bytes[scan] == 0xFF && bytes[scan + 1] != 0x00 && !(0xD0 ... 0xD7).contains(bytes[scan + 1]) {
                    break
                }
                scan += 1
            }
            guard scan + 1 < bytes.count, bytes[scan + 1] == 0xD9 else {
                throw CustomSanitizeError.notSanitizable
            }
            output.append(contentsOf: bytes[segmentEnd ..< scan])
            output.append(contentsOf: [0xFF, 0xD9])
            return Data(output)
        }

        output.append(contentsOf: [0xFF, marker])
        output.append(contentsOf: bytes[(offset + 2) ..< segmentEnd])
        offset = segmentEnd
    }
    throw CustomSanitizeError.notSanitizable
}

private func customSanitizeExifOrientation(bytes: [UInt8], segmentStart: Int, segmentLength: Int) -> Int? {
    // TIFF header begins after "Exif\0\0" (6 bytes).
    let tiffStart = segmentStart + 6
    guard tiffStart + 8 <= segmentStart + segmentLength else { return nil }
    let bigEndian = bytes[tiffStart] == 0x4D && bytes[tiffStart + 1] == 0x4D
    let littleEndian = bytes[tiffStart] == 0x49 && bytes[tiffStart + 1] == 0x49
    guard bigEndian || littleEndian else { return nil }

    func u16(_ at: Int) -> Int {
        let a = tiffStart + at
        guard a + 1 < bytes.count else { return 0 }
        return bigEndian ? (Int(bytes[a]) << 8) | Int(bytes[a + 1]) : Int(bytes[a]) | (Int(bytes[a + 1]) << 8)
    }
    func u32(_ at: Int) -> Int {
        let a = tiffStart + at
        guard a + 3 < bytes.count else { return 0 }
        if bigEndian {
            return (Int(bytes[a]) << 24) | (Int(bytes[a + 1]) << 16) | (Int(bytes[a + 2]) << 8) | Int(bytes[a + 3])
        } else {
            return Int(bytes[a]) | (Int(bytes[a + 1]) << 8) | (Int(bytes[a + 2]) << 16) | (Int(bytes[a + 3]) << 24)
        }
    }

    let ifdOffset = u32(4)
    guard ifdOffset > 0, tiffStart + ifdOffset + 2 <= bytes.count else { return nil }
    let entryCount = u16(ifdOffset)
    for index in 0 ..< entryCount {
        let entry = ifdOffset + 2 + index * 12
        guard tiffStart + entry + 12 <= bytes.count else { return nil }
        if u16(entry) == 0x0112 { // Orientation
            let value = u16(entry + 8)
            if (1 ... 8).contains(value) {
                return value
            }
            return nil
        }
    }
    return nil
}

// Minimal valid EXIF APP1 carrying only the orientation tag.
private func customSanitizeExifAPP1(orientation: Int) -> Data {
    var tiff: [UInt8] = []
    tiff.append(contentsOf: [0x4D, 0x4D]) // MM (big endian)
    tiff.append(contentsOf: [0x00, 0x2A])
    tiff.append(contentsOf: [0x00, 0x00, 0x00, 0x08]) // IFD at 8
    tiff.append(contentsOf: [0x00, 0x01]) // one entry
    tiff.append(contentsOf: [0x01, 0x12]) // Orientation
    tiff.append(contentsOf: [0x00, 0x03]) // SHORT
    tiff.append(contentsOf: [0x00, 0x00, 0x00, 0x01]) // count 1
    tiff.append(contentsOf: [UInt8((orientation >> 8) & 0xFF), UInt8(orientation & 0xFF), 0x00, 0x00])
    tiff.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // next IFD

    var payload: [UInt8] = Array("Exif\0\0".utf8)
    payload.append(contentsOf: tiff)

    var output: [UInt8] = [0xFF, 0xE1]
    output.append(contentsOf: [UInt8((payload.count + 2) >> 8) & 0xFF, UInt8((payload.count + 2) & 0xFF)])
    output.append(contentsOf: payload)
    return Data(output)
}

// MARK: - PNG

private func customSanitizePNG(_ data: Data) throws -> Data {
    let bytes = [UInt8](data)
    var output: [UInt8] = []
    output.append(contentsOf: bytes[0 ..< 8]) // signature

    func readU32(_ at: Int) -> Int? {
        guard at + 3 < bytes.count else { return nil }
        return (Int(bytes[at]) << 24) | (Int(bytes[at + 1]) << 16) | (Int(bytes[at + 2]) << 8) | Int(bytes[at + 3])
    }

    var offset = 8
    var crcTable = [UInt32](repeating: 0, count: 256)
    for n in 0 ..< 256 {
        var c = UInt32(n)
        for _ in 0 ..< 8 {
            c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1
        }
        crcTable[n] = c
    }
    func crc32(_ chunk: [UInt8]) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in chunk {
            crc = crcTable[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFFFFFF
    }

    while offset + 8 <= bytes.count {
        guard let length = readU32(offset), length >= 0 else {
            throw CustomSanitizeError.notSanitizable
        }
        let typeStart = offset + 4
        let dataStart = typeStart + 4
        let chunkEnd = dataStart + length
        let crcEnd = chunkEnd + 4
        guard crcEnd <= bytes.count else {
            throw CustomSanitizeError.notSanitizable
        }
        let type = String(bytes: bytes[typeStart ..< dataStart], encoding: .ascii) ?? ""

        if type == "eXIf" || type == "tEXt" || type == "iTXt" || type == "zTXt" {
            offset = crcEnd
            continue
        }

        output.append(contentsOf: bytes[offset ..< chunkEnd])
        if type != "IEND" {
            let chunk = Array(bytes[typeStart ..< chunkEnd])
            let crc = crc32(chunk)
            output.append(contentsOf: [
                UInt8((crc >> 24) & 0xFF), UInt8((crc >> 16) & 0xFF), UInt8((crc >> 8) & 0xFF), UInt8(crc & 0xFF)
            ])
        }
        if type == "IEND" {
            return Data(output)
        }
        offset = crcEnd
    }
    throw CustomSanitizeError.notSanitizable
}

// MARK: - ISO-BMFF (HEIC / MP4 / MOV)

// Rebuilds the top-level box structure dropping metadata boxes: 'udta',
// 'uuid', 'meud' and free/skip padding. A top-level 'meta' box is dropped
// only when it carries iTunes-style metadata (its handler type is 'mdir'):
// in HEIF containers the 'meta' box is a required structural box and must
// stay. Sample tables and media tracks are copied verbatim.
private func customSanitizeISOBMFF(_ data: Data) throws -> Data {
    let bytes = [UInt8](data)
    var output: [UInt8] = []

    func boxType(_ at: Int) -> String? {
        guard at + 8 <= bytes.count else { return nil }
        return String(bytes: bytes[(at + 4) ..< (at + 8)], encoding: .ascii)
    }

    var offset = 0
    while offset + 8 <= bytes.count {
        guard let size32 = readU32BE(bytes, offset) else {
            break
        }
        var headerSize = 8
        var boxSize = Int(size32)
        if size32 == 1 {
            guard let size64 = readU64BE(bytes, offset + 8) else {
                break
            }
            headerSize = 16
            boxSize = size64
        } else if size32 == 0 {
            boxSize = bytes.count - offset
        }
        guard boxSize >= headerSize, offset + boxSize <= bytes.count else {
            break
        }
        let type = boxType(offset) ?? ""
        var drop = (type == "udta" || type == "uuid" || type == "meud" || type == "free" || type == "skip")
        if type == "meta" {
            // Drop only iTunes-style metadata boxes (handler 'mdir'); a
            // structural HEIF 'meta' box does not contain that marker.
            let payloadStart = offset + headerSize
            drop = customSanitizeContainsASCII(bytes, payloadStart ..< (offset + boxSize), "mdir")
        }
        if !drop {
            output.append(contentsOf: bytes[offset ..< (offset + boxSize)])
        }
        offset += boxSize
    }
    guard offset == bytes.count, output.count > 0 else {
        throw CustomSanitizeError.notSanitizable
    }
    return Data(output)
}

private func customSanitizeContainsASCII(_ bytes: [UInt8], _ range: Range<Int>, _ needle: String) -> Bool {
    let pattern = Array(needle.utf8)
    guard !pattern.isEmpty, range.lowerBound >= 0, range.upperBound <= bytes.count else {
        return false
    }
    var index = range.lowerBound
    let upperBound = range.upperBound - pattern.count
    while index <= upperBound {
        if Array(bytes[index ..< (index + pattern.count)]) == pattern {
            return true
        }
        index += 1
    }
    return false
}

private func readU32BE(_ bytes: [UInt8], _ at: Int) -> UInt32? {
    guard at + 3 < bytes.count else { return nil }
    return (UInt32(bytes[at]) << 24) | (UInt32(bytes[at + 1]) << 16) | (UInt32(bytes[at + 2]) << 8) | UInt32(bytes[at + 3])
}

private func readU64BE(_ bytes: [UInt8], _ at: Int) -> Int? {
    guard at + 7 < bytes.count else { return nil }
    var value: Int64 = 0
    for index in 0 ..< 8 {
        value = (value << 8) | Int64(bytes[at + index])
    }
    return Int(value)
}

// MARK: - PDF

// Re-renders the document pages into a fresh PDF context. Document-level
// metadata (/Info, XMP) does not survive the round trip.
private func customSanitizePDF(_ data: Data) throws -> Data {
    #if canImport(CoreGraphics)
    guard let provider = CGDataProvider(data: data as CFData),
        let document = CGPDFDocument(provider) else {
        throw CustomSanitizeError.notSanitizable
    }
    guard document.numberOfPages > 0 else {
        throw CustomSanitizeError.notSanitizable
    }

    let output = NSMutableData()
    guard let consumer = CGDataConsumer(data: output as CFMutableData) else {
        throw CustomSanitizeError.notSanitizable
    }
    var box = CGRect(x: 0, y: 0, width: 612, height: 792)
    if let page = document.page(at: 1) {
        box = page.getBoxRect(.mediaBox)
    }
    guard let context = CGContext(consumer: consumer, mediaBox: &box, nil) else {
        throw CustomSanitizeError.notSanitizable
    }

    for pageNumber in 1 ... document.numberOfPages {
        guard let page = document.page(at: pageNumber) else {
            continue
        }
        let pageBox = page.getBoxRect(.mediaBox)
        context.beginPage(mediaBox: &box)
        context.saveGState()
        context.translateBy(x: (box.width - pageBox.width) / 2.0, y: (box.height - pageBox.height) / 2.0)
        context.drawPDFPage(page)
        context.restoreGState()
    }
    context.closePDF()
    guard output.length > 0 else {
        throw CustomSanitizeError.notSanitizable
    }
    return output as Data
    #else
    throw CustomSanitizeError.notSanitizable
    #endif
}

// MARK: - Office zip

private func customSanitizeOfficeZip(_ data: Data) throws -> Data {
    // Stored (uncompressed) rewrite of a zip archive, dropping the
    // docProps/* entries and per-entry timestamps. Content parts are copied
    // byte-for-byte with method 0 (stored), which is valid per spec.
    guard let archive = customSanitizeParseZip(data) else {
        throw CustomSanitizeError.notSanitizable
    }
    if archive.entries.contains(where: { $0.isEncrypted }) {
        throw CustomSanitizeError.notSanitizable
    }
    let keptEntries = archive.entries.filter { !$0.path.hasPrefix("docProps/") }
    var output: [UInt8] = []
    var centralDirectory: [UInt8] = []
    var localOffset = 0

    for entry in keptEntries {
        let payload: Data
        if entry.isStored {
            payload = entry.payload
        } else {
            // ZIP method 8 is raw deflate; Apple's Compression framework
            // implements exactly that as COMPRESSION_ZLIB.
            guard let inflated = customSanitizeInflate(entry.payload) else {
                throw CustomSanitizeError.notSanitizable
            }
            payload = inflated
        }
        var local: [UInt8] = []
        local.append(contentsOf: [0x50, 0x4B, 0x03, 0x04])
        local.append(contentsOf: [0x14, 0x00]) // version
        local.append(contentsOf: [0x00, 0x00]) // flags
        local.append(contentsOf: [0x00, 0x00]) // method: stored
        local.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // time+date
        let crc32 = customSanitizeCrc32(payload)
        local.append(contentsOf: customSanitizeLe32(UInt32(crc32)))
        local.append(contentsOf: customSanitizeLe32(UInt32(payload.count)))
        local.append(contentsOf: customSanitizeLe32(UInt32(payload.count)))
        local.append(contentsOf: customSanitizeLe16(UInt16(entry.path.utf8.count)))
        local.append(contentsOf: customSanitizeLe16(0))
        local.append(contentsOf: Array(entry.path.utf8))

        var central: [UInt8] = []
        central.append(contentsOf: [0x50, 0x4B, 0x01, 0x02])
        central.append(contentsOf: [0x14, 0x00])
        central.append(contentsOf: [0x14, 0x00])
        central.append(contentsOf: [0x00, 0x00])
        central.append(contentsOf: [0x00, 0x00])
        central.append(contentsOf: [0x00, 0x00, 0x00, 0x00])
        central.append(contentsOf: customSanitizeLe32(UInt32(crc32)))
        central.append(contentsOf: customSanitizeLe32(UInt32(payload.count)))
        central.append(contentsOf: customSanitizeLe32(UInt32(payload.count)))
        central.append(contentsOf: customSanitizeLe16(UInt16(entry.path.utf8.count)))
        central.append(contentsOf: customSanitizeLe16(0))
        central.append(contentsOf: customSanitizeLe16(0))
        central.append(contentsOf: customSanitizeLe16(0))
        central.append(contentsOf: customSanitizeLe16(0))
        central.append(contentsOf: customSanitizeLe32(0))
        central.append(contentsOf: customSanitizeLe32(UInt32(localOffset)))
        central.append(contentsOf: Array(entry.path.utf8))

        output.append(contentsOf: local)
        output.append(contentsOf: payload)
        centralDirectory.append(contentsOf: central)
        localOffset = output.count
    }

    let centralOffset = output.count
    output.append(contentsOf: centralDirectory)
    let centralSize = output.count - centralOffset

    var eocd: [UInt8] = []
    eocd.append(contentsOf: [0x50, 0x4B, 0x05, 0x06])
    eocd.append(contentsOf: [0x00, 0x00])
    eocd.append(contentsOf: [0x00, 0x00])
    eocd.append(contentsOf: customSanitizeLe16(UInt16(keptEntries.count)))
    eocd.append(contentsOf: customSanitizeLe16(UInt16(keptEntries.count)))
    eocd.append(contentsOf: customSanitizeLe32(UInt32(centralSize)))
    eocd.append(contentsOf: customSanitizeLe32(UInt32(centralOffset)))
    eocd.append(contentsOf: customSanitizeLe16(0))
    output.append(contentsOf: eocd)
    return Data(output)
}

private struct CustomZipEntry {
    var path: String
    var payload: Data
    var isStored: Bool
    var isEncrypted: Bool
}

#if canImport(Compression)
private func customSanitizeInflate(_ data: Data) -> Data? {
    guard !data.isEmpty else { return nil }
    let source = [UInt8](data)
    var destinationSize = source.count * 4
    for _ in 0 ..< 3 {
        var destination = [UInt8](repeating: 0, count: destinationSize)
        let written = destination.withUnsafeMutableBytes { destRaw -> Int in
            source.withUnsafeBytes { srcRaw -> Int in
                guard let destBase = destRaw.baseAddress?.assumingMemoryBound(to: UInt8.self),
                    let srcBase = srcRaw.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                    return 0
                }
                return compression_decode_buffer(
                    destBase, destinationSize,
                    srcBase, source.count,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
        }
        if written > 0 && written < destinationSize {
            return Data(destination[0 ..< written])
        }
        if written == destinationSize {
            // Output may be truncated; retry with a larger buffer.
            destinationSize *= 4
            continue
        }
        return nil
    }
    return nil
}
#else
private func customSanitizeInflate(_ data: Data) -> Data? {
    return nil
}
#endif

private func customSanitizeParseZip(_ data: Data) -> (entries: [CustomZipEntry], count: Int)? {
    let bytes = [UInt8](data)
    // Locate End Of Central Directory.
    var eocdIndex: Int? = nil
    if bytes.count >= 22 {
        var index = bytes.count - 22
        while index >= 0 && index > bytes.count - 22 - 65536 {
            if bytes[index] == 0x50 && bytes[index + 1] == 0x4B && bytes[index + 2] == 0x05 && bytes[index + 3] == 0x06 {
                eocdIndex = index
                break
            }
            index -= 1
        }
    }
    guard let eocd = eocdIndex else {
        return nil
    }
    func le16(_ at: Int) -> Int {
        return Int(bytes[at]) | (Int(bytes[at + 1]) << 8)
    }
    func le32(_ at: Int) -> Int {
        return Int(bytes[at]) | (Int(bytes[at + 1]) << 8) | (Int(bytes[at + 2]) << 16) | (Int(bytes[at + 3]) << 24)
    }
    let entryCount = le16(eocd + 10)
    var centralOffset = le32(eocd + 16)

    var entries: [CustomZipEntry] = []
    for _ in 0 ..< entryCount {
        guard centralOffset + 46 <= bytes.count,
            bytes[centralOffset] == 0x50 && bytes[centralOffset + 1] == 0x4B && bytes[centralOffset + 2] == 0x01 && bytes[centralOffset + 3] == 0x02 else {
            break
        }
        let flags = le16(centralOffset + 8)
        let method = le16(centralOffset + 10)
        let compressedSize = le32(centralOffset + 20)
        let nameLength = le16(centralOffset + 28)
        let extraLength = le16(centralOffset + 30)
        let commentLength = le16(centralOffset + 32)
        let localOffset = le32(centralOffset + 42)
        let nameStart = centralOffset + 46
        guard nameStart + nameLength <= bytes.count else {
            break
        }
        let path = String(bytes: bytes[nameStart ..< (nameStart + nameLength)], encoding: .utf8) ?? ""
        guard localOffset + 30 <= bytes.count else {
            break
        }
        let lNameLength = le16(localOffset + 26)
        let lExtraLength = le16(localOffset + 28)
        let payloadStart = localOffset + 30 + lNameLength + lExtraLength
        guard payloadStart + compressedSize <= bytes.count else {
            break
        }
        let payload = Data(bytes[payloadStart ..< (payloadStart + compressedSize)])
        entries.append(CustomZipEntry(path: path, payload: payload, isStored: method == 0, isEncrypted: flags & 0x1 != 0))
        centralOffset = nameStart + nameLength + extraLength + commentLength
    }
    return (entries, entries.count)
}

private func customSanitizeLe16(_ value: UInt16) -> [UInt8] {
    return [UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF)]
}

private func customSanitizeLe32(_ value: UInt32) -> [UInt8] {
    return [UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF), UInt8((value >> 16) & 0xFF), UInt8((value >> 24) & 0xFF)]
}

private func customSanitizeCrc32(_ data: Data) -> UInt32 {
    var table = [UInt32](repeating: 0, count: 256)
    for n in 0 ..< 256 {
        var c = UInt32(n)
        for _ in 0 ..< 8 {
            c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1
        }
        table[n] = c
    }
    var crc: UInt32 = 0xFFFFFFFF
    for byte in data {
        crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
    }
    return crc ^ 0xFFFFFFFF
}

// MARK: - Entry point

public func customSanitizeUploadData(_ data: Data, fileNameHint: String?) -> (data: Data, report: CustomSanitizeReport?) {
    guard CustomExtrasSettings.metadataSanitizationEnabled else {
        return (data, nil)
    }
    guard !data.isEmpty, let format = customSanitizeDetectFormat(data) else {
        return (data, nil)
    }
    if format == .officeZip && !(fileNameHint.map(customSanitizeIsOfficePath) ?? false) {
        // Plain zip archives are left untouched.
        return (data, nil)
    }

    let originalSize = data.count
    do {
        let output: Data
        switch format {
        case .jpeg:
            output = try customSanitizeJPEG(data)
        case .png:
            output = try customSanitizePNG(data)
        case .heic, .mp4:
            output = try customSanitizeISOBMFF(data)
        case .pdf:
            output = try customSanitizePDF(data)
        case .officeZip:
            output = try customSanitizeOfficeZip(data)
        }
        let changed = output != data
        return (output, CustomSanitizeReport(
            format: format.rawValue,
            originalSize: originalSize,
            outputSize: output.count,
            changed: changed
        ))
    } catch {
        return (data, nil)
    }
}
