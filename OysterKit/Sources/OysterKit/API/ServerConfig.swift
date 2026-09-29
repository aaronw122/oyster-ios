import Foundation

/// Where the Oyster backend lives and the bearer token that authenticates this
/// device. Kept in the App Group `SharedStore` so the app and the widget
/// extension talk to the same server as the same user.
public struct ServerConfig: Codable, Equatable, Sendable {
    public var baseURL: URL
    public var token: String

    public static let storeKey = StoreKey<ServerConfig>("serverConfig")

    public init(baseURL: URL, token: String) {
        self.baseURL = baseURL
        self.token = token
    }

    /// The stored config, or `nil` when none has been saved (or it is unreadable).
    public static func load(from store: SharedStore) -> ServerConfig? {
        store.get(storeKey)
    }

    public func save(to store: SharedStore) throws {
        try store.set(self, for: Self.storeKey)
    }
}
