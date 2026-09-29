import SwiftUI
import WidgetKit

struct OysterEntry: TimelineEntry {
    let date: Date
}

struct OysterProvider: TimelineProvider {
    func placeholder(in context: Context) -> OysterEntry {
        OysterEntry(date: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping (OysterEntry) -> Void) {
        completion(OysterEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<OysterEntry>) -> Void) {
        completion(Timeline(entries: [OysterEntry(date: .now)], policy: .never))
    }
}

struct OysterWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: OysterEntry

    var body: some View {
        switch family {
        case .accessoryInline:
            Text("Oyster")
        case .accessoryRectangular:
            VStack(alignment: .leading) {
                Text("Oyster").font(.headline)
                Text("No Pearl yet").font(.caption)
            }
        default:
            VStack(spacing: 6) {
                Image(systemName: "circle.hexagongrid.fill")
                    .font(.title)
                Text("Oyster")
                    .font(.headline)
            }
        }
    }
}

struct OysterWidget: Widget {
    let kind = "OysterWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: OysterProvider()) { entry in
            OysterWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Oyster")
        .description("A Pearl on your Home or Lock Screen.")
        .supportedFamilies([.accessoryInline, .accessoryRectangular, .systemSmall, .systemMedium])
    }
}
