import SwiftUI

/// Fixed geometry and type for one size's native layout.
///
/// Every number here is chosen so that each string at its §2b budget (the
/// `widget-output.max.<size>.json` fixtures) sets on one line, unscaled, inside
/// the smallest iPhone widget of that family that iOS 17 supports (375×667 pt
/// screens, per the HIG widget dimension table). `LayoutFitTests` measures it.
///
/// Type is one face — SF Pro, condensed width — at fixed point sizes, so a
/// budget-sized string can never grow past the width it was measured at.
struct PearlLayoutSpec: Sendable {
    enum Role: CaseIterable, Sendable {
        case value
        case subtitle
        case itemLabel
        case itemValue
    }

    /// Canonical widget frame (smallest supported device).
    let frame: CGSize
    /// Insets the view applies itself; the widget host disables system content margins.
    let insets: EdgeInsets
    /// Space between the value and the subtitle.
    let headerSpacing: CGFloat
    /// Minimum space between the header block and the item list.
    let sectionSpacing: CGFloat
    /// Space between item entries.
    let itemSpacing: CGFloat
    /// Horizontal gap between an item's label and value when they share a row.
    let itemColumnGap: CGFloat
    /// Items stack label over value (`true`) or share one row (`false`).
    let stacksItems: Bool
    let fontSizes: [Role: CGFloat]

    static let staleDotDiameter: CGFloat = 5
    static let staleDotGap: CGFloat = 4

    /// Horizontal room the stale dot, which trails the value, takes from it.
    static var valueRowReserve: CGFloat { staleDotDiameter + staleDotGap }

    var contentSize: CGSize {
        CGSize(
            width: frame.width - insets.leading - insets.trailing,
            height: frame.height - insets.top - insets.bottom
        )
    }

    func font(_ role: Role) -> Font {
        let size = fontSizes[role] ?? fontSizes[.value]!
        switch role {
        case .value:
            return .system(size: size, weight: .semibold).width(.condensed).monospacedDigit()
        case .itemValue:
            return .system(size: size, weight: .medium).width(.condensed).monospacedDigit()
        case .subtitle, .itemLabel:
            return .system(size: size, weight: .regular).width(.condensed).monospacedDigit()
        }
    }

    /// `string` set in the role's type, single line. The minimum scale factor is
    /// a safety net for pathological glyphs only; budget-sized fixture strings fit
    /// at full size (proved by `LayoutFitTests`).
    func text(_ string: String, _ role: Role) -> some View {
        Text(verbatim: string)
            .font(font(role))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
    }

    static func spec(for size: Size) -> PearlLayoutSpec {
        switch size {
        case .inline: inline
        case .rectangular: rectangular
        case .small: small
        case .medium: medium
        }
    }

    // Lock Screen inline: WidgetKit sets the type itself; 17 pt semibold is the
    // size we draw it at in previews and the upper bound we measure against.
    static let inline = PearlLayoutSpec(
        frame: CGSize(width: 225, height: 26),
        insets: EdgeInsets(),
        headerSpacing: 0,
        sectionSpacing: 0,
        itemSpacing: 0,
        itemColumnGap: 0,
        stacksItems: false,
        fontSizes: [.value: 17]
    )

    static let rectangular = PearlLayoutSpec(
        frame: CGSize(width: 153, height: 68),
        insets: EdgeInsets(),
        headerSpacing: 1,
        sectionSpacing: 0,
        itemSpacing: 0,
        itemColumnGap: 0,
        stacksItems: false,
        fontSizes: [.value: 20, .subtitle: 14]
    )

    static let small = PearlLayoutSpec(
        frame: CGSize(width: 148, height: 148),
        insets: EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12),
        headerSpacing: 1,
        sectionSpacing: 8,
        itemSpacing: 5,
        itemColumnGap: 0,
        stacksItems: true,
        fontSizes: [.value: 15, .subtitle: 11, .itemLabel: 11, .itemValue: 13]
    )

    static let medium = PearlLayoutSpec(
        frame: CGSize(width: 321, height: 148),
        insets: EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14),
        headerSpacing: 1,
        sectionSpacing: 6,
        itemSpacing: 1,
        itemColumnGap: 12,
        stacksItems: false,
        fontSizes: [.value: 20, .subtitle: 12, .itemLabel: 12, .itemValue: 12]
    )
}
