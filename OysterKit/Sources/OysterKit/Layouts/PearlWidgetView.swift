import SwiftUI
import WidgetKit

/// The native rendering of a Pearl's `WidgetOutput` at one size — shared by the
/// widget extension and the chat preview cards so both show exactly the same thing.
///
/// No title (§2b): only the output. The view projects `output` for `size`
/// itself (same rules as the server), so callers may pass a raw transform
/// output. It fills the frame it is given and owns its insets; the widget
/// configuration must use `.contentMarginsDisabled()`, and preview cards should
/// size it with `previewFrame(for:)`.
public struct PearlWidgetView: View {
    let output: WidgetOutput
    let size: Size
    let stale: Bool

    public init(output: WidgetOutput, size: Size, stale: Bool = false) {
        self.output = output.projected(for: size)
        self.size = size
        self.stale = stale
    }

    /// Canonical point size of `size`: the smallest iPhone widget of that family
    /// on iOS 17 (see `PearlLayoutSpec`). Chat preview cards and snapshots use it.
    public static func previewFrame(for size: Size) -> CGSize {
        PearlLayoutSpec.spec(for: size).frame
    }

    public var body: some View {
        let spec = PearlLayoutSpec.spec(for: size)
        switch size {
        case .inline:
            InlineLayout(output: output, spec: spec, stale: stale)
        case .rectangular, .small, .medium:
            BlockLayout(output: output, spec: spec, stale: stale)
                .padding(spec.insets)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .containerBackground(for: .widget) {
                    if size == .rectangular { Color.clear } else { Color(uiColor: .systemBackground) }
                }
        }
    }
}

/// Stale marker: a small secondary dot. Takes no text width, reads in every
/// rendering mode (full color, accented, vibrant).
struct StaleDot: View {
    var body: some View {
        Circle()
            .fill(.secondary)
            .frame(width: PearlLayoutSpec.staleDotDiameter, height: PearlLayoutSpec.staleDotDiameter)
            .accessibilityLabel(Text("Not updated recently"))
    }
}

/// Lock Screen inline: the value on one line. WidgetKit sets the inline type,
/// so stale is a symbol rather than a drawn dot — shown only when it fits
/// beside the value; the value itself always has the whole line.
struct InlineLayout: View {
    let output: WidgetOutput
    let spec: PearlLayoutSpec
    let stale: Bool

    var body: some View {
        ViewThatFits(in: .horizontal) {
            if stale {
                HStack(spacing: 4) {
                    Image(systemName: "clock.arrow.circlepath")
                        .accessibilityLabel(Text("Not updated recently"))
                    spec.text(output.value, .value)
                }
            }
            spec.text(output.value, .value)
        }
        .widgetAccentable()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(for: .widget) { Color.clear }
    }
}

/// Rectangular, small, and medium: value, subtitle, then the items pinned to
/// the bottom edge. The unpadded content; `PearlWidgetView` frames it.
struct BlockLayout: View {
    let output: WidgetOutput
    let spec: PearlLayoutSpec
    let stale: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: spec.headerSpacing) {
                HStack(alignment: .center, spacing: PearlLayoutSpec.staleDotGap) {
                    spec.text(output.value, .value)
                        .foregroundStyle(.primary)
                        .widgetAccentable()
                    if stale {
                        StaleDot()
                    }
                }
                if let subtitle = output.subtitle {
                    spec.text(subtitle, .subtitle)
                        .foregroundStyle(.secondary)
                }
            }
            if let items = output.items, !items.isEmpty {
                Spacer(minLength: spec.sectionSpacing)
                VStack(alignment: .leading, spacing: spec.itemSpacing) {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                        ItemRow(item: item, spec: spec)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ItemRow: View {
    let item: WidgetOutput.Item
    let spec: PearlLayoutSpec

    var body: some View {
        if spec.stacksItems {
            VStack(alignment: .leading, spacing: 0) {
                spec.text(item.label, .itemLabel)
                    .foregroundStyle(.secondary)
                if let value = item.value {
                    spec.text(value, .itemValue)
                        .foregroundStyle(.primary)
                }
            }
        } else {
            ItemColumns(gap: spec.itemColumnGap) {
                spec.text(item.label, .itemLabel)
                    .foregroundStyle(.secondary)
                if let value = item.value {
                    spec.text(value, .itemValue)
                        .foregroundStyle(.primary)
                }
            }
        }
    }
}

/// One item row: label leading, value trailing, first baselines aligned.
///
/// When both don't fit at their ideal widths, each column gets the same
/// fraction of its ideal width, so both shrink by the same factor and neither
/// is starved. Deterministic, so `LayoutFitTests` can prove the fit.
struct ItemColumns: Layout {
    let gap: CGFloat

    /// Widths given to columns with `ideal` widths in `available` points.
    static func columnWidths(ideal: [CGFloat], available: CGFloat, gap: CGFloat) -> [CGFloat] {
        let gaps = gap * CGFloat(max(ideal.count - 1, 0))
        let total = ideal.reduce(0, +)
        guard total + gaps > available, total > 0 else { return ideal }
        let scale = max(available - gaps, 0) / total
        return ideal.map { $0 * scale }
    }

    private func widths(_ subviews: Subviews, available: CGFloat?) -> [CGFloat] {
        let ideal = subviews.map { $0.sizeThatFits(.unspecified).width }
        guard let available else { return ideal }
        return Self.columnWidths(ideal: ideal, available: available, gap: gap)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let widths = widths(subviews, available: proposal.width)
        let heights = zip(subviews, widths).map { $0.sizeThatFits(ProposedViewSize(width: $1, height: nil)).height }
        let natural = widths.reduce(0, +) + gap * CGFloat(max(subviews.count - 1, 0))
        return CGSize(width: proposal.width ?? natural, height: heights.max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let widths = widths(subviews, available: bounds.width)
        let proposals = widths.map { ProposedViewSize(width: $0, height: nil) }
        let baselines = zip(subviews, proposals).map { $0.dimensions(in: $1)[VerticalAlignment.firstTextBaseline] }
        let top = baselines.max() ?? 0
        for (index, subview) in subviews.enumerated() {
            let leading = index == 0
            subview.place(
                at: CGPoint(x: leading ? bounds.minX : bounds.maxX, y: bounds.minY + top - baselines[index]),
                anchor: leading ? .topLeading : .topTrailing,
                proposal: proposals[index]
            )
        }
    }
}
