import SnapshotTesting
import SwiftUI
import Testing
import WidgetKit
@testable import OysterKit

@MainActor
@Suite struct PearlWidgetViewSnapshotTests {
    private static let schemes: [(name: String, style: UIUserInterfaceStyle)] = [("light", .light), ("dark", .dark)]

    private func snapshot(_ output: WidgetOutput, size: Size, stale: Bool = false, named name: String,
                          fileID: StaticString = #fileID, filePath: StaticString = #filePath,
                          testName: String = #function, line: UInt = #line, column: UInt = #column) {
        let frame = PearlWidgetView.previewFrame(for: size)
        for scheme in Self.schemes {
            assertSnapshot(
                of: previewCard(output, size: size, stale: stale),
                as: .image(
                    precision: 0.99,
                    perceptualPrecision: 0.98,
                    layout: .fixed(width: frame.width, height: frame.height),
                    traits: UITraitCollection(userInterfaceStyle: scheme.style)
                ),
                named: "\(name).\(scheme.name)",
                fileID: fileID, file: filePath, testName: testName, line: line, column: column
            )
        }
    }

    @Test(arguments: Size.allCases)
    func normal(size: Size) throws {
        let data = try LayoutFixtures.normal(size)
        snapshot(data.output, size: size, named: size.rawValue)
    }

    @Test(arguments: Size.allCases)
    func maxLength(size: Size) throws {
        snapshot(try LayoutFixtures.max(size), size: size, named: size.rawValue)
    }

    @Test func staleSmall() throws {
        let data = try Fixture.decode(PearlData.self, "pearl-data.stale.json")
        #expect(data.stale)
        snapshot(data.output, size: data.size, stale: data.stale, named: data.size.rawValue)
    }
}

@MainActor
@Suite struct PearlWidgetViewProjectionTests {
    private func render(_ output: WidgetOutput, size: Size) throws -> Data {
        let renderer = ImageRenderer(content: previewCard(output, size: size))
        renderer.scale = 2
        return try #require(renderer.uiImage?.pngData())
    }

    /// Raw transform output (more than any size shows) must render exactly like
    /// the server's projection for that size.
    private let raw = WidgetOutput(
        value: "W 21st & 6th",
        subtitle: "5 docks · 0.2 mi",
        items: (1...7).map { WidgetOutput.Item(label: "Station \($0)", value: "\($0) docks") }
    )

    @Test func inlineRendersOnlyTheValue() throws {
        #expect(try render(raw, size: .inline) == render(WidgetOutput(value: raw.value), size: .inline))
        #expect(try render(raw, size: .inline) != render(WidgetOutput(value: "W 22nd & 8th"), size: .inline))
    }

    @Test func rectangularDropsItems() throws {
        let expected = WidgetOutput(value: raw.value, subtitle: raw.subtitle)
        #expect(try render(raw, size: .rectangular) == render(expected, size: .rectangular))
    }

    @Test(arguments: [(Size.small, 2), (.medium, 5)])
    func itemsAreCappedPerSize(size: Size, cap: Int) throws {
        let expected = WidgetOutput(value: raw.value, subtitle: raw.subtitle, items: Array(raw.items!.prefix(cap)))
        #expect(try render(raw, size: size) == render(expected, size: size))
        let oneFewer = WidgetOutput(value: raw.value, subtitle: raw.subtitle, items: Array(raw.items!.prefix(cap - 1)))
        #expect(try render(raw, size: size) != render(oneFewer, size: size))
    }
}

@Suite struct SizeWidgetFamilyTests {
    @Test(arguments: Size.allCases)
    func roundTrips(size: Size) {
        #expect(Size(family: size.widgetFamily) == size)
    }

    @Test func unsupportedFamiliesHaveNoSize() {
        #expect(Size(family: .systemLarge) == nil)
        #expect(Size(family: .accessoryCircular) == nil)
    }
}
