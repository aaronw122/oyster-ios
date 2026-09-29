import OysterKit
import SwiftUI
import WidgetKit

struct PearlEntry: TimelineEntry {
    let date: Date
    let size: Size
    let output: WidgetOutput
    let stale: Bool
    var isPlaceholder = false

    init(date: Date = .now, size: Size, content: PearlWidgetContent) {
        self.date = date
        self.size = size
        output = content.output(for: size)
        stale = content.stale
    }

    static func placeholder(size: Size) -> PearlEntry {
        var entry = PearlEntry(date: .now, size: size, output: PearlWidgetContent.sample, stale: false)
        entry.isPlaceholder = true
        return entry
    }

    private init(date: Date, size: Size, output: WidgetOutput, stale: Bool) {
        self.date = date
        self.size = size
        self.output = output
        self.stale = stale
    }
}

struct PearlTimelineProvider: AppIntentTimelineProvider {
    static let refreshInterval: TimeInterval = 15 * 60

    func placeholder(in context: Context) -> PearlEntry {
        .placeholder(size: size(of: context))
    }

    func snapshot(for configuration: SelectPearlIntent, in context: Context) async -> PearlEntry {
        let size = size(of: context)
        guard let data = PearlEntryLoader.appGroup().cached(pearlId: configuration.pearl?.id, size: size) else {
            return .placeholder(size: size)
        }
        return PearlEntry(size: size, content: .pearl(data))
    }

    func timeline(for configuration: SelectPearlIntent, in context: Context) async -> Timeline<PearlEntry> {
        let size = size(of: context)
        let content = await PearlEntryLoader.appGroup().load(pearlId: configuration.pearl?.id, size: size)
        let now = Date.now
        return Timeline(
            entries: [PearlEntry(date: now, size: size, content: content)],
            policy: .after(now.addingTimeInterval(Self.refreshInterval))
        )
    }

    private func size(of context: Context) -> Size {
        Size(family: context.family) ?? .small
    }
}

struct PearlWidgetEntryView: View {
    let entry: PearlEntry

    var body: some View {
        PearlWidgetView(output: entry.output, size: entry.size, stale: entry.stale)
            .redacted(reason: entry.isPlaceholder ? .placeholder : [])
    }
}

struct PearlWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "PearlWidget", intent: SelectPearlIntent.self, provider: PearlTimelineProvider()) { entry in
            PearlWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Pearl")
        .description("Shows one of your saved Pearls.")
        .supportedFamilies([.accessoryInline, .accessoryRectangular, .systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}
