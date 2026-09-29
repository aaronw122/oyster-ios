import OysterKit
import SwiftUI

/// The saved Pearls on this iPhone — the same list the widget picker offers.
struct PearlsView: View {
    let disk: PearlDiskStore?
    let api: APIClient?
    let openSettings: () -> Void

    @State private var entries: [Entry] = []
    @State private var refreshFailed = false

    struct Entry: Identifiable {
        let pearl: PearlSummary
        let small: PearlData?
        var id: String { pearl.id }
    }

    var body: some View {
        NavigationStack {
            List {
                if refreshFailed {
                    Label("Couldn't refresh. Showing what's saved on this iPhone.", systemImage: "exclamationmark.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                ForEach(entries) { PearlRow(entry: $0) }
            }
            .overlay {
                if entries.isEmpty {
                    ContentUnavailableView {
                        Label("No Pearls yet", systemImage: "circle.hexagongrid")
                    } description: {
                        Text("Open Chat and describe something you'd like to see at a glance. When you save it, it shows up here and in the widget picker.")
                    }
                }
            }
            .navigationTitle("Pearls")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Settings", systemImage: "gearshape", action: openSettings)
                }
            }
            .refreshable { await refresh() }
            .onAppear(perform: reload)
            .task(id: api?.config) { await refresh() }
        }
    }

    private func reload() {
        guard let disk else { return }
        entries = disk.list().map { Entry(pearl: $0, small: disk.data(id: $0.id, size: .small)) }
    }

    private func refresh() async {
        guard let disk, let api else {
            reload()
            return
        }
        do {
            try await PearlSync.sync(api: api, disk: disk)
            refreshFailed = false
        } catch is CancellationError {
            return
        } catch {
            refreshFailed = true
        }
        reload()
    }
}

private struct PearlRow: View {
    let entry: PearlsView.Entry

    private static let thumbnailScale: CGFloat = 0.5

    var body: some View {
        HStack(spacing: 16) {
            if let data = entry.small {
                let frame = PearlWidgetView.previewFrame(for: .small)
                PearlWidgetView(output: data.output, size: .small, stale: data.stale)
                    .frame(width: frame.width, height: frame.height)
                    .background(Color(.systemBackground))
                    .clipShape(.rect(cornerRadius: 20))
                    .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color(.separator), lineWidth: 1))
                    .scaleEffect(Self.thumbnailScale)
                    .frame(width: frame.width * Self.thumbnailScale, height: frame.height * Self.thumbnailScale)
                    .accessibilityHidden(true)
            }
            Text(entry.pearl.name)
                .font(.headline)
        }
        .padding(.vertical, 4)
    }
}
