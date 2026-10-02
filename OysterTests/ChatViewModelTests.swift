import Foundation
import OysterKit
import Testing
@testable import Oyster

@MainActor
@Suite struct ChatViewModelTests {
    let service = ScriptedChatService()
    let authenticator = FakeAuthenticator()
    let defaults = UserDefaults(suiteName: "ChatViewModelTests.\(UUID().uuidString)")!
    let disk = PearlDiskStore(directory: FileManager.default.temporaryDirectory.appending(component: UUID().uuidString))

    func makeModel() -> ChatViewModel {
        ChatViewModel(
            service: service,
            disk: disk,
            sessions: ChatSessionStore(defaults: defaults),
            authenticator: authenticator
        )
    }

    @Test func textDeltasAccumulateIntoOneReplyAndStatusClearsAtTheEnd() async {
        service.script(.init(events: [.status(text: "Finding stations"), .text(delta: "Hel"), .text(delta: "lo"), .done]))
        let model = makeModel()

        #expect(model.send("  hi  "))
        await model.settle()

        #expect(model.rows.map(\.kind) == [.user("hi"), .assistant("Hello")])
        #expect(model.status == nil)
        #expect(!model.isStreaming)
        #expect(service.sent == [.init(sessionId: model.sessionId ?? "", message: "hi")])
        #expect(model.sessionId != nil)
    }

    @Test func statusShowsOnlyTheLatestWhileStreamingAndCancelStopsTheStream() async throws {
        service.script(.init(events: [.status(text: "Finding stations"), .status(text: "Checking docks")], hangs: true))
        let model = makeModel()

        model.send("docks near work")
        try await until { model.status == "Checking docks" }
        #expect(model.isStreaming)
        #expect(!model.canSend)

        model.cancel()
        #expect(!model.isStreaming)
        #expect(model.status == nil)
        try await until { service.terminatedStreams == 1 }
        #expect(model.canSend)
    }

    @Test func questionOptionSendsItsTextAndOnlyTheLatestQuestionIsAnswerable() async {
        service.script(
            .init(events: [.question(id: "q_threshold", text: "How many open docks?", options: ["1", "3"]), .done]),
            .init(events: [.text(delta: "Got it."), .done])
        )
        let model = makeModel()

        model.send("Citi Bike near work")
        await model.settle()
        let question = model.rows[1]
        #expect(question.kind == .question(id: "q_threshold", text: "How many open docks?", options: ["1", "3"]))
        #expect(model.canAnswer(question))

        model.send("3")
        await model.settle()
        #expect(service.sent.map(\.message) == ["Citi Bike near work", "3"])
        #expect(!model.canAnswer(question))
        #expect(model.rows.last?.kind == .assistant("Got it."))
    }

    @Test func previewCardsFollowSizeOrderWithPlainLabels() async {
        let medium = WidgetOutput(value: "W 21st & 6th", subtitle: "5 docks", items: [.init(label: "W 22 St", value: "11")])
        let inline = WidgetOutput(value: "W 21st & 6th")
        let small = WidgetOutput(value: "W 21st & 6th", subtitle: "5 docks")
        service.script(.init(events: [.preview(previews: [.medium: medium, .inline: inline, .small: small]), .done]))
        let model = makeModel()

        model.send("preview it")
        await model.settle()

        guard case .previews(let cards) = model.rows.last?.kind else {
            Issue.record("expected a preview row, got \(String(describing: model.rows.last))")
            return
        }
        #expect(cards.map(\.size) == [.inline, .small, .medium])
        #expect(cards.map(\.label) == ["Lock Screen, one line", "Small", "Medium"])
        #expect(cards.map(\.output) == [inline, small, medium])
    }

    @Test func savedPearlIsWrittenToTheOnDeviceLibrary() async {
        let pearl = PearlSummary(id: "pearl_citibike", name: "Citi Bike docks near work")
        service.script(.init(events: [.saved(pearl: pearl), .done]))
        let model = makeModel()

        model.send("save it")
        await model.settle()

        #expect(disk.list() == [pearl])
        #expect(model.rows.last?.kind == .saved(name: "Citi Bike docks near work"))
    }

    @Test func successfulSignInSendsTheResumeMessage() async throws {
        let url = try #require(URL(string: "https://oyster.example.com/oauth/plaid/start?state=abc"))
        service.script(
            .init(events: [.status(text: "Connecting your bank"), .oauth(provider: "plaid", url: url.absoluteString), .done]),
            .init(events: [.text(delta: "Thanks!"), .done])
        )
        authenticator.result = .success(URL(string: "oyster://oauth/complete?provider=plaid&status=ok"))
        let model = makeModel()

        model.send("my checking balance")
        await model.settle()

        #expect(authenticator.requests == [.init(url: url, callbackScheme: "oyster")])
        #expect(service.sent.map(\.message) == ["my checking balance", "I've signed in to your bank."])
        #expect(model.rows.map(\.kind) == [
            .user("my checking balance"),
            .user("I've signed in to your bank."),
            .assistant("Thanks!"),
        ])
    }

    @Test func failedSignInOffersARetryThatAsksTheAssistantAgain() async throws {
        let url = try #require(URL(string: "https://oyster.example.com/oauth/github/start?state=abc"))
        service.script(.init(events: [.oauth(provider: "github", url: url.absoluteString), .done]))
        authenticator.result = .success(URL(string: "oyster://oauth/complete?provider=github&status=error&code=denied"))
        let model = makeModel()

        model.send("my open pull requests")
        await model.settle()

        #expect(model.rows.last?.kind == .signInFailed(provider: "github"))
        #expect(service.sent.count == 1)

        model.retrySignIn(provider: "github")
        await model.settle()
        #expect(service.sent.last?.message == "Let's try signing in to GitHub again.")
    }

    @Test func cancelledSignInIsSilentAndReopensWithAFreshLink() async throws {
        let url = try #require(URL(string: "https://oyster.example.com/oauth/strava/start?state=abc"))
        let fresh = try #require(URL(string: "https://oyster.example.com/oauth/strava/start?state=def"))
        service.script(.init(events: [.oauth(provider: "strava", url: url.absoluteString), .done]))
        service.links = [.success(fresh)]
        authenticator.result = .success(nil)
        let model = makeModel()

        model.send("my weekly miles")
        await model.settle()

        #expect(model.rows.last?.kind == .signIn(provider: "strava", url: url))
        #expect(service.sent.count == 1)
        #expect(service.linkRequests.isEmpty)

        authenticator.result = .success(URL(string: "oyster://oauth/complete?provider=strava&status=ok"))
        model.signIn(provider: "strava")
        await model.settle()
        // The first URL was spent when it was presented; the reopen presents the fresh one.
        #expect(service.linkRequests == ["strava"])
        #expect(authenticator.requests.map(\.url) == [url, fresh])
        #expect(service.sent.last?.message == "I've signed in to Strava.")
    }

    @Test func reopenWhoseLinkFailsShowsTheFailedSignInRow() async throws {
        let url = try #require(URL(string: "https://oyster.example.com/oauth/github/start?state=abc"))
        service.script(.init(events: [.oauth(provider: "github", url: url.absoluteString), .done]))
        service.links = [.failure(APIError.notFound)]
        authenticator.result = .success(nil)
        let model = makeModel()

        model.send("my open pull requests")
        await model.settle()
        model.signIn(provider: "github")
        await model.settle()

        #expect(model.rows.last?.kind == .signInFailed(provider: "github"))
        #expect(authenticator.requests.map(\.url) == [url])
        #expect(service.sent.count == 1)

        model.retrySignIn(provider: "github")
        await model.settle()
        #expect(service.sent.last?.message == "Let's try signing in to GitHub again.")
    }

    @Test func callbackAfterAReopenResumesOnce() async throws {
        let url = try #require(URL(string: "https://oyster.example.com/oauth/plaid/start?state=abc"))
        let fresh = try #require(URL(string: "https://oyster.example.com/oauth/plaid/start?state=def"))
        let callback = try #require(URL(string: "oyster://oauth/complete?provider=plaid&status=ok"))
        service.script(
            .init(events: [.oauth(provider: "plaid", url: url.absoluteString), .done]),
            .init(events: [.text(delta: "Thanks!"), .done])
        )
        service.links = [.success(fresh)]
        authenticator.result = .success(nil)
        let model = makeModel()

        model.send("my checking balance")
        await model.settle()
        authenticator.result = .success(callback)
        model.signIn(provider: "plaid")
        await model.settle()
        // The same callback also reaches `.onOpenURL`, after the sheet already delivered it.
        model.handleOAuthCallback(callback)
        await model.settle()
        // The row is consumed, so a stray tap can't reopen it either.
        model.signIn(provider: "plaid")
        await model.settle()

        #expect(authenticator.requests.map(\.url) == [url, fresh])
        #expect(service.sent.map(\.message) == ["my checking balance", "I've signed in to your bank."])
        #expect(model.rows.last?.kind == .assistant("Thanks!"))
    }

    @Test func sameCallbackFromTheSheetAndAnOpenedURLResumesOnce() async throws {
        let url = try #require(URL(string: "https://oyster.example.com/oauth/plaid/start?state=abc"))
        let callback = try #require(URL(string: "oyster://oauth/complete?provider=plaid&status=ok"))
        service.script(
            .init(events: [.oauth(provider: "plaid", url: url.absoluteString), .done]),
            .init(events: [.text(delta: "Thanks!"), .done])
        )
        authenticator.result = .success(callback)
        let model = makeModel()

        model.send("my checking balance")
        await model.settle()
        // The same callback also reaches `.onOpenURL`, after the sheet already delivered it.
        model.handleOAuthCallback(callback)
        await model.settle()

        #expect(service.sent.map(\.message) == ["my checking balance", "I've signed in to your bank."])
        #expect(model.rows.filter { $0.kind == .user("I've signed in to your bank.") }.count == 1)
    }

    @Test func callbackArrivingMidStreamResumesOnceAfterTheTurnEnds() async throws {
        let url = try #require(URL(string: "https://oyster.example.com/oauth/strava/start?state=abc"))
        let callback = try #require(URL(string: "oyster://oauth/complete?provider=strava&status=ok"))
        service.script(
            .init(events: [.oauth(provider: "strava", url: url.absoluteString)], hangs: true),
            .init(events: [.text(delta: "Connected."), .done])
        )
        authenticator.result = .success(callback)
        let model = makeModel()

        model.send("my weekly miles")
        try await until { model.rows.last?.kind == .signIn(provider: "strava", url: url) }
        model.handleOAuthCallback(callback)
        model.handleOAuthCallback(callback)
        #expect(model.isStreaming)
        #expect(service.sent.count == 1)

        service.finishHangingTurn()
        await model.settle()

        #expect(service.sent.map(\.message) == ["my weekly miles", "I've signed in to Strava."])
        // Already signed in, so the sheet isn't presented for the consumed row.
        #expect(authenticator.requests.isEmpty)
        #expect(model.rows.last?.kind == .assistant("Connected."))
    }

    @Test func aLaterSignInToTheSameProviderStillResumes() async throws {
        let first = try #require(URL(string: "https://oyster.example.com/oauth/github/start?state=one"))
        let second = try #require(URL(string: "https://oyster.example.com/oauth/github/start?state=two"))
        let callback = try #require(URL(string: "oyster://oauth/complete?provider=github&status=ok"))
        service.script(
            .init(events: [.oauth(provider: "github", url: first.absoluteString), .done]),
            .init(events: [.text(delta: "Done."), .done]),
            .init(events: [.oauth(provider: "github", url: second.absoluteString), .done]),
            .init(events: [.text(delta: "Done again."), .done])
        )
        authenticator.result = .success(callback)
        let model = makeModel()

        model.send("my pull requests")
        await model.settle()
        model.send("my issues too")
        await model.settle()

        #expect(service.sent.map(\.message) == [
            "my pull requests", "I've signed in to GitHub.",
            "my issues too", "I've signed in to GitHub.",
        ])
        #expect(authenticator.requests.map(\.url) == [first, second])
    }

    @Test func errorsBecomePlainLanguageRows() async {
        service.script(
            .init(events: [.text(delta: "Looking"), .unavailable(text: "That data isn't available yet."), .error(text: "Something broke on the server.")]),
            .init(events: [], error: APIError.transport(URLError(.notConnectedToInternet))),
            .init(events: [], error: APIError.decoding(DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "{\"type\":1}"))))
        )
        let model = makeModel()

        model.send("one")
        await model.settle()
        model.send("two")
        await model.settle()
        model.send("three")
        await model.settle()

        let notices = model.rows.compactMap { row -> String? in
            if case .notice(let text) = row.kind { return text }
            return nil
        }
        #expect(notices == [
            "That data isn't available yet.",
            "Something broke on the server.",
            "Couldn't reach your Oyster server. Check your connection and try again.",
            "Something went wrong. Try again.",
        ])
        #expect(model.canSend)
    }

    @Test func sessionPersistsAcrossLaunchesUntilNewConversation() async throws {
        let first = makeModel()
        #expect(!first.canStartOver)

        service.script(.init(events: [.text(delta: "Hi"), .done]), .init(events: [.done]))
        first.send("hello")
        await first.settle()
        let sessionId = try #require(first.sessionId)

        // A later launch: empty transcript, same server conversation, and it can be left.
        let relaunched = makeModel()
        #expect(relaunched.rows.isEmpty)
        #expect(relaunched.sessionId == sessionId)
        #expect(relaunched.canStartOver)

        relaunched.newConversation()
        #expect(!relaunched.canStartOver)
        #expect(makeModel().sessionId == nil)

        relaunched.send("again")
        await relaunched.settle()
        let fresh = try #require(relaunched.sessionId)
        #expect(fresh != sessionId)
        #expect(service.sent.map(\.sessionId) == [sessionId, fresh])
    }

    @Test(arguments: [
        ("oyster://oauth/complete?provider=plaid&status=ok", OAuthCallback?.some(.init(provider: "plaid", succeeded: true))),
        ("oyster://oauth/complete?provider=plaid&status=error&code=denied", .some(.init(provider: "plaid", succeeded: false))),
        ("oyster://oauth/complete?status=ok", nil),
        ("oyster://somewhere/else?provider=plaid&status=ok", nil),
        ("https://oauth/complete?provider=plaid&status=ok", nil),
    ])
    func oauthCallbackParsing(url: String, expected: OAuthCallback?) throws {
        #expect(OAuthCallback(url: try #require(URL(string: url))) == expected)
    }

    @Test func providerDisplayNames() {
        #expect(ProviderName.display(for: "plaid") == "your bank")
        #expect(ProviderName.display(for: "github") == "GitHub")
        #expect(ProviderName.display(for: "whoop") == "Whoop")
        #expect(ProviderName.display(for: "google_calendar") == "Google Calendar")
    }
}

// MARK: - Support

extension ChatViewModel {
    /// Waits for the current turn and anything it chains into (sign-in, resume message).
    func settle() async {
        while let task = currentTask {
            await task.value
            if currentTask == task { return }
        }
    }
}

@MainActor
func until(_ condition: () -> Bool, timeout: Duration = .seconds(2)) async throws {
    let deadline = ContinuousClock.now + timeout
    while !condition() {
        guard ContinuousClock.now < deadline else {
            Issue.record("condition not met in time")
            return
        }
        try await Task.sleep(for: .milliseconds(10))
    }
}

/// Plays back one scripted turn per `messages` call and records what was sent.
final class ScriptedChatService: ChatService, @unchecked Sendable {
    struct Turn {
        var events: [ChatEvent]
        var error: (any Error)?
        /// Leave the stream open after the events, like a server still working.
        var hangs = false

        init(events: [ChatEvent], error: (any Error)? = nil, hangs: Bool = false) {
            self.events = events
            self.error = error
            self.hangs = hangs
        }
    }

    struct Sent: Equatable {
        let sessionId: String
        let message: String
    }

    private let lock = NSLock()
    private var turns: [Turn] = []
    private var _sent: [Sent] = []
    private var _terminated = 0
    private var hanging: AsyncThrowingStream<ChatEvent, Error>.Continuation?
    private var _links: [Result<URL, any Error>] = []
    private var _linkRequests: [String] = []

    var sent: [Sent] { lock.withLock { _sent } }
    var terminatedStreams: Int { lock.withLock { _terminated } }
    /// Answers to `oauthLink`, one per call.
    var links: [Result<URL, any Error>] {
        get { lock.withLock { _links } }
        set { lock.withLock { _links = newValue } }
    }
    var linkRequests: [String] { lock.withLock { _linkRequests } }

    func oauthLink(provider: String) async throws -> URL {
        let link = lock.withLock {
            _linkRequests.append(provider)
            return _links.isEmpty ? nil : _links.removeFirst()
        }
        guard let link else { throw APIError.notFound }
        return try link.get()
    }

    func script(_ turns: Turn...) {
        lock.withLock { self.turns.append(contentsOf: turns) }
    }

    /// Ends the open stream of a turn scripted with `hangs`, as if the server finished it.
    func finishHangingTurn() {
        // Finish outside the lock: `onTermination` takes it too.
        let continuation = lock.withLock {
            defer { hanging = nil }
            return hanging
        }
        continuation?.finish()
    }

    func messages(sessionId: String, message: String) -> AsyncThrowingStream<ChatEvent, Error> {
        let turn = lock.withLock {
            _sent.append(Sent(sessionId: sessionId, message: message))
            return turns.isEmpty ? Turn(events: [.done]) : turns.removeFirst()
        }
        return AsyncThrowingStream { continuation in
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                self.lock.withLock { self._terminated += 1 }
            }
            for event in turn.events { continuation.yield(event) }
            if turn.hangs {
                self.lock.withLock { self.hanging = continuation }
                return
            }
            if let error = turn.error {
                continuation.finish(throwing: error)
            } else {
                continuation.finish()
            }
        }
    }
}

/// Start URLs are single-use, like the backend's: presenting one twice fails.
@MainActor
final class FakeAuthenticator: WebAuthenticating {
    struct Request: Equatable {
        let url: URL
        let callbackScheme: String
    }

    struct SpentURL: Error {}

    var result: Result<URL?, any Error> = .success(nil)
    private(set) var requests: [Request] = []

    func authenticate(url: URL, callbackScheme: String) async throws -> URL? {
        let spent = requests.contains { $0.url == url }
        requests.append(Request(url: url, callbackScheme: callbackScheme))
        if spent { throw SpentURL() }
        return try result.get()
    }
}
