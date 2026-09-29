import Foundation

public enum APIError: Error {
    /// 401: the bearer token is missing, invalid, or revoked.
    case unauthorized
    /// 404: the Pearl is unknown or belongs to another account.
    case notFound
    /// 503: the Pearl failed to run and has no last-good value for that size.
    case unavailable
    /// Any other non-2xx status, with the server's `{ error: { code, message } }` body.
    case server(ApiError)
    /// The request never produced an HTTP response (offline, timeout, TLS, …).
    case transport(any Error)
    /// A 2xx body (or stream event) did not match the contract.
    case decoding(any Error)
}

/// Client for the Oyster backend's app routes (§2c). Every request carries
/// `Authorization: Bearer <token>`.
public actor APIClient {
    public nonisolated let config: ServerConfig
    private let session: URLSession

    /// Upper bound on how much of an error body a failed chat stream reads.
    private static let maxErrorBodyBytes = 64 * 1024

    public init(config: ServerConfig, session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    /// `GET /pearls`
    public func listPearls() async throws -> [PearlSummary] {
        let request = makeRequest(path: ["pearls"])
        return try await send(request, as: PearlsListResponse.self).pearls
    }

    /// `GET /pearls/:id/data?size=`
    public func pearlData(id: String, size: Size) async throws -> PearlData {
        let request = makeRequest(
            path: ["pearls", id, "data"],
            query: [URLQueryItem(name: "size", value: size.rawValue)]
        )
        return try await send(request, as: PearlData.self)
    }

    /// `POST /messages`, streamed as `ChatEvent`s.
    ///
    /// The stream yields events in arrival order and finishes after `.done` (which
    /// it yields) or when the server closes the connection. `preview` events that
    /// don't decode (e.g. a size this client doesn't know) are skipped. A non-2xx
    /// response, transport failure, or any other undecodable event finishes the
    /// stream with an `APIError`. Terminating the stream early (the consumer
    /// breaks out or its task is cancelled) cancels the HTTP request.
    public nonisolated func messages(sessionId: String, message: String) -> AsyncThrowingStream<ChatEvent, Error> {
        let request: URLRequest
        do {
            var post = makeRequest(path: ["messages"], method: "POST", accept: "text/event-stream")
            post.setValue("application/json", forHTTPHeaderField: "Content-Type")
            post.httpBody = try ContractCoding.makeEncoder()
                .encode(MessagesRequest(sessionId: sessionId, message: message))
            request = post
        } catch {
            return AsyncThrowingStream { $0.finish(throwing: APIError.decoding(error)) }
        }
        let session = self.session

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await Self.streamEvents(request, session: session) { continuation.yield($0) }
                    continuation.finish()
                } catch let error as APIError {
                    continuation.finish(throwing: error)
                } catch is CancellationError {
                    continuation.finish()
                } catch let error as URLError where error.code == .cancelled {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: APIError.transport(error))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Requests

    private nonisolated func makeRequest(
        path: [String],
        query: [URLQueryItem] = [],
        method: String = "GET",
        accept: String = "application/json"
    ) -> URLRequest {
        var url = config.baseURL
        for component in path {
            url.append(component: component)
        }
        if !query.isEmpty {
            url.append(queryItems: query)
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(config.token)", forHTTPHeaderField: "Authorization")
        request.setValue(accept, forHTTPHeaderField: "Accept")
        return request
    }

    private func send<T: Decodable>(_ request: URLRequest, as type: T.Type) async throws -> T {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.transport(error)
        }
        let status = try Self.statusCode(of: response)
        guard (200..<300).contains(status) else {
            throw Self.error(status: status, body: data)
        }
        do {
            return try ContractCoding.makeDecoder().decode(type, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }

    private static func statusCode(of response: URLResponse) throws -> Int {
        guard let http = response as? HTTPURLResponse else {
            throw APIError.transport(URLError(.badServerResponse))
        }
        return http.statusCode
    }

    /// Maps a non-2xx response to an `APIError`.
    static func error(status: Int, body: Data) -> APIError {
        switch status {
        case 401: return .unauthorized
        case 404: return .notFound
        case 503: return .unavailable
        default:
            let apiError = (try? ContractCoding.makeDecoder().decode(ApiError.self, from: body))
                ?? ApiError(
                    code: "http_\(status)",
                    message: HTTPURLResponse.localizedString(forStatusCode: status)
                )
            return .server(apiError)
        }
    }

    // MARK: - Chat stream

    private static func streamEvents(
        _ request: URLRequest,
        session: URLSession,
        yield: (ChatEvent) -> Void
    ) async throws {
        let (bytes, response) = try await session.bytes(for: request)
        let status = try statusCode(of: response)
        guard (200..<300).contains(status) else {
            var body = Data()
            for try await byte in bytes {
                body.append(byte)
                if body.count >= maxErrorBodyBytes { break }
            }
            throw error(status: status, body: body)
        }

        var parser = SSEParser()
        for try await byte in bytes {
            guard let payload = parser.consume(byte), let event = try decodeEvent(payload) else { continue }
            yield(event)
            if event == .done { return }
        }
    }

    private struct EventType: Decodable {
        let type: String
    }

    /// Decodes one SSE `data` payload. Returns `nil` for payloads the stream
    /// skips: empty data and `preview` events this client can't decode.
    static func decodeEvent(_ payload: String) throws -> ChatEvent? {
        if payload.isEmpty { return nil }
        let data = Data(payload.utf8)
        let decoder = ContractCoding.makeDecoder()
        do {
            return try decoder.decode(ChatEvent.self, from: data)
        } catch {
            if (try? decoder.decode(EventType.self, from: data))?.type == "preview" { return nil }
            throw APIError.decoding(error)
        }
    }
}
