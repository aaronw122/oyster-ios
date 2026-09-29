import Foundation

/// Decides what the widget shows for a configured Pearl at one size.
///
/// Only Pearls in the on-device list count as chosen. A refresh fetches the
/// Pearl's data and saves it as the on-device last-good; when the fetch fails
/// the last-good is shown marked stale.
public struct PearlEntryLoader: Sendable {
    public typealias Fetch = @Sendable (_ pearlId: String, _ size: Size) async throws -> PearlData

    private let disk: PearlDiskStore?
    private let fetch: Fetch?

    /// - Parameters:
    ///   - disk: on-device store; `nil` when the App Group is unavailable.
    ///   - fetch: server fetch; `nil` when the app hasn't connected to a server.
    public init(disk: PearlDiskStore?, fetch: Fetch?) {
        self.disk = disk
        self.fetch = fetch
    }

    /// Fetches through `APIClient` when a server config is present.
    public init(disk: PearlDiskStore?, config: ServerConfig?, session: URLSession = .shared) {
        guard let config else {
            self.init(disk: disk, fetch: nil)
            return
        }
        let client = APIClient(config: config, session: session)
        self.init(disk: disk) { id, size in
            try await client.pearlData(id: id, size: size)
        }
    }

    /// The loader the widget extension uses: App Group disk and server config.
    public static func appGroup() -> PearlEntryLoader {
        PearlEntryLoader(
            disk: .appGroup,
            config: SharedStore.appGroup.flatMap(ServerConfig.load(from:)),
            session: widgetSession
        )
    }

    /// Short timeouts so a slow server still leaves time to commit the stale
    /// fallback within WidgetKit's refresh budget.
    private static let widgetSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 12
        configuration.timeoutIntervalForResource = 15
        return URLSession(configuration: configuration)
    }()

    /// Refreshes the Pearl's data for `size`.
    public func load(pearlId: String?, size: Size) async -> PearlWidgetContent {
        guard let disk else { return .openOyster }
        guard let pearlId, isSaved(pearlId, in: disk) else { return .choosePearl }
        guard let fetch else { return .openOyster }
        do {
            let data = try await fetch(pearlId, size)
            try? disk.saveData(data)
            return .pearl(data)
        } catch APIError.notFound {
            // Deleted on the server; the next library sync drops it from the device.
            return .choosePearl
        } catch APIError.unauthorized {
            return .openOyster
        } catch {
            guard var lastGood = disk.data(id: pearlId, size: size) else { return .openOyster }
            lastGood.stale = true
            return .pearl(lastGood)
        }
    }

    /// The on-device last-good for the Pearl at `size`, without touching the network.
    public func cached(pearlId: String?, size: Size) -> PearlData? {
        guard let disk, let pearlId, isSaved(pearlId, in: disk) else { return nil }
        return disk.data(id: pearlId, size: size)
    }

    private func isSaved(_ pearlId: String, in disk: PearlDiskStore) -> Bool {
        disk.list().contains { $0.id == pearlId }
    }
}

/// The widget's Pearl picker options. Reads only the on-device list; never the server.
public struct PearlPicker: Sendable {
    private let disk: PearlDiskStore?

    public init(disk: PearlDiskStore?) {
        self.disk = disk
    }

    /// Every saved Pearl, in library order.
    public func all() -> [PearlSummary] {
        disk?.list() ?? []
    }

    /// The saved Pearls among `ids`, in library order; unknown ids are dropped.
    public func pearls(ids: [String]) -> [PearlSummary] {
        let wanted = Set(ids)
        return all().filter { wanted.contains($0.id) }
    }

    /// Saved Pearls whose name contains `text` (case- and diacritic-insensitive).
    public func pearls(matching text: String) -> [PearlSummary] {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return all() }
        return all().filter { $0.name.localizedStandardContains(query) }
    }
}
