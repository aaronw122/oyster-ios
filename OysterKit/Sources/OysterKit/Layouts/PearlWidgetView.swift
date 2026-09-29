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
    /// on iOS 17 (375×667 pt screens). Chat preview cards and snapshots use it.
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
/// so stale is a symbol rather than a drawn dot.
struct InlineLayout: View {
    let output: WidgetOutput
    let spec: PearlLayoutSpec
    let stale: Bool

    var body: some View {
        HStack(spacing: 4) {
            if stale {
                Image(systemName: "clock.arrow.circlepath")
                    .accessibilityLabel(Text("Not updated recently"))
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
            HStack(alignment: .firstTextBaseline, spacing: spec.itemColumnGap) {
                spec.text(item.label, .itemLabel)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if let value = item.value {
                    spec.text(value, .itemValue)
                        .foregroundStyle(.primary)
                }
            }
        }
    }
}
