import Foundation
import os
import Testing
@testable import OysterKit

private let pearlId = "pearl_01J8ZQ4K7M3CITIBIKE"

private func freshData(_ size: Size, value: String = "fresh", stale: Bool = false) -> PearlData {
    PearlData(
        pearlId: pearlId,
        version: 3,
        size: size,
        output: WidgetOutput(value: value),
        updatedAt: Date(timeIntervalSince1970: 1_790_000_000),
        stale: stale
    )
}

/// Any request on a session this protocol is installed in is recorded as a test failure.
final class NetworkTripwire: URLProtocol, @unchecked Sendable {
    static let hits = OSAllocatedUnfairLock(initialState: [URL]())

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        if let url = request.url { Self.hits.withLock { $0.append(url) } }
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }

    override func stopLoading() {}

    /// A session whose every request trips the wire.
    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [NetworkTripwire.self]
        return URLSession(configuration: configuration)
    }
}

@Suite(.serialized) final class PearlWidgetTests {
    private let root = FileManager.default.temporaryDirectory
        .appending(component: "PearlWidgetTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    private let disk: PearlDiskStore

    init() throws {
        disk = PearlDiskStore(directory: root)
        try disk.replaceAll([
            PearlSummary(id: "pearl_other", name: "Morning train"),
            PearlSummary(id: pearlId, name: "Citi Bike near work"),
        ])
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    private func unexpectedServer() -> StubServer {
        StubServer { request in
            Issue.record("unexpected request to \(request.url?.absoluteString ?? "?")")
            return .json(500, Data())
        }
    }

    // MARK: - Loader

    @Test func chosenPearlFetchesAndSavesToDisk() async throws {
        let body = try Fixture.data("pearl-data.small.json")
        let server = StubServer(basePath: "/api") { _ in .json(200, body) }
        let loader = PearlEntryLoader(
            disk: disk,
            config: ServerConfig(baseURL: server.baseURL, token: "tok"),
            session: server.session
        )

        let content = await loader.load(pearlId: pearlId, size: .small)

        let expected = try Fixture.decode(PearlData.self, "pearl-data.small.json")
        #expect(content == .pearl(expected))
        #expect(!content.stale)
        #expect(disk.data(id: pearlId, size: .small) == expected)
        #expect(server.requests.map { $0.url?.path() } == ["/api/pearls/\(pearlId)/data"])
    }

    @Test func serverStaleFlagIsShown() async throws {
        let loader = PearlEntryLoader(disk: disk) { _, size in freshData(size, stale: true) }
        #expect(await loader.load(pearlId: pearlId, size: .medium).stale)
    }

    @Test func networkFailureFallsBackToDiskMarkedStale() async throws {
        try disk.saveData(freshData(.rectangular, value: "last good"))
        let server = StubServer { _ in .json(503, Data()) }
        let loader = PearlEntryLoader(
            disk: disk,
            config: ServerConfig(baseURL: server.baseURL, token: "tok"),
            session: server.session
        )

        let content = await loader.load(pearlId: pearlId, size: .rectangular)

        #expect(content == .pearl(freshData(.rectangular, value: "last good", stale: true)))
        #expect(content.stale)
        #expect(content.output(for: .rectangular).value == "last good")
    }

    @Test func pearlDeletedOnServerAsksToChooseEvenWithDiskData() async throws {
        try disk.saveData(freshData(.small))
        let server = StubServer { _ in .json(404, Data()) }
        let loader = PearlEntryLoader(
            disk: disk,
            config: ServerConfig(baseURL: server.baseURL, token: "tok"),
            session: server.session
        )
        #expect(await loader.load(pearlId: pearlId, size: .small) == .choosePearl)
    }

    @Test func revokedTokenOpensOysterEvenWithDiskData() async throws {
        try disk.saveData(freshData(.small))
        let server = StubServer { _ in .json(401, Data()) }
        let loader = PearlEntryLoader(
            disk: disk,
            config: ServerConfig(baseURL: server.baseURL, token: "tok"),
            session: server.session
        )
        #expect(await loader.load(pearlId: pearlId, size: .small) == .openOyster)
    }

    @Test func transportFailureWithoutDiskDataOpensOyster() async {
        let loader = PearlEntryLoader(disk: disk) { _, _ in throw APIError.transport(URLError(.notConnectedToInternet)) }
        // Last-good for another size doesn't stand in for this one.
        try? disk.saveData(freshData(.medium))
        #expect(await loader.load(pearlId: pearlId, size: .small) == .openOyster)
    }

    @Test func missingServerConfigOpensOysterWithoutFetching() async throws {
        try disk.saveData(freshData(.small))
        let loader = PearlEntryLoader(disk: disk, config: nil)
        #expect(await loader.load(pearlId: pearlId, size: .small) == .openOyster)
    }

    @Test func noPearlChosenAsksToChooseWithoutFetching() async {
        let server = unexpectedServer()
        let loader = PearlEntryLoader(
            disk: disk,
            config: ServerConfig(baseURL: server.baseURL, token: "tok"),
            session: server.session
        )
        #expect(await loader.load(pearlId: nil, size: .inline) == .choosePearl)
        #expect(server.requests.isEmpty)
    }

    @Test func pearlRemovedFromDeviceAsksToChooseWithoutFetching() async throws {
        try disk.saveData(freshData(.small))
        try disk.remove(id: pearlId)
        let server = unexpectedServer()
        let loader = PearlEntryLoader(
            disk: disk,
            config: ServerConfig(baseURL: server.baseURL, token: "tok"),
            session: server.session
        )
        #expect(await loader.load(pearlId: pearlId, size: .small) == .choosePearl)
        #expect(loader.cached(pearlId: pearlId, size: .small) == nil)
        #expect(server.requests.isEmpty)
    }

    @Test func cachedReadsDiskOnly() throws {
        try disk.saveData(freshData(.small, value: "on disk"))
        let loader = PearlEntryLoader(
            disk: disk,
            config: ServerConfig(baseURL: URL(string: "https://oyster.invalid")!, token: "tok"),
            session: NetworkTripwire.session()
        )
        #expect(loader.cached(pearlId: pearlId, size: .small)?.output.value == "on disk")
        #expect(loader.cached(pearlId: pearlId, size: .medium) == nil)
        #expect(loader.cached(pearlId: nil, size: .small) == nil)
    }

    // MARK: - Picker

    @Test func pickerListsExactlyTheDiskListAndNeverTouchesTheNetwork() {
        URLProtocol.registerClass(NetworkTripwire.self)
        defer { URLProtocol.unregisterClass(NetworkTripwire.self) }
        NetworkTripwire.hits.withLock { $0.removeAll() }

        let picker = PearlPicker(disk: disk)

        #expect(picker.all() == disk.list())
        #expect(picker.pearls(ids: [pearlId, "pearl_gone"]) == [PearlSummary(id: pearlId, name: "Citi Bike near work")])
        #expect(picker.pearls(ids: [pearlId, "pearl_other"]).map(\.id) == ["pearl_other", pearlId])
        #expect(picker.pearls(matching: "citi").map(\.id) == [pearlId])
        #expect(picker.pearls(matching: "  ").map(\.id) == ["pearl_other", pearlId])
        #expect(NetworkTripwire.hits.withLock { $0 }.isEmpty)
    }

    @Test func pickerIsEmptyWithoutDisk() {
        #expect(PearlPicker(disk: nil).all().isEmpty)
        #expect(PearlPicker(disk: nil).pearls(ids: [pearlId]).isEmpty)
    }

    // MARK: - Rendered text

    @Test(arguments: Size.allCases)
    func promptsAndSampleFitEverySize(size: Size) {
        for output in [
            PearlWidgetContent.choosePearl.output(for: size),
            PearlWidgetContent.openOyster.output(for: size),
            PearlWidgetContent.sample,
        ] {
            #expect(SizeBudgets.fits(output, size: size).isEmpty, "\(output.value) at \(size)")
        }
    }
}
