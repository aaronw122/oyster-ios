import SwiftUI
import Testing
@testable import OysterKit

/// ENSURE-3b: native layouts render budget-length data without truncation, in
/// the smallest frame of each family (`PearlLayoutSpec`).
///
/// - The max fixtures (`widget-output.max.<size>.json`, realistic strings at the
///   §2b budgets) set on one line at full size — no scaling.
/// - Any string at its budget in the widest glyphs (`WideGlyph`) sets on one
///   line at `PearlLayoutSpec.minimumScale`, so text shrinks rather than
///   truncating. Inline is the exception: WidgetKit draws it in the system font
///   without scaling, so there the widest value must fit at full size — true for
///   W/M, not for 12 emoji (a known contract gap, recorded below).
///
/// Widths are ideal single-line widths of the exact styled `Text`, compared with
/// the width its layout allots it. Stacked content must also fit the height.
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

    @Test(arguments: Size.allCases, WideGlyph.allCases)
    func wideGlyphOutputIsAtBudget(size: Size, glyph: WideGlyph) {
        let output = glyph.output(for: size)
        #expect(SizeBudgets.fits(output, size: size).isEmpty)
        // One code point past the budget must be rejected, so this is the worst case.
        #expect(!SizeBudgets.fits(WidgetOutput(value: output.value + glyph.rawValue), size: size).isEmpty)
    }

    @Test(arguments: Size.allCases)
    func maxFixtureSetsUnscaled(size: Size) throws {
        let output = try LayoutFixtures.max(size).projected(for: size)
        let spec = PearlLayoutSpec.spec(for: size)
        if size == .inline {
            // With the stale symbol shown beside it.
            let line = idealSize(of: InlineLayout(output: output, spec: spec, stale: true)).width
            #expect(line <= spec.contentSize.width, "inline line \(line) > \(spec.contentSize.width)")
        } else {
            assertFits(output, spec: spec, scale: 1)
        }
    }

    @Test(arguments: Size.allCases, WideGlyph.allCases)
    func wideGlyphsShrinkInsteadOfTruncating(size: Size, glyph: WideGlyph) {
        let output = glyph.output(for: size)
        let spec = PearlLayoutSpec.spec(for: size)
        if size == .inline {
            // WidgetKit ignores scaling here; the stale symbol drops out when it doesn't fit.
            let value = measure(output.value, .value, spec: spec, scale: 1)
            let fits = { #expect(value <= spec.contentSize.width, "inline value \(value) > \(spec.contentSize.width)") }
            if glyph == .emoji {
                // 12 emoji ≈ 276 pt in 17 pt system type; the line is 225 pt and the
                // client can't shrink inline text. Needs the server's inline budget to
                // weigh emoji wider than one code point.
                withKnownIssue("12-emoji inline value exceeds the Lock Screen inline line", fits)
            } else {
                fits()
            }
        } else {
            assertFits(output, spec: spec, scale: PearlLayoutSpec.minimumScale)
        }
    }

    @Test(arguments: [Size.rectangular, .small, .medium])
    func contentFitsFrameHeight(size: Size) throws {
        let spec = PearlLayoutSpec.spec(for: size)
        let outputs = try [LayoutFixtures.max(size)] + WideGlyph.allCases.map { $0.output(for: size) }
        for output in outputs {
            let block = BlockLayout(output: output.projected(for: size), spec: spec, stale: true)
            let height = idealHeight(of: block, width: spec.contentSize.width)
            #expect(height <= spec.contentSize.height, "\(output.value): content \(height) > \(spec.contentSize.height)")
        }
    }

    @Test func itemColumnsShrinkBothColumnsByTheSameFactor() {
        #expect(ItemColumns.columnWidths(ideal: [100, 50], available: 200, gap: 10) == [100, 50])
        let widths = ItemColumns.columnWidths(ideal: [200, 100], available: 160, gap: 10)
        #expect(widths == [100, 50])
        #expect(ItemColumns.columnWidths(ideal: [300], available: 150, gap: 10) == [150])
    }

    // MARK: - Measurement

    /// Ideal single-line width of `string` in `role`'s type at `scale`.
    private func measure(_ string: String, _ role: PearlLayoutSpec.Role, spec: PearlLayoutSpec, scale: CGFloat) -> CGFloat {
        idealSize(of: Text(verbatim: string).font(spec.font(role, scale: scale)).lineLimit(1)).width
    }

    /// Every string of a block-layout `output` fits its allotted width when set at `scale`.
    private func assertFits(_ output: WidgetOutput, spec: PearlLayoutSpec, scale: CGFloat,
                            sourceLocation: SourceLocation = #_sourceLocation) {
        let width = spec.contentSize.width
        func check(_ measured: CGFloat, _ available: CGFloat, _ what: String) {
            #expect(measured <= available, "\(what) \(measured) > \(available) at scale \(scale)", sourceLocation: sourceLocation)
        }

        check(measure(output.value, .value, spec: spec, scale: scale), width - PearlLayoutSpec.valueRowReserve, "value")
        if let subtitle = output.subtitle {
            check(measure(subtitle, .subtitle, spec: spec, scale: scale), width, "subtitle")
        }
        for (index, item) in (output.items ?? []).enumerated() {
            let texts = [(item.label, PearlLayoutSpec.Role.itemLabel)] + (item.value.map { [($0, .itemValue)] } ?? [])
            let allotted: [CGFloat] = if spec.stacksItems {
                texts.map { _ in width }
            } else {
                // The row layout splits the width from the columns' full-size ideal widths.
                ItemColumns.columnWidths(
                    ideal: texts.map { idealSize(of: spec.text($0.0, $0.1)).width },
                    available: width,
                    gap: spec.itemColumnGap
                )
            }
            for ((string, role), available) in zip(texts, allotted) {
                check(measure(string, role, spec: spec, scale: scale), available, "items[\(index)] \(role)")
            }
        }
    }
}
