import Foundation
import Testing
@testable import OysterKit

private struct Sample: Codable, Equatable, Sendable {
    let id: String
    let values: [Int]
    let updatedAt: Date?
}

@Suite final class SharedStoreTests {
    private let suiteName = "OysterKitTests.\(UUID().uuidString)"
    private let defaults: UserDefaults
    private let store: SharedStore

    init() {
        defaults = UserDefaults(suiteName: suiteName)!
        store = SharedStore(defaults: defaults)
    }

    deinit {
        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test func roundTripsCodableStruct() throws {
        let key = StoreKey<Sample>("sample")
        let value = Sample(id: "pearl-1", values: [1, 2, 3], updatedAt: Date(timeIntervalSince1970: 1_700_000_000))
        try store.set(value, for: key)
        #expect(store.get(key) == value)
    }

    @Test func roundTripsScalarsAndOverwrites() throws {
        let token = StoreKey<String>("authToken")
        try store.set("first", for: token)
        try store.set("second", for: token)
        #expect(store.get(token) == "second")

        let url = StoreKey<URL>("baseURL")
        try store.set(URL(string: "https://oyster.example.com/api")!, for: url)
        #expect(store.get(url) == URL(string: "https://oyster.example.com/api"))
    }

    @Test func missingKeyReturnsNil() {
        #expect(store.get(StoreKey<String>("absent")) == nil)
    }

    @Test func removeDeletesOnlyThatKey() throws {
        let a = StoreKey<Int>("a")
        let b = StoreKey<Int>("b")
        try store.set(1, for: a)
        try store.set(2, for: b)
        store.remove(a)
        #expect(store.get(a) == nil)
        #expect(store.get(b) == 2)
    }

    @Test func garbageDataReturnsNil() {
        defaults.set(Data("not json".utf8), forKey: "garbage")
        #expect(store.get(StoreKey<Sample>("garbage")) == nil)
    }

    @Test func typeMismatchReturnsNil() throws {
        try store.set("a string", for: StoreKey<String>("mismatch"))
        #expect(store.get(StoreKey<Sample>("mismatch")) == nil)
    }

    @Test func nonDataValueReturnsNil() {
        defaults.set("plain string written by someone else", forKey: "foreign")
        #expect(store.get(StoreKey<String>("foreign")) == nil)
    }

    @Test func storesShareStateThroughSameDefaults() throws {
        let key = StoreKey<String>("shared")
        try store.set("from app", for: key)
        let other = SharedStore(defaults: UserDefaults(suiteName: suiteName)!)
        #expect(other.get(key) == "from app")
    }
}
