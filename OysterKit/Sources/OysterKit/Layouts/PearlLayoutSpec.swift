import SwiftUI

/// Fixed geometry and type for one size's native layout.
///
/// Frames are the smallest iPhone widget of each family iOS 17 supports, per
/// the HIG widget dimension table: 141×141 / 292×141 for Home Screen (Display
/// Zoom on 320-pt-wide screens) and 153×68 / 225×26 for the Lock Screen
/// (375×667 screens). `LayoutFitTests` proves two things in those frames:
/// - typical worst-case data (`widget-output.max.<size>.json`, every field at its
///   §2b budget) sets on one line at full size, unscaled;
/// - any string at its budget — including the widest glyphs per code point
///   (single-code-point emoji, all-caps W/M) — sets on one line at no smaller
///   than `minimumScale`, so text shrinks instead of truncating.
///
/// Type is one face — SF Pro — at fixed point sizes, so a budget-sized string
/// can never grow past the width it was measured at.
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
    /// SF Pro condensed (`true`) or standard width (`false`).
    let condensed: Bool
    let fontSizes: [Role: CGFloat]

    /// Smallest scale any text may shrink to before it would truncate. Only
    /// pathological strings ever need it: a budget's worth of emoji (≈1.45 em
    /// each, whole-point advances) needs 0.27 for the small subtitle (28 in
    /// 121 pt). Legible it isn't, but it is never cut off.
    static let minimumScale: CGFloat = 0.25

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

    /// The role's type, optionally scaled (the tests measure at `minimumScale`).
    func font(_ role: Role, scale: CGFloat = 1) -> Font {
        let size = (fontSizes[role] ?? fontSizes[.value]!) * scale
        let weight: Font.Weight = switch role {
        case .value: .semibold
        case .itemValue: .medium
        case .subtitle, .itemLabel: .regular
        }
        let font = Font.system(size: size, weight: weight)
        return (condensed ? font.width(.condensed) : font).monospacedDigit()
    }

    /// `string` set in the role's type on one line, shrinking down to
    /// `minimumScale` when its width is short.
    func text(_ string: String, _ role: Role) -> some View {
        Text(verbatim: string)
            .font(font(role))
            .lineLimit(1)
            .minimumScaleFactor(Self.minimumScale)
    }

    static func spec(for size: Size) -> PearlLayoutSpec {
        switch size {
        case .inline: inline
        case .rectangular: rectangular
        case .small: small
        case .medium: medium
        }
    }

    // Lock Screen inline: WidgetKit draws it in the system font and ignores
    // font and scale modifiers. We draw previews in, and measure against, SF Pro
    // standard width 17 pt semibold — [INFERENCE] the Lock Screen date-line type.
    static let inline = PearlLayoutSpec(
        frame: CGSize(width: 225, height: 26),
        insets: EdgeInsets(),
        headerSpacing: 0,
        sectionSpacing: 0,
        itemSpacing: 0,
        itemColumnGap: 0,
        stacksItems: false,
        condensed: false,
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
        condensed: true,
        fontSizes: [.value: 20, .subtitle: 14]
    )

    static let small = PearlLayoutSpec(
        frame: CGSize(width: 141, height: 141),
        insets: EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10),
        headerSpacing: 1,
        sectionSpacing: 8,
        itemSpacing: 5,
        itemColumnGap: 0,
        stacksItems: true,
        condensed: true,
        fontSizes: [.value: 15, .subtitle: 11, .itemLabel: 11, .itemValue: 13]
    )

    static let medium = PearlLayoutSpec(
        frame: CGSize(width: 292, height: 141),
        insets: EdgeInsets(top: 11, leading: 14, bottom: 11, trailing: 14),
        headerSpacing: 1,
        sectionSpacing: 4,
        itemSpacing: 0,
        itemColumnGap: 12,
        stacksItems: false,
        condensed: true,
        fontSizes: [.value: 20, .subtitle: 12, .itemLabel: 12, .itemValue: 12]
    )
}
