import Foundation
import Testing
@testable import OysterKit

private func summary(_ id: String, _ name: String? = nil) -> PearlSummary {
    PearlSummary(id: id, name: name ?? "Pearl \(id)")
}

@Suite final class PearlDiskStoreTests {
    private let temp = TemporaryDirectory()
    private let store: PearlDiskStore

    init() {
        store = PearlDiskStore(directory: temp.url)
    }

    private var root: URL { temp.url }
    private var pearlsDir: URL { root.appending(component: "Pearls") }

    private func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path())
    }

    @Test func emptyStoreReadsAsEmpty() {
        #expect(store.list().isEmpty)
        #expect(store.data(id: "p1", size: .small) == nil)
    }

    @Test func persistsAcrossInstances() throws {
        let fixture = try Fixture.decode(PearlData.self, "pearl-data.small.json")
        try store.replaceAll([summary("a"), summary(fixture.pearlId)])
        try store.saveData(fixture)

        let reopened = PearlDiskStore(directory: temp.url)
        #expect(reopened.list() == [summary("a"), summary(fixture.pearlId)])
        #expect(reopened.data(id: fixture.pearlId, size: .small) == fixture)
        #expect(reopened.data(id: fixture.pearlId, size: .medium) == nil)
        #expect(exists(pearlsDir.appending(component: "list.json")))
        #expect(exists(pearlsDir.appending(components: fixture.pearlId, "small.json")))
    }

    @Test func dataIsKeptPerSize() throws {
        for size in Size.allCases {
            try store.saveData(makePearlData("p1", size, value: size.rawValue))
        }
        try store.saveData(makePearlData("p1", .small, value: "newer"))

        #expect(store.data(id: "p1", size: .inline)?.output.value == "inline")
        #expect(store.data(id: "p1", size: .small)?.output.value == "newer")
        #expect(store.data(id: "p2", size: .small) == nil)
    }

    @Test func upsertRenamesInPlaceAndAppendsNew() throws {
        try store.replaceAll([summary("a"), summary("b"), summary("c")])

        try store.upsert(summary("b", "Renamed"))
        try store.upsert(summary("d"))

        #expect(store.list() == [summary("a"), summary("b", "Renamed"), summary("c"), summary("d")])
    }

    @Test func replaceAllPrunesDataOfRemovedPearls() throws {
        try store.replaceAll([summary("keep"), summary("drop")])
        try store.saveData(makePearlData("keep", .small))
        try store.saveData(makePearlData("drop", .small))
        try store.saveData(makePearlData("orphan", .medium))

        try store.replaceAll([summary("new"), summary("keep")])

        #expect(store.list() == [summary("new"), summary("keep")])
        #expect(store.data(id: "keep", size: .small) != nil)
        #expect(store.data(id: "drop", size: .small) == nil)
        #expect(!exists(pearlsDir.appending(component: "drop")))
        #expect(!exists(pearlsDir.appending(component: "orphan")))
    }

    @Test func removeDeletesEntryAndData() throws {
        try store.replaceAll([summary("a"), summary("b")])
        try store.saveData(makePearlData("a", .small))
        try store.saveData(makePearlData("b", .small))

        try store.remove(id: "a")
        try store.remove(id: "never-stored")

        #expect(store.list() == [summary("b")])
        #expect(store.data(id: "a", size: .small) == nil)
        #expect(!exists(pearlsDir.appending(component: "a")))
        #expect(store.data(id: "b", size: .small) != nil)
    }

    @Test func corruptFilesReadAsAbsentAndAreOverwritable() throws {
        try store.replaceAll([summary("a")])
        try store.saveData(makePearlData("a", .small))
        try Data("{ not json".utf8).write(to: pearlsDir.appending(component: "list.json"))
        try Data([0xFF, 0x00]).write(to: pearlsDir.appending(components: "a", "small.json"))

        #expect(store.list().isEmpty)
        #expect(store.data(id: "a", size: .small) == nil)

        try store.upsert(summary("b"))
        try store.saveData(makePearlData("a", .small))
        #expect(store.list() == [summary("b")])
        #expect(store.data(id: "a", size: .small) != nil)
    }

    @Test func dataFiledUnderWrongIdOrSizeReadsAsAbsent() throws {
        try FileManager.default.createDirectory(at: pearlsDir.appending(component: "a"), withIntermediateDirectories: true)
        let other = try ContractCoding.makeEncoder().encode(makePearlData("b", .medium))
        try other.write(to: pearlsDir.appending(components: "a", "small.json"))

        #expect(store.data(id: "a", size: .small) == nil)
    }

    @Test(arguments: ["", ".", "..", "../escape", "a/b", "/abs", ".hidden", "list.json", "x..y"])
    func unsafeIdsAreRejected(id: String) throws {
        try store.replaceAll([summary("a")])

        #expect(throws: PearlDiskStore.StoreError.invalidId(id)) { try self.store.upsert(summary(id)) }
        #expect(throws: PearlDiskStore.StoreError.invalidId(id)) { try self.store.saveData(makePearlData(id, .small)) }
        #expect(throws: PearlDiskStore.StoreError.invalidId(id)) { try self.store.remove(id: id) }
        #expect(throws: PearlDiskStore.StoreError.invalidId(id)) { try self.store.replaceAll([summary("b"), summary(id)]) }
        #expect(store.data(id: id, size: .small) == nil)

        #expect(store.list() == [summary("a")])
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path()) == ["Pearls"])
        #expect(try FileManager.default.contentsOfDirectory(atPath: pearlsDir.path()) == ["list.json"])
    }

    @Test func replaceAllKeepsUpsertsMadeAfterCheckpoint() throws {
        try store.replaceAll([summary("a"), summary("b")])
        try store.upsert(summary("before"))
        let checkpoint = store.checkpoint()
        try store.upsert(summary("new"))
        try store.upsert(summary("a", "Renamed"))
        try store.upsert(summary("deleted"))
        try store.remove(id: "deleted")

        try store.replaceAll([summary("a"), summary("b")], keepingUpsertsSince: checkpoint)

        #expect(store.list() == [summary("a", "Renamed"), summary("b"), summary("new")])
    }

    @Test func replaceAllWritesListEvenWhenPruningFails() throws {
        try store.replaceAll([summary("stuck")])
        try store.saveData(makePearlData("stuck", .small))
        let stuckDir = pearlsDir.appending(component: "stuck")
        // Without write permission on its directory, the data file (and so the directory) can't be deleted.
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: stuckDir.path())
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: stuckDir.path()) }

        try store.replaceAll([summary("other")])

        #expect(store.list() == [summary("other")])
        #expect(exists(stuckDir))
    }

    @Test func concurrentUpsertsAreAllKept() async throws {
        let store = self.store
        let ids = (0..<50).map { "p\($0)" }
        try await withThrowingTaskGroup(of: Void.self) { group in
            for id in ids {
                group.addTask { try store.upsert(summary(id)) }
            }
            try await group.waitForAll()
        }

        #expect(Set(store.list().map(\.id)) == Set(ids))
    }
}

@Suite final class PearlSyncTests {
    private let temp = TemporaryDirectory()

    @Test func syncMirrorsServerListAndDropsRemovedPearls() async throws {
        let body = try Fixture.data("pearls-list.json")
        let server = StubServer { _ in .json(200, body) }
        let disk = PearlDiskStore(directory: temp.url)
        let serverPearls = try Fixture.decode(PearlsListResponse.self, "pearls-list.json").pearls
        try disk.replaceAll([summary("deleted-on-server"), serverPearls[0]])
        try disk.saveData(makePearlData("deleted-on-server", .small))
        try disk.saveData(makePearlData(serverPearls[0].id, .small))

        try await PearlSync.sync(api: server.apiClient(), disk: disk)

        #expect(disk.list() == serverPearls)
        #expect(disk.data(id: "deleted-on-server", size: .small) == nil)
        #expect(disk.data(id: serverPearls[0].id, size: .small) != nil)
    }

    @Test func failedSyncLeavesDiskUntouched() async throws {
        let server = StubServer { _ in .json(503, Data()) }
        let disk = PearlDiskStore(directory: temp.url)
        try disk.replaceAll([summary("a")])
        try disk.saveData(makePearlData("a", .small))

        await #expect(throws: APIError.self) { try await PearlSync.sync(api: server.apiClient(), disk: disk) }

        #expect(disk.list() == [summary("a")])
        #expect(disk.data(id: "a", size: .small) != nil)
    }

    @Test func pearlSavedWhileSyncIsInFlightIsKept() async throws {
        let body = try Fixture.data("pearls-list.json")
        let serverPearls = try Fixture.decode(PearlsListResponse.self, "pearls-list.json").pearls
        let disk = PearlDiskStore(directory: temp.url)
        let justSaved = summary("pearl_saved_mid_sync", "Just saved")
        // The `saved` event lands after the server built its (older) list response.
        let server = StubServer { _ in
            try? PearlSync.recordSaved(justSaved, disk: disk)
            return .json(200, body)
        }

        try await PearlSync.sync(api: server.apiClient(), disk: disk)

        #expect(disk.list() == serverPearls + [justSaved])
    }

    @Test func pearlSavedBeforeSyncDefersToServer() async throws {
        let body = try Fixture.data("pearls-list.json")
        let serverPearls = try Fixture.decode(PearlsListResponse.self, "pearls-list.json").pearls
        let disk = PearlDiskStore(directory: temp.url)
        try PearlSync.recordSaved(summary("deleted-elsewhere"), disk: disk)
        let server = StubServer { _ in .json(200, body) }

        try await PearlSync.sync(api: server.apiClient(), disk: disk)

        #expect(disk.list() == serverPearls)
    }
}

@Suite final class ServerConfigTests {
    private let suiteName = "ServerConfigTests.\(UUID().uuidString)"
    private let defaults: UserDefaults

    init() {
        defaults = UserDefaults(suiteName: suiteName)!
    }

    deinit {
        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test func roundTripsThroughSharedStore() throws {
        let store = SharedStore(defaults: defaults)
        #expect(ServerConfig.load(from: store) == nil)

        let config = ServerConfig(baseURL: URL(string: "https://oyster.example.com/api")!, token: "tok")
        try config.save(to: store)

        #expect(ServerConfig.load(from: SharedStore(defaults: UserDefaults(suiteName: suiteName)!)) == config)
    }

    @Test func readsAConfigSavedBeforeTheContractCoder() throws {
        // Builds that predate `ContractCoding` in `SharedStore` wrote with a default `JSONEncoder`.
        let config = ServerConfig(baseURL: URL(string: "https://oyster.example.com/api")!, token: "tok")
        defaults.set(try JSONEncoder().encode(config), forKey: ServerConfig.storeKey.name)

        #expect(ServerConfig.load(from: SharedStore(defaults: defaults)) == config)
    }
}
