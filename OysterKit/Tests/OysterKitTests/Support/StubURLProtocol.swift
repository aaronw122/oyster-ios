import Foundation
import os
@testable import OysterKit

/// A canned HTTP response, delivered to the client as the given chunks.
struct StubResponse: Sendable {
    var status: Int
    var headers: [String: String] = [:]
    var chunks: [Data] = []
    /// Keep the connection open after the last chunk instead of finishing.
    var holdOpen = false

    static func json(_ status: Int, _ body: Data) -> StubResponse {
        StubResponse(status: status, headers: ["Content-Type": "application/json"], chunks: [body])
    }

    /// A `text/event-stream` response. The content type matters: without one,
    /// URLSession buffers the first 512 bytes to sniff it.
    static func eventStream(_ chunks: [Data], holdOpen: Bool = false) -> StubResponse {
        StubResponse(status: 200, headers: ["Content-Type": "text/event-stream"], chunks: chunks, holdOpen: holdOpen)
    }
}

/// One stubbed server. Each instance claims a unique host, so concurrently
/// running tests never see each other's requests.
final class StubServer: Sendable {
    typealias Handler = @Sendable (URLRequest) -> StubResponse

    struct State {
        var requests: [URLRequest] = []
        var stopped = false
    }

    let baseURL: URL
    let session: URLSession
    fileprivate let handler: Handler
    fileprivate let state = OSAllocatedUnfairLock(initialState: State())

    init(basePath: String = "", handler: @escaping Handler) {
        let host = "stub-\(UUID().uuidString.lowercased()).test"
        baseURL = URL(string: "https://\(host)\(basePath)")!
        self.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        session = URLSession(configuration: configuration)
        StubURLProtocol.servers.withLock { $0[host] = self }
    }

    deinit {
        let host = baseURL.host()!
        StubURLProtocol.servers.withLock { _ = $0.removeValue(forKey: host) }
        session.invalidateAndCancel()
    }

    var requests: [URLRequest] { state.withLock { $0.requests } }
    var stopped: Bool { state.withLock { $0.stopped } }

    static let token = "tok_test_123"

    /// A config pointing at this server, authenticated with `token`.
    var config: ServerConfig { ServerConfig(baseURL: baseURL, token: Self.token) }

    /// A client that talks to this server.
    func apiClient() -> APIClient { APIClient(config: config, session: session) }
}

final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    static let servers = OSAllocatedUnfairLock<[String: StubServer]>(initialState: [:])

    private static func server(for request: URLRequest) -> StubServer? {
        guard let host = request.url?.host() else { return nil }
        return servers.withLock { $0[host] }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        server(for: request) != nil
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let server = Self.server(for: request), let client else { return }
        let recorded = Self.withBody(request)
        server.state.withLock { $0.requests.append(recorded) }

        let stub = server.handler(recorded)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: stub.status,
            httpVersion: "HTTP/1.1",
            headerFields: stub.headers
        )!
        client.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        for chunk in stub.chunks {
            client.urlProtocol(self, didLoad: chunk)
        }
        if !stub.holdOpen {
            client.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {
        Self.server(for: request)?.state.withLock { $0.stopped = true }
    }

    private static func readAll(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }

    /// URLSession moves a request's body into `httpBodyStream`; read it back so tests can inspect it.
    private static func withBody(_ request: URLRequest) -> URLRequest {
        var request = request
        if request.httpBody == nil, let stream = request.httpBodyStream {
            request.httpBody = readAll(stream)
        }
        return request
    }
}
