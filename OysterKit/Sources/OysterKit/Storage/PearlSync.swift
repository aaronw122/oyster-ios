#if canImport(WidgetKit)
import WidgetKit
#endif

/// Keeps the on-device Pearl list in step with the server and tells WidgetKit
/// when it changes, so the widget's Pearl picker (which reads only the disk
/// list) offers what the user has saved.
public enum PearlSync {
    /// `GET /pearls` → replace the on-device list (dropping data of removed
    /// Pearls) → reload widget timelines.
    public static func sync(api: APIClient, disk: PearlDiskStore) async throws {
        let pearls = try await api.listPearls()
        try disk.replaceAll(pearls)
        reloadWidgets()
    }

    /// Records a Pearl the agent just saved (the chat `saved` event) without
    /// waiting for the next full sync.
    public static func recordSaved(_ summary: PearlSummary, disk: PearlDiskStore) throws {
        try disk.upsert(summary)
        reloadWidgets()
    }

    private static func reloadWidgets() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}
