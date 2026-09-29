import SwiftUI
import Testing
@testable import OysterKit

/// ENSURE-3b: native layouts render max-length data without clipping.
///
/// Each shown string of `widget-output.max.<size>.json` (every field at its §2b
/// code-point budget) is measured at its ideal single-line width — full size,
/// before any `minimumScaleFactor` — and must fit the width its layout gives it
/// inside the canonical (smallest device) frame. The stacked content must also
/// fit the frame's height.
@MainActor
@Suite struct LayoutFitTests {
    @Test(arguments: Size.allCases)
    func maxFixtureFitsBudgets(size: Size) throws {
        // Guard: the fixture really is at the budget, or the fit proof is hollow.
        let output = try LayoutFixtures.max(size)
        #expect(SizeBudgets.fits(output, size: size).isEmpty)
        let budget = SizeBudgets[size]
        #expect(output.value.codePointCount == budget.value)
        if let limit = budget.subtitle { #expect(output.subtitle?.codePointCount == limit) }
        if let limits = budget.items {
            let items = try #require(output.items)
            #expect(items.count == limits.max)
            #expect(items.contains { $0.label.codePointCount == limits.label })
            #expect(items.contains { $0.value?.codePointCount == limits.value })
        }
    }

    @Test(arguments: Size.allCases)
    func everyStringSetsOnOneLineUnscaled(size: Size) throws {
        let output = try LayoutFixtures.max(size).projected(for: size)
        let spec = PearlLayoutSpec.spec(for: size)
        let width = spec.contentSize.width

        func measure(_ string: String, _ role: PearlLayoutSpec.Role) -> CGFloat {
            idealSize(of: spec.text(string, role)).width
        }

        switch size {
        case .inline:
            // Measured as drawn when stale: symbol + value.
            let line = idealSize(of: InlineLayout(output: output, spec: spec, stale: true)).width
            #expect(line <= width, "inline line \(line) > \(width)")
        case .rectangular, .small, .medium:
            let value = measure(output.value, .value) + PearlLayoutSpec.valueRowReserve
            #expect(value <= width, "value \(value) > \(width)")
            if let subtitle = output.subtitle {
                let measured = measure(subtitle, .subtitle)
                #expect(measured <= width, "subtitle \(measured) > \(width)")
            }
            for (index, item) in (output.items ?? []).enumerated() {
                let label = measure(item.label, .itemLabel)
                let value = item.value.map { measure($0, .itemValue) } ?? 0
                if spec.stacksItems {
                    #expect(label <= width, "items[\(index)].label \(label) > \(width)")
                    #expect(value <= width, "items[\(index)].value \(value) > \(width)")
                } else {
                    let row = label + spec.itemColumnGap + value
                    #expect(row <= width, "items[\(index)] row \(row) > \(width)")
                }
            }
        }
    }

    @Test(arguments: [Size.rectangular, .small, .medium])
    func contentFitsFrameHeight(size: Size) throws {
        let output = try LayoutFixtures.max(size).projected(for: size)
        let spec = PearlLayoutSpec.spec(for: size)
        let height = idealHeight(of: BlockLayout(output: output, spec: spec, stale: true), width: spec.contentSize.width)
        #expect(height <= spec.contentSize.height, "content \(height) > \(spec.contentSize.height)")
    }
}
