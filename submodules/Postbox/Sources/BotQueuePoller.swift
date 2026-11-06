import Foundation

/// What one `getUpdates` call produced.
public enum BotQueueFetchOutcome {
    /// Updates in queue order (oldest first), at most the requested limit.
    case updates([[String: Any]])
    /// Transport or API failure; `retryAfter` is the wait the API asked for, if it asked.
    case failure(String, retryAfter: Double?)
    /// Another process is polling the same bot (`409 Conflict`). Two readers with one
    /// queue destroy each other's batches, so this is reported separately from a generic
    /// failure: it means the server-side reader is still running.
    case conflict(String)
}

/// `getUpdates` over HTTPS. Everything here is synchronous: callers run it on a
/// background queue, never on the main thread.
public final class BotQueuePoller {
    private let endpoint: URL
    private let session: URLSession

    public init(apiBase: String, token: String, proxy: String = "", session: URLSession? = nil) {
        self.endpoint = URL(string: "\(apiBase)/bot\(token)/getUpdates")!
        if let session = session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 60.0
            configuration.timeoutIntervalForResource = 85.0
            if let proxy = BotQueuePoller.proxyDictionary(proxy) {
                configuration.connectionProxyDictionary = proxy
            }
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            self.session = URLSession(configuration: configuration)
        }
    }

    /// Proxy description to `URLSession`'s dictionary; `nil` for a direct connection.
    public static func proxyDictionary(_ description: String) -> [AnyHashable: Any]? {
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed), let host = url.host, let port = url.port else {
            return nil
        }
        let scheme = (url.scheme ?? "").lowercased()
        let type: String
        switch scheme {
        case "socks", "socks5":
            type = "SOCKS"
        case "http", "https":
            type = "HTTP"
        default:
            return nil
        }
        return [
            "\(type)Enable": 1,
            "\(type)Proxy": host,
            "\(type)Port": port
        ]
    }

    /// One long-poll call. `offset` is the position to resume from (`nil` asks for the
    /// whole queue, oldest first).
    public func fetch(offset: Int64?, limit: Int, timeout: Int, allowedUpdates: [String]) -> BotQueueFetchOutcome {
        var request = URLRequest(url: self.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = BotQueuePoller.formBody([
            "offset": offset.flatMap { $0 > 0 ? String($0) : nil },
            "limit": String(limit),
            "timeout": String(timeout),
            "allowed_updates": BotQueuePoller.jsonArray(allowedUpdates)
        ])

        let semaphore = DispatchSemaphore(value: 0)
        var payload: Data?
        var statusCode: Int?
        var transportError: String?

        self.session.dataTask(with: request) { data, response, error in
            payload = data
            statusCode = (response as? HTTPURLResponse)?.statusCode
            transportError = error?.localizedDescription
            semaphore.signal()
        }.resume()

        // The long poll itself may take `timeout` seconds; the extra margin covers the
        // connection setup and the response upload, and keeps a stuck request from
        // holding the drain loop forever.
        if semaphore.wait(timeout: .now() + .milliseconds((timeout + 20) * 1000)) == .timedOut {
            return .failure("timed out", retryAfter: nil)
        }

        if let transportError = transportError {
            return .failure(transportError, retryAfter: nil)
        }
        guard let data = payload else {
            return .failure("empty response", retryAfter: nil)
        }

        return BotQueuePoller.parseResponse(data: data, statusCode: statusCode)
    }

    /// Mapping of a Bot API answer to the outcome, shared with the tests.
    public static func parseResponse(data: Data, statusCode: Int?) -> BotQueueFetchOutcome {
        guard let object = (try? JSONSerialization.jsonObject(with: data, options: [])) as? [String: Any] else {
            return .failure("malformed response", retryAfter: nil)
        }
        let ok = (object["ok"] as? NSNumber)?.boolValue ?? false
        if ok {
            guard let updates = object["result"] as? [[String: Any]] else {
                return .failure("unexpected result", retryAfter: nil)
            }
            return .updates(updates)
        }

        let description = object["description"] as? String ?? "unknown error"
        let errorCode = (object["error_code"] as? NSNumber)?.intValue ?? statusCode ?? 0
        if errorCode == 409 {
            return .conflict(description)
        }
        var retryAfter: Double?
        if let parameters = object["parameters"] as? [String: Any], let value = parameters["retry_after"] as? NSNumber {
            retryAfter = value.doubleValue
        }
        return .failure("\(errorCode): \(description)", retryAfter: retryAfter)
    }

    static func jsonArray(_ values: [String]) -> String {
        let encoded = values.map { value -> String in
            let escaped = value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            return "\"\(escaped)\""
        }
        return "[" + encoded.joined(separator: ",") + "]"
    }

    static func formBody(_ fields: [String: String?]) -> Data? {
        var components: [String] = []
        for (key, value) in fields {
            guard let value = value else {
                continue
            }
            let escaped = value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? value
            components.append("\(key)=\(escaped)")
        }
        return components.sorted().joined(separator: "&").data(using: .utf8)
    }
}
