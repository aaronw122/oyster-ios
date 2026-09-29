import Foundation
import os

/// On-device storage for the saved-Pearl list and each Pearl's last-good
/// `PearlData` per size, shared by the app and the widget extension.
///
/// Layout under `directory`:
/// - `Pearls/list.json` — `[PearlSummary]`, in library order
/// - `Pearls/<id>/<size>.json` — `PearlData`
///
/// Every write is atomic (write-then-rename), so a reader in another process
/// sees either the old file or the new one. Operations within one process are
/// serialized. Missing or corrupt files read as absent; reads never throw.
public final class PearlDiskStore: Sendable {
    public enum StoreError: Error, Equatable {
        /// The id can't safely name a directory (empty, contains `/` or `..`, …).
        case invalidId(String)
    }

    public let directory: URL
    private let lock = OSAllocatedUnfairLock()

    private static let listFileName = "list.json"

    public init(directory: URL) {
        self.directory = directory
    }

    private static let sharedAppGroup: PearlDiskStore? = AppGroup.containerURL.map(PearlDiskStore.init(directory:))

    /// The store in the App Group container; `nil` without the entitlement.
    /// One instance per process, so all in-process callers share its lock.
    public static var appGroup: PearlDiskStore? { sharedAppGroup }

    // MARK: - List

    /// Saved Pearls in library order; empty when none are stored or the file is unreadable.
    public func list() -> [PearlSummary] {
        lock.withLock { readList() }
    }

    /// Replaces the list and deletes stored data for every Pearl not in `pearls`.
    public func replaceAll(_ pearls: [PearlSummary]) throws {
        for pearl in pearls { try Self.validate(pearl.id) }
        try lock.withLock {
            try writeList(pearls)
            try prune(keeping: Set(pearls.map(\.id)))
        }
    }

    /// Updates the name of a stored Pearl in place, or appends a new one.
    public func upsert(_ pearl: PearlSummary) throws {
        try Self.validate(pearl.id)
        try lock.withLock {
            var pearls = readList()
            if let index = pearls.firstIndex(where: { $0.id == pearl.id }) {
                pearls[index] = pearl
            } else {
                pearls.append(pearl)
            }
            try writeList(pearls)
        }
    }

    /// Removes the Pearl from the list and deletes its stored data.
    public func remove(id: String) throws {
        try Self.validate(id)
        try lock.withLock {
            try writeList(readList().filter { $0.id != id })
            try removeItemIfPresent(pearlDirectory(id))
        }
    }

    // MARK: - Data

    /// The stored data for that Pearl and size, or `nil` if absent, unreadable, or the id is invalid.
    public func data(id: String, size: Size) -> PearlData? {
        guard (try? Self.validate(id)) != nil else { return nil }
        return lock.withLock {
            guard let bytes = try? Data(contentsOf: dataFile(id: id, size: size)),
                  let data = try? ContractCoding.makeDecoder().decode(PearlData.self, from: bytes),
                  data.pearlId == id, data.size == size
            else { return nil }
            return data
        }
    }

    /// Stores `data` as the last-good value for its Pearl and size.
    public func saveData(_ data: PearlData) throws {
        try Self.validate(data.pearlId)
        let bytes = try ContractCoding.makeEncoder().encode(data)
        try lock.withLock {
            try write(bytes, to: dataFile(id: data.pearlId, size: data.size))
        }
    }

    // MARK: - Files (call with the lock held)

    private var pearlsDirectory: URL {
        directory.appending(component: "Pearls", directoryHint: .isDirectory)
    }

    private var listFile: URL {
        pearlsDirectory.appending(component: Self.listFileName, directoryHint: .notDirectory)
    }

    private func pearlDirectory(_ id: String) -> URL {
        pearlsDirectory.appending(component: id, directoryHint: .isDirectory)
    }

    private func dataFile(id: String, size: Size) -> URL {
        pearlDirectory(id).appending(component: "\(size.rawValue).json", directoryHint: .notDirectory)
    }

    private func readList() -> [PearlSummary] {
        guard let bytes = try? Data(contentsOf: listFile),
              let pearls = try? ContractCoding.makeDecoder().decode([PearlSummary].self, from: bytes)
        else { return [] }
        return pearls
    }

    private func writeList(_ pearls: [PearlSummary]) throws {
        try write(ContractCoding.makeEncoder().encode(pearls), to: listFile)
    }

    private func write(_ bytes: Data, to file: URL) throws {
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try bytes.write(to: file, options: .atomic)
    }

    /// Deletes every Pearl data directory whose id is not in `ids`.
    private func prune(keeping ids: Set<String>) throws {
        let entries: [URL]
        do {
            entries = try FileManager.default.contentsOfDirectory(
                at: pearlsDirectory,
                includingPropertiesForKeys: [.isDirectoryKey]
            )
        } catch CocoaError.fileReadNoSuchFile {
            return
        }
        for entry in entries where entry.lastPathComponent != Self.listFileName {
            let isDirectory = (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isDirectory, !ids.contains(entry.lastPathComponent) {
                try removeItemIfPresent(entry)
            }
        }
    }

    private func removeItemIfPresent(_ url: URL) throws {
        do {
            try FileManager.default.removeItem(at: url)
        } catch CocoaError.fileNoSuchFile {
            return
        }
    }

    /// Ids name directories, so reject anything that could escape `Pearls/`,
    /// hide itself, or collide with `list.json`.
    private static func validate(_ id: String) throws {
        let unsafe = id.isEmpty
            || id.contains("/")
            || id.contains("\0")
            || id.contains("..")
            || id.hasPrefix(".")
            || id == listFileName
        if unsafe { throw StoreError.invalidId(id) }
    }
}
