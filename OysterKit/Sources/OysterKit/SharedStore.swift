import Foundation

/// A typed key naming a `Codable` value in a `SharedStore`.
public struct StoreKey<Value: Codable & Sendable>: Hashable, Sendable {
    public let name: String

    public init(_ name: String) {
        self.name = name
    }
}

/// Typed `Codable` key/value storage over `UserDefaults`.
///
/// Values are JSON-encoded, so any `Codable` type round-trips. Reads of
/// missing keys or undecodable data yield `nil` rather than failing.
public final class SharedStore: @unchecked Sendable {
    // UserDefaults is documented thread-safe; the encoder/decoder are created per call.
    private let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// Store backed by the App Group suite; `nil` without the entitlement.
    public static var appGroup: SharedStore? {
        AppGroup.userDefaults.map(SharedStore.init(defaults:))
    }

    public func get<Value>(_ key: StoreKey<Value>) -> Value? {
        guard let data = defaults.data(forKey: key.name) else { return nil }
        return try? JSONDecoder().decode(Value.self, from: data)
    }

    public func set<Value>(_ value: Value, for key: StoreKey<Value>) throws {
        let data = try JSONEncoder().encode(value)
        defaults.set(data, forKey: key.name)
    }

    public func remove<Value>(_ key: StoreKey<Value>) {
        defaults.removeObject(forKey: key.name)
    }
}
