import Foundation
import Testing
@testable import OysterKit

/// Asserts `body` throws an `APIError` matching `matches`.
private func expectAPIError(
    _ body: () async throws -> Void,
    sourceLocation: SourceLocation = #_sourceLocation,
    _ matches: (APIError) -> Bool
) async {
    do {
        try await body()
        Issue.record("expected an APIError", sourceLocation: sourceLocation)
    } catch let error as APIError {
        #expect(matches(error), "unexpected \(error)", sourceLocation: sourceLocation)
    } catch {
        Issue.record("expected an APIError, got \(error)", sourceLocation: sourceLocation)
    }
}

private func collect(_ stream: AsyncThrowingStream<ChatEvent, Error>) async throws -> [ChatEvent] {
    var events: [ChatEvent] = []
    for try await event in stream { events.append(event) }
    return events
}

/// The fixture's events, decoded line by line without the SSE parser.
private func fixtureEvents() throws -> [ChatEvent] {
    let text = String(decoding: try Fixture.data("chat-stream.sse.txt"), as: UTF8.self)
    return try text.split(separator: "\n")
        .filter { $0.hasPrefix("data: ") }
        .map { try ContractCoding.makeDecoder().decode(ChatEvent.self, from: Data($0.dropFirst(6).utf8)) }
}

private func sse(_ events: String...) -> Data {
    Data(events.map { "data: \($0)\n\n" }.joined().utf8)
}

// MARK: - REST

@Suite struct APIClientRESTTests {
    @Test func listPearlsSendsBearerAndDecodes() async throws {
        let body = try Fixture.data("pearls-list.json")
        let server = StubServer(basePath: "/api") { _ in .json(200, body) }

        let pearls = try await server.apiClient().listPearls()

        #expect(pearls == (try Fixture.decode(PearlsListResponse.self, "pearls-list.json")).pearls)
        let request = try #require(server.requests.first)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.path() == "/api/pearls")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer \(StubServer.token)")
    }

    @Test(arguments: Size.allCases)
    func pearlDataRequestsSizeAndDecodes(size: Size) async throws {
        let name = "pearl-data.\(size.rawValue).json"
        let body = try Fixture.data(name)
        let server = StubServer(basePath: "/api") { _ in .json(200, body) }

        let data = try await server.apiClient().pearlData(id: "pearl_01J8ZQ4K7M3CITIBIKE", size: size)

        #expect(data == (try Fixture.decode(PearlData.self, name)))
        let url = try #require(server.requests.first?.url)
        #expect(url.path() == "/api/pearls/pearl_01J8ZQ4K7M3CITIBIKE/data")
        #expect(url.query() == "size=\(size.rawValue)")
    }

    @Test func pearlIdIsASinglePathComponent() async throws {
        let body = try Fixture.data("pearl-data.small.json")
        let server = StubServer { _ in .json(200, body) }

        _ = try await server.apiClient().pearlData(id: "a/../b", size: .small)

        let url = try #require(server.requests.first?.url)
        #expect(url.path(percentEncoded: true) == "/pearls/a%2F..%2Fb/data")
    }

    @Test func oauthLinkPostsWithBearerAndDecodesTheURL() async throws {
        let body = try Fixture.data("oauth-link-response.json")
        let server = StubServer(basePath: "/api") { _ in .json(200, body) }

        let url = try await server.apiClient().oauthLink(provider: "github")

        #expect(url == (try Fixture.decode(OAuthLinkResponse.self, "oauth-link-response.json")).url)
        let request = try #require(server.requests.first)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path() == "/api/oauth/github/link")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer \(StubServer.token)")
    }

    @Test func oauthLinkProviderIsASinglePathComponent() async throws {
        let body = try Fixture.data("oauth-link-response.json")
        let server = StubServer { _ in .json(200, body) }

        _ = try await server.apiClient().oauthLink(provider: "a/../b")

        let url = try #require(server.requests.first?.url)
        #expect(url.path(percentEncoded: true) == "/oauth/a%2F..%2Fb/link")
    }

    @Test func oauthLinkUnknownProviderIsNotFound() async throws {
        let body = Data(#"{"error":{"code":"unknown_provider","message":"Unknown provider"}}"#.utf8)
        let server = StubServer { _ in .json(404, body) }
        let api = server.apiClient()

        await expectAPIError({ _ = try await api.oauthLink(provider: "nope") }) { error in
            if case .notFound = error { true } else { false }
        }
    }

    @Test(arguments: [401, 404, 503])
    func mappedStatusesBecomeDedicatedErrors(status: Int) async throws {
        let body = try Fixture.data("error.json")
        let server = StubServer { _ in .json(status, body) }
        let api = server.apiClient()

        await expectAPIError({ _ = try await api.listPearls() }) { error in
            switch (status, error) {
            case (401, .unauthorized), (404, .notFound), (503, .unavailable): true
            default: false
            }
        }
    }

    @Test func otherStatusCarriesServerErrorBody() async throws {
        let body = try Fixture.data("error.json")
        let server = StubServer { _ in .json(500, body) }
        let api = server.apiClient()

        await expectAPIError({ _ = try await api.pearlData(id: "p", size: .small) }) { error in
            guard case .server(let apiError) = error else { return false }
            return apiError == (try? Fixture.decode(ApiError.self, "error.json"))
        }
    }

    @Test func otherStatusWithoutErrorBodyStillReportsStatus() async throws {
        let server = StubServer { _ in StubResponse(status: 502, chunks: [Data("<html>Bad Gateway</html>".utf8)]) }
        let api = server.apiClient()

        await expectAPIError({ _ = try await api.listPearls() }) { error in
            guard case .server(let apiError) = error else { return false }
            return apiError.code == "http_502"
        }
    }

    @Test func malformedSuccessBodyIsDecodingError() async throws {
        let server = StubServer { _ in .json(200, Data(#"{"pearls":[{"id":1}]}"#.utf8)) }
        let api = server.apiClient()

        await expectAPIError({ _ = try await api.listPearls() }) { error in
            if case .decoding = error { true } else { false }
        }
    }
}

// MARK: - Chat stream

@Suite struct APIClientMessagesTests {
    @Test func postsMessageWithBearer() async throws {
        let server = StubServer(basePath: "/api") { _ in
            .eventStream([sse(#"{"type":"done"}"#)])
        }

        let events = try await collect(server.apiClient().messages(sessionId: "sess_1", message: "Citi Bike near work"))

        #expect(events == [.done])
        let request = try #require(server.requests.first)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path() == "/api/messages")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer \(StubServer.token)")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        let body = try JSONDecoder().decode(MessagesRequest.self, from: try #require(request.httpBody))
        #expect(body == MessagesRequest(sessionId: "sess_1", message: "Citi Bike near work"))
    }

    /// The fixture, CRLF-terminated, cut into chunks that split lines, the
    /// `data:` prefix, multi-byte UTF-8 (`·`), and CR from LF.
    @Test func fixtureInAwkwardChunksYieldsAllEventsInOrder() async throws {
        let crlf = Data(String(decoding: try Fixture.data("chat-stream.sse.txt"), as: UTF8.self)
            .replacingOccurrences(of: "\n", with: "\r\n").utf8)
        let lengths = [1, 2, 3, 5, 7, 11, 13, 17, 97, 3]
        var cuts: [Data] = []
        var start = crlf.startIndex
        while start < crlf.endIndex {
            let index = cuts.count
            var end = min(start + lengths[index % lengths.count], crlf.endIndex)
            // Every fifth chunk ends right after a CR, splitting the CRLF pair.
            if index % 5 == 4, let cr = crlf[start...].firstIndex(of: 0x0D) { end = cr + 1 }
            cuts.append(Data(crlf[start..<end]))
            start = end
        }
        let chunks = cuts
        #expect(chunks.contains { $0.last == 0x0D }, "no chunk splits a CRLF pair")
        let server = StubServer { _ in .eventStream(chunks) }

        let events = try await collect(server.apiClient().messages(sessionId: "s", message: "m"))

        #expect(events == (try fixtureEvents()))
        #expect(events.last == .done)
    }

    @Test func stopsAtDone() async throws {
        let server = StubServer { _ in
            .eventStream([sse(#"{"type":"text","delta":"hi"}"#, #"{"type":"done"}"#, #"{"type":"text","delta":"after"}"#)])
        }

        let events = try await collect(server.apiClient().messages(sessionId: "s", message: "m"))

        #expect(events == [.text(delta: "hi"), .done])
    }

    @Test func finishesWhenServerClosesWithoutDone() async throws {
        let server = StubServer { _ in .eventStream([sse(#"{"type":"status","text":"Working"}"#)]) }

        let events = try await collect(server.apiClient().messages(sessionId: "s", message: "m"))

        #expect(events == [.status(text: "Working")])
    }

    @Test func unknownEventTypeIsDeliveredAsUnknown() async throws {
        let server = StubServer { _ in
            .eventStream([sse(#"{"type":"thinking","text":"hmm"}"#, #"{"type":"done"}"#)])
        }

        let events = try await collect(server.apiClient().messages(sessionId: "s", message: "m"))

        #expect(events == [.unknown(type: "thinking"), .done])
    }

    @Test func undecodablePreviewIsSkipped() async throws {
        let server = StubServer { _ in
            .eventStream([sse(
                #"{"type":"preview","previews":{"extraLarge":{"value":"x"}}}"#,
                #"{"type":"text","delta":"still here"}"#,
                #"{"type":"done"}"#
            )])
        }

        let events = try await collect(server.apiClient().messages(sessionId: "s", message: "m"))

        #expect(events == [.text(delta: "still here"), .done])
    }

    @Test func malformedNonPreviewEventFailsStream() async throws {
        let server = StubServer { _ in
            .eventStream([sse(#"{"type":"text","delta":"ok"}"#, #"{"type":"text"}"#, #"{"type":"done"}"#)])
        }
        var received: [ChatEvent] = []

        await expectAPIError({
            for try await event in server.apiClient().messages(sessionId: "s", message: "m") { received.append(event) }
        }) { error in
            if case .decoding = error { true } else { false }
        }
        #expect(received == [.text(delta: "ok")])
    }

    @Test func httpErrorFailsStream() async throws {
        let body = try Fixture.data("error.json")
        let server = StubServer { _ in .json(401, body) }

        await expectAPIError({ _ = try await collect(server.apiClient().messages(sessionId: "s", message: "m")) }) { error in
            if case .unauthorized = error { true } else { false }
        }
    }

    @Test func consumerStoppingCancelsRequest() async throws {
        let server = StubServer { _ in
            .eventStream([sse(#"{"type":"status","text":"Working"}"#)], holdOpen: true)
        }

        for try await event in server.apiClient().messages(sessionId: "s", message: "m") {
            #expect(event == .status(text: "Working"))
            break
        }

        let deadline = ContinuousClock.now + .seconds(5)
        while !server.stopped, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(server.stopped)
    }
}

// MARK: - SSE parsing

@Suite struct SSEParserTests {
    private func parse(_ text: String) -> [String] {
        var parser = SSEParser()
        return text.utf8.compactMap { parser.consume($0) }
    }

    @Test(arguments: ["\n", "\r\n", "\r"])
    func fixtureParsesWithAnyLineEnding(lineEnding: String) throws {
        let text = String(decoding: try Fixture.data("chat-stream.sse.txt"), as: UTF8.self)
            .replacingOccurrences(of: "\n", with: lineEnding)
        let expected = text.components(separatedBy: lineEnding)
            .filter { $0.hasPrefix("data: ") }
            .map { String($0.dropFirst(6)) }

        #expect(parse(text) == expected)
        #expect(expected.count == 8)
    }

    @Test func multiLineDataJoinsWithNewline() {
        #expect(parse("data: {\"a\":\ndata:1}\n\n") == ["{\"a\":\n1}"])
    }

    @Test func ignoresCommentsAndOtherFields() {
        let text = ": keep-alive\nevent: message\nid: 7\nretry: 1000\nfoo: bar\ndata: x\n\n: ping\n\n"
        #expect(parse(text) == ["x"])
    }

    @Test func stripsOnlyOneLeadingSpace() {
        #expect(parse("data:x\n\ndata:  y\n\ndata\n\n") == ["x", " y", ""])
    }

    @Test func blankLinesWithoutDataDispatchNothing() {
        #expect(parse("\n\n\r\n: c\n\n").isEmpty)
    }

    @Test func unterminatedTrailingEventIsDropped() {
        #expect(parse("data: a\n\ndata: b\n") == ["a"])
    }

    @Test func leadingByteOrderMarkIsIgnored() {
        #expect(parse("\u{FEFF}data: a\n\n") == ["a"])
    }
}
