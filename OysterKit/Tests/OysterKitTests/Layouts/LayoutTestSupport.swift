import SwiftUI
import UIKit
@testable import OysterKit

/// Sample outputs used by the layout tests, keyed by the size they target.
enum LayoutFixtures {
    /// `pearl-data.<size>.json` — typical data.
    static func normal(_ size: Size) throws -> PearlData {
        try Fixture.decode(PearlData.self, "pearl-data.\(size.rawValue).json")
    }

    /// `widget-output.max.<size>.json` — every shown string at its §2b budget.
    static func max(_ size: Size) throws -> WidgetOutput {
        try Fixture.decode(WidgetOutput.self, "widget-output.max.\(size.rawValue).json")
    }
}

/// The widest glyphs per code point: all-caps W and M, and a single-code-point
/// emoji (emoji advance ≈ 1.08 em, wider than any Latin letter).
enum WideGlyph: String, CaseIterable, Sendable {
    case w = "W"
    case m = "M"
    case emoji = "🚲"

    /// Every field `size` shows filled with this glyph to exactly its §2b budget,
    /// and the item list at its cap.
    func output(for size: Size) -> WidgetOutput {
        let budget = SizeBudgets[size]
        func fill(_ count: Int) -> String { String(repeating: rawValue, count: count) }
        return WidgetOutput(
            value: fill(budget.value),
            subtitle: budget.subtitle.map(fill),
            items: budget.items.map { limits in
                Array(repeating: WidgetOutput.Item(label: fill(limits.label), value: fill(limits.value)), count: limits.max)
            }
        )
    }
}

/// A Pearl view as a chat preview card shows it: the canonical frame over a
/// plain surface, clipped like a widget.
@MainActor
func previewCard(_ output: WidgetOutput, size: Size, stale: Bool = false) -> some View {
    let frame = PearlWidgetView.previewFrame(for: size)
    let isHomeScreen = size == .small || size == .medium
    return PearlWidgetView(output: output, size: size, stale: stale)
        .frame(width: frame.width, height: frame.height)
        .background(Color(uiColor: isHomeScreen ? .systemBackground : .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: isHomeScreen ? 22 : 12, style: .continuous))
}

/// Ideal size of `view` under an unconstrained proposal.
@MainActor
func idealSize(of view: some View) -> CGSize {
    let host = UIHostingController(rootView: view.fixedSize())
    return host.sizeThatFits(in: CGSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude))
}

/// Ideal height of `view` laid out at a fixed `width`.
@MainActor
func idealHeight(of view: some View, width: CGFloat) -> CGFloat {
    let host = UIHostingController(rootView: view.frame(width: width).fixedSize(horizontal: false, vertical: true))
    return host.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude)).height
}
