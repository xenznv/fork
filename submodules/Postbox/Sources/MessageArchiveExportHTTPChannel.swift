import Foundation

/// Delivers export events to the archive backend over HTTPS, one `POST /events`
/// per event (`Authorization: Bearer`, JSON body, base64 payload, see PROJECT.md
/// §10). A 2xx answer means the backend stored the event durably; a repeated
/// delivery is deduped there by `event_id`, so any replay is safe.
public final class ArchivedMessageExportHTTPChannel: ArchivedMessageExportChannel {
    private let url: URL
    private let token: String
    private let session: URLSession

    public init(url: URL, token: String, session: URLSession = .shared) {
        self.url = url
        self.token = token
        self.session = session
    }

    public func send(_ event: ArchivedMessageExportEvent, _ completion: @escaping (ArchivedMessageExportChannelResult) -> Void) {
        let request = self.makeRequest(event)
        self.session.dataTask(with: request) { data, response, error in
            completion(ArchivedMessageExportHTTPChannel.result(data: data, response: response, error: error))
        }.resume()
    }

    /// Request construction is shared with the tests, which verify the wire format
    /// against the backend contract without running any networking.
    func makeRequest(_ event: ArchivedMessageExportEvent) -> URLRequest {
        var request = URLRequest(url: self.url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(self.token)", forHTTPHeaderField: "Authorization")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.httpBody = self.body(event)
        return request
    }

    private func body(_ event: ArchivedMessageExportEvent) -> Data? {
        let object: [String: Any] = [
            "event_id": event.eventId,
            "stream": event.stream,
            "payload": event.payload.base64EncodedString(),
            "event_time": event.eventTime
        ]
        return try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    /// Mapping of a transfer outcome to the channel result, shared with the tests.
    static func result(data: Data?, response: URLResponse?, error: Error?) -> ArchivedMessageExportChannelResult {
        if let error = error {
            return .failure(error.localizedDescription)
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            return .failure("non_http_response")
        }
        let visibleBody = (data.flatMap { String(data: $0, encoding: .utf8) } ?? "").prefix(256)
        switch httpResponse.statusCode {
        case 200...299:
            return .accepted
        default:
            return .failure("backend_\(httpResponse.statusCode): \(visibleBody)")
        }
    }
}
