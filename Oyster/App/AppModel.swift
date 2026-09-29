import Foundation
import Observation
import OysterKit

/// App-wide state: which server this iPhone talks to, and the shared chat.
@MainActor
@Observable
final class AppModel {
    enum ConnectError: Error, Equatable {
        case invalidAddress
        case unauthorized
        case unreachable
        case notOyster
        case cannotStore

        var message: String {
            switch self {
            case .invalidAddress: "That doesn't look like a server address."
            case .unauthorized: "That access token wasn't accepted."
            case .unreachable: "Couldn't reach that server. Check the address and your connection."
            case .notOyster: "That server didn't answer like an Oyster server."
            case .cannotStore: "Oyster couldn't save these settings on this iPhone."
            }
        }
    }

    private(set) var config: ServerConfig?
    private(set) var api: APIClient?
    let chat: ChatViewModel

    @ObservationIgnored let disk: PearlDiskStore?
    @ObservationIgnored private let store: SharedStore?

    init(
        store: SharedStore? = .appGroup,
        disk: PearlDiskStore? = .appGroup,
        sessions: ChatSessionStore = ChatSessionStore(defaults: .standard),
        authenticator: any WebAuthenticating = WebAuthenticator()
    ) {
        self.store = store
        self.disk = disk
        let config = store.flatMap(ServerConfig.load(from:))
        let api = config.map { APIClient(config: $0) }
        self.config = config
        self.api = api
        chat = ChatViewModel(service: api, disk: disk, sessions: sessions, authenticator: authenticator)
    }

    /// Checks the server accepts `token` (by listing Pearls, which also fills
    /// the on-device library), then saves the config for the app and widget.
    func connect(address: String, token: String) async throws(ConnectError) {
        guard let baseURL = Self.baseURL(from: address) else { throw .invalidAddress }
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let store else { throw .cannotStore }
        let config = ServerConfig(baseURL: baseURL, token: token)
        let api = APIClient(config: config)
        do {
            if let disk {
                try await PearlSync.sync(api: api, disk: disk)
            } else {
                _ = try await api.listPearls()
            }
        } catch let error as APIError {
            switch error {
            case .unauthorized: throw .unauthorized
            case .transport: throw .unreachable
            case .notFound, .unavailable, .server, .decoding: throw .notOyster
            }
        } catch {
            throw .cannotStore
        }
        do {
            try config.save(to: store)
        } catch {
            throw .cannotStore
        }
        self.config = config
        self.api = api
        chat.service = api
    }

    /// `oyster.example.com` → `https://oyster.example.com`; keeps an explicit http(s) scheme.
    static func baseURL(from address: String) -> URL? {
        var text = address.trimmingCharacters(in: .whitespacesAndNewlines)
        while text.hasSuffix("/") { text.removeLast() }
        if !text.lowercased().hasPrefix("http://") && !text.lowercased().hasPrefix("https://") {
            text = "https://" + text
        }
        guard let components = URLComponents(string: text),
              let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = components.host, !host.isEmpty,
              let url = components.url
        else { return nil }
        return url
    }
}
