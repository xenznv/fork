import Foundation
#if canImport(Darwin)
import Darwin
#endif

// Pending-crash file descriptor. Opened once at launch and kept open for the
// whole session so the signal handler only performs write() calls.
fileprivate var customCrashFileDescriptor: Int32 = -1
fileprivate var customBacktraceBuffer: UnsafeMutablePointer<UnsafeMutableRawPointer?>?

// Swift traps (fatalError / precondition / arithmetic overflow) surface as
// SIGTRAP; ObjC exceptions go through NSSetUncaughtExceptionHandler.
// The handler logs the backtrace to the pending-crash file and re-raises so
// the process still terminates the way it would have without the handler.
private func customSignalHandler(_ sig: Int32) {
    let fd = customCrashFileDescriptor
    if fd >= 0 {
        let headerText = "\n===CUSTOM-SIGNAL-\(sig)===\n"
        let headerData = headerText.data(using: .utf8) ?? Data()
        headerData.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            if let base = raw.baseAddress {
                _ = write(fd, base, raw.count)
            }
        }
        if let buffer = customBacktraceBuffer {
            let count = backtrace(buffer, 128)
            if count > 0 {
                backtrace_symbols_fd(buffer, count, fd)
            }
        }
    }
    signal(sig, SIG_DFL)
    raise(sig)
}

public final class CustomDebugConsole {
    public static let shared = CustomDebugConsole()

    private static let entriesKey = "custom.DebugConsole.Entries"
    private static let maxEntries = 500
    private static let maxMessageLength = 6000

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    private let lock = NSLock()

    private init() {}

    // MARK: - App-level logging

    public func log(_ message: String) {
        self.append(kind: "i", message: message)
    }

    /// Lightweight step markers written around high-risk flows (file sending,
    /// attachment menu, etc.). After a crash, the last breadcrumbs show how
    /// far execution got before the process died.
    public func breadcrumb(_ message: String) {
        self.append(kind: "b", message: message)
    }

    public func error(_ message: String) {
        self.append(kind: "e", message: message)
    }

    public func crashReport(_ message: String) {
        self.append(kind: "c", message: message)
    }

    // MARK: - Storage

    public func entries() -> [String] {
        self.lock.lock()
        defer { self.lock.unlock() }
        return UserDefaults.standard.stringArray(forKey: Self.entriesKey) ?? []
    }

    public func entriesText() -> String {
        return self.entries().joined(separator: "\n")
    }

    public func clear() {
        self.lock.lock()
        UserDefaults.standard.removeObject(forKey: Self.entriesKey)
        self.lock.unlock()
    }

    private func append(kind: String, message: String) {
        self.lock.lock()
        defer { self.lock.unlock() }

        let limited: String
        if message.count > Self.maxMessageLength {
            limited = String(message.prefix(Self.maxMessageLength)) + "…"
        } else {
            limited = message
        }
        let entry = "\(Self.timeFormatter.string(from: Date())) [\(kind)] \(limited)"

        var all = UserDefaults.standard.stringArray(forKey: Self.entriesKey) ?? []
        all.append(entry)
        if all.count > Self.maxEntries {
            all.removeFirst(all.count - Self.maxEntries)
        }
        UserDefaults.standard.set(all, forKey: Self.entriesKey)
    }

    // MARK: - Static shortcuts (breadcrumbs and UI call sites)

    public static func log(_ message: String) {
        shared.log(message)
    }

    public static func breadcrumb(_ message: String) {
        shared.breadcrumb(message)
    }

    public static func error(_ message: String) {
        shared.error(message)
    }

    public static func crashReport(_ message: String) {
        shared.crashReport(message)
    }

    public static func logText() -> String {
        return shared.entriesText()
    }

    public static func clearLog() {
        shared.clear()
    }

    public static func installCrashHandlersOnce() {
        shared.installCrashHandlers()
    }

    // MARK: - Crash capture

    public func installCrashHandlers() {
        // Import the report left behind by the previous session (if any).
        self.importPendingCrashFile()

        let path = Self.pendingCrashFilePath()
        customCrashFileDescriptor = open(path, O_WRONLY | O_CREAT | O_APPEND, 0o644)
        if customBacktraceBuffer == nil {
            let buffer = UnsafeMutablePointer<UnsafeMutableRawPointer?>.allocate(capacity: 128)
            for index in 0 ..< 128 {
                buffer[index] = nil
            }
            customBacktraceBuffer = buffer
        }

        NSSetUncaughtExceptionHandler { exception in
            let name = exception.name.rawValue
            let reason = exception.reason ?? "no reason"
            let stack = exception.callStackSymbols.prefix(48).joined(separator: "\n")
            let report = "uncaught exception: \(name)\nreason: \(reason)\n\(stack.isEmpty ? "(no stack)" : stack)"
            CustomDebugConsole.shared.crashReport(report)
            CustomDebugConsole.writeTextToPendingCrashFile("===CUSTOM-EXCEPTION===\n\(name): \(reason)\n\(stack)\n")
        }

        signal(SIGABRT, customSignalHandler)
        signal(SIGILL, customSignalHandler)
        signal(SIGSEGV, customSignalHandler)
        signal(SIGFPE, customSignalHandler)
        signal(SIGBUS, customSignalHandler)
        signal(SIGTRAP, customSignalHandler)
    }

    fileprivate static func pendingCrashFilePath() -> String {
        let base = NSSearchPathForDirectoriesInDomains(.applicationSupportDirectory, .userDomainMask, true).first ?? NSTemporaryDirectory()
        let directory = base + "/custom"
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        return directory + "/pending-crash.log"
    }

    fileprivate static func writeTextToPendingCrashFile(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }
        let path = self.pendingCrashFilePath()
        if let handle = FileHandle(forWritingAtPath: path) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: URL(fileURLWithPath: path))
        }
    }

    private func importPendingCrashFile() {
        let path = Self.pendingCrashFilePath()
        guard let data = FileManager.default.contents(atPath: path), !data.isEmpty else {
            return
        }
        let text = String(data: data, encoding: .utf8) ?? "(binary crash data)"
        self.crashReport("previous session crash:\n\(text)")
        FileManager.default.createFile(atPath: path, contents: Data())
    }
}
