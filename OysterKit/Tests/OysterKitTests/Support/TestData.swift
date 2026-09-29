import Foundation
@testable import OysterKit

/// A unique directory under the temp dir, removed when this object is released.
final class TemporaryDirectory: Sendable {
    let url = FileManager.default.temporaryDirectory
        .appending(component: "OysterKitTests-\(UUID().uuidString)", directoryHint: .isDirectory)

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}

func makePearlData(_ id: String, _ size: Size, value: String = "v", stale: Bool = false) -> PearlData {
    PearlData(
        pearlId: id,
        version: 1,
        size: size,
        output: WidgetOutput(value: value),
        updatedAt: Date(timeIntervalSince1970: 1_790_000_000),
        stale: stale
    )
}
