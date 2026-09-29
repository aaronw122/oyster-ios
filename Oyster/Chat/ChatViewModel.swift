import Foundation
import Observation
import OysterKit
import os

/// The chat stream the view model consumes; `APIClient` in the app, scripted in tests.
protocol ChatService: Sendable {
    func messages(sessionId: String, message: String) -> AsyncThrowingStream<ChatEvent, Error>
}

extension APIClient: ChatService {}

/// Presents a web sign-in and returns the callback URL, or `nil` when the user cancels.
@MainActor
protocol WebAuthenticating {
    func authenticate(url: URL, callbackScheme: String) async throws -> URL?
}

/// The server-side conversation id, kept across launches until the user starts over.
struct ChatSessionStore {
    private static let key = "chat.sessionId"
    let defaults: UserDefaults

    func load() -> String? {
        defaults.string(forKey: Self.key)
    }

    func save(_ sessionId: String) {
        defaults.set(sessionId, forKey: Self.key)
    }

    func clear() {
        defaults.removeObject(forKey: Self.key)
    }
}

@MainActor
@Observable
final class ChatViewModel {
    private(set) var rows: [ChatRow] = []
    /// What the assistant is doing right now; only the latest, only while streaming.
    private(set) var status: String?
    private(set) var isStreaming = false
    /// The server-side conversation; `nil` until the first message is sent.
    private(set) var sessionId: String?
    var draft = ""

    /// `nil` until the app is connected to a server.
    var service: (any ChatService)?

    @ObservationIgnored private let disk: PearlDiskStore?
    @ObservationIgnored private let sessions: ChatSessionStore
    @ObservationIgnored private let authenticator: any WebAuthenticating
    /// The running turn (and any sign-in it leads to). Tests await it.
    @ObservationIgnored private(set) var currentTask: Task<Void, Never>?
    /// A sign-in that succeeded while a turn was still streaming; resumed once the turn is idle.
    @ObservationIgnored private var pendingResumeProvider: String?

    private static let log = Logger(subsystem: "com.aaronw122.oyster", category: "chat")

    init(
        service: (any ChatService)?,
        disk: PearlDiskStore?,
        sessions: ChatSessionStore,
        authenticator: any WebAuthenticating
    ) {
        self.service = service
        self.disk = disk
        self.sessions = sessions
        self.authenticator = authenticator
        sessionId = sessions.load()
    }

    var canSend: Bool {
        service != nil && !isStreaming
    }

    /// A conversation is on the server (possibly from an earlier launch) that the user can leave.
    var canStartOver: Bool {
        sessionId != nil
    }

    /// Only the latest question is answerable, and only between turns.
    func canAnswer(_ row: ChatRow) -> Bool {
        guard case .question = row.kind else { return false }
        return canSend && rows.last?.id == row.id
    }

    // MARK: - Actions

    /// Sends the composer text.
    func sendDraft() {
        let text = draft
        if send(text) { draft = "" }
    }

    /// Sends `text` as the user's next message. Returns whether it was sent.
    @discardableResult
    func send(_ text: String) -> Bool {
        let message = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty, canSend, let service else { return false }
        rows.append(ChatRow(.user(message)))
        isStreaming = true
        status = nil
        let sessionId = sessionId ?? startSession()
        currentTask = Task { [weak self] in
            await self?.runTurn(service.messages(sessionId: sessionId, message: message))
        }
        return true
    }

    /// Stops the current turn.
    func cancel() {
        currentTask?.cancel()
        currentTask = nil
        isStreaming = false
        status = nil
        resumePendingSignIn()
    }

    /// Clears the transcript and forgets the server-side conversation; the next
    /// message starts a fresh one.
    func newConversation() {
        pendingResumeProvider = nil
        cancel()
        rows = []
        draft = ""
        sessionId = nil
        sessions.clear()
    }

    private func startSession() -> String {
        let id = UUID().uuidString
        sessionId = id
        sessions.save(id)
        return id
    }

    /// Re-opens a sign-in the user dismissed.
    func signIn(url: URL) {
        guard canSend else { return }
        currentTask = Task { [weak self] in
            await self?.presentSignIn(url: url)
        }
    }

    /// Asks the assistant to start the sign-in again after it failed.
    func retrySignIn(provider: String) {
        send("Let's try signing in to \(ProviderName.display(for: provider)) again.")
    }

    /// Handles `oyster://oauth/complete?...` — from the sign-in sheet or an opened URL.
    ///
    /// Both deliver the same callback, so a success is only accepted while its sign-in
    /// row is still pending: the first delivery consumes the row and later ones are ignored.
    func handleOAuthCallback(_ url: URL) {
        guard let callback = OAuthCallback(url: url) else { return }
        guard callback.succeeded else {
            markSignInFinished(provider: callback.provider)
            rows.append(ChatRow(.signInFailed(provider: callback.provider)))
            return
        }
        guard hasPendingSignIn(provider: callback.provider) else { return }
        markSignInFinished(provider: callback.provider)
        pendingResumeProvider = callback.provider
        if !isStreaming { resumePendingSignIn() }
    }

    /// Tells the assistant about a completed sign-in, once, when no turn is running.
    private func resumePendingSignIn() {
        guard let provider = pendingResumeProvider, canSend else { return }
        pendingResumeProvider = nil
        send("I've signed in to \(ProviderName.display(for: provider)).")
    }

    // MARK: - Streaming

    private func runTurn(_ events: AsyncThrowingStream<ChatEvent, Error>) async {
        var signIn: URL?
        do {
            for try await event in events {
                if Task.isCancelled { break }
                if case .oauth(_, let url) = event, let url = URL(string: url) { signIn = url }
                apply(event)
            }
        } catch {
            if !Task.isCancelled {
                rows.append(ChatRow(.notice(Self.plainMessage(for: error))))
            }
        }
        guard !Task.isCancelled else { return }
        isStreaming = false
        status = nil
        resumePendingSignIn()
        // The stream ends right after `oauth`; sign in once the turn is over — unless the
        // callback already arrived (via an opened URL) while the turn was streaming.
        if !isStreaming, let signIn, pendingSignInProvider(for: signIn) != nil {
            await presentSignIn(url: signIn)
        }
    }

    private func apply(_ event: ChatEvent) {
        switch event {
        case .text(let delta):
            status = nil
            if let last = rows.indices.last, case .assistant(let text) = rows[last].kind {
                rows[last].kind = .assistant(text + delta)
            } else {
                rows.append(ChatRow(.assistant(delta)))
            }
        case .question(let id, let text, let options):
            rows.append(ChatRow(.question(id: id, text: text, options: options ?? [])))
        case .status(let text):
            status = text
        case .oauth(let provider, let url):
            if let url = URL(string: url) {
                rows.append(ChatRow(.signIn(provider: provider, url: url)))
            }
        case .preview(let previews):
            let cards = PreviewCard.cards(for: previews)
            if !cards.isEmpty { rows.append(ChatRow(.previews(cards))) }
        case .saved(let pearl):
            recordSaved(pearl)
            rows.append(ChatRow(.saved(name: pearl.name)))
        case .unavailable(let text), .error(let text):
            rows.append(ChatRow(.notice(text)))
        case .done, .unknown:
            break
        }
    }

    private func recordSaved(_ pearl: PearlSummary) {
        guard let disk else { return }
        do {
            try PearlSync.recordSaved(pearl, disk: disk)
        } catch {
            // Saved on the server; the next library sync brings it to this iPhone.
            Self.log.error("Couldn't record saved Pearl on disk: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Sign-in

    private func presentSignIn(url: URL) async {
        do {
            guard let callback = try await authenticator.authenticate(url: url, callbackScheme: OAuthCallback.scheme) else {
                return  // The user closed the sheet; the row's button can reopen it.
            }
            handleOAuthCallback(callback)
        } catch {
            if let provider = pendingSignInProvider(for: url) {
                rows.append(ChatRow(.signInFailed(provider: provider)))
            }
        }
    }

    private func pendingSignInProvider(for url: URL) -> String? {
        for row in rows.reversed() {
            if case .signIn(let provider, let rowURL) = row.kind, rowURL == url { return provider }
        }
        return nil
    }

    private func hasPendingSignIn(provider: String) -> Bool {
        rows.contains { row in
            if case .signIn(let rowProvider, _) = row.kind { return rowProvider == provider }
            return false
        }
    }

    /// Once a sign-in completes (either way) its row no longer offers the button.
    private func markSignInFinished(provider: String) {
        rows.removeAll { row in
            if case .signIn(let rowProvider, _) = row.kind { return rowProvider == provider }
            return false
        }
    }

    static func plainMessage(for error: any Error) -> String {
        switch error as? APIError {
        case .unauthorized:
            "Your access token wasn't accepted. Check it in Settings."
        case .transport:
            "Couldn't reach your Oyster server. Check your connection and try again."
        default:
            "Something went wrong. Try again."
        }
    }
}
