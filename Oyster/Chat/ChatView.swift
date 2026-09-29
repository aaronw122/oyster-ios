import OysterKit
import SwiftUI

struct ChatView: View {
    @Bindable var model: ChatViewModel
    let openSettings: () -> Void

    @FocusState private var composerFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        if model.rows.isEmpty {
                            intro
                        }
                        ForEach(model.rows) { row in
                            ChatRowView(row: row, model: model)
                                .id(row.id)
                        }
                        if model.isStreaming {
                            statusLine.id(Self.statusID)
                        }
                    }
                    .padding()
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: model.rows.last) {
                    guard let last = model.rows.last?.id else { return }
                    withAnimation { proxy.scrollTo(last, anchor: .bottom) }
                }
                .onChange(of: model.status) {
                    if model.isStreaming { proxy.scrollTo(Self.statusID, anchor: .bottom) }
                }
            }
            .safeAreaInset(edge: .bottom) { composer }
            .navigationTitle("Chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Settings", systemImage: "gearshape", action: openSettings)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("New conversation", systemImage: "square.and.pencil") {
                        model.newConversation()
                    }
                    .disabled(!model.canStartOver)
                }
            }
        }
    }

    private static let statusID = "status"

    private var intro: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What would you like to see at a glance?")
                .font(.title3.weight(.semibold))
            Text("Describe it in your own words — like “open Citi Bike docks near my office” or “my checking balance”. Oyster builds a widget for it.")
                .foregroundStyle(.secondary)
        }
        .padding(.top, 24)
    }

    private var statusLine: some View {
        HStack(spacing: 8) {
            ProgressView()
            if let status = model.status {
                Text(status)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .contentTransition(.opacity)
            }
        }
        .animation(.default, value: model.status)
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Message", text: $model.draft, axis: .vertical)
                .lineLimit(1...5)
                .focused($composerFocused)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 20))
                .disabled(model.isStreaming)
                .onSubmit(model.sendDraft)
            if model.isStreaming {
                Button("Stop", systemImage: "stop.circle.fill", action: model.cancel)
                    .labelStyle(.iconOnly)
                    .font(.title)
            } else {
                Button("Send", systemImage: "arrow.up.circle.fill", action: model.sendDraft)
                    .labelStyle(.iconOnly)
                    .font(.title)
                    .disabled(!model.canSend || model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

/// One transcript row, rendered in plain language.
private struct ChatRowView: View {
    let row: ChatRow
    let model: ChatViewModel

    var body: some View {
        switch row.kind {
        case .user(let text):
            Text(text)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Color.accentColor.opacity(0.15), in: .rect(cornerRadius: 18))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.leading, 48)
        case .assistant(let text):
            Text(text)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .question(_, let text, let options):
            QuestionCard(text: text, options: options, enabled: model.canAnswer(row)) { option in
                model.send(option)
            }
        case .previews(let cards):
            VStack(alignment: .leading, spacing: 12) {
                ForEach(cards) { PreviewCardView(card: $0) }
            }
        case .saved(let name):
            Label("Saved “\(name)”. Add it from your Home Screen or Lock Screen.", systemImage: "checkmark.circle.fill")
                .symbolRenderingMode(.hierarchical)
        case .signIn(let provider, let url):
            VStack(alignment: .leading, spacing: 10) {
                Text("Sign in to \(ProviderName.display(for: provider)) to continue.")
                Button("Sign in") { model.signIn(url: url) }
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.canSend)
            }
        case .signInFailed(let provider):
            VStack(alignment: .leading, spacing: 10) {
                Label("Signing in to \(ProviderName.display(for: provider)) didn't finish.", systemImage: "exclamationmark.circle")
                    .foregroundStyle(.secondary)
                Button("Try again") { model.retrySignIn(provider: provider) }
                    .buttonStyle(.bordered)
                    .disabled(!model.canSend)
            }
        case .notice(let text):
            Label(text, systemImage: "exclamationmark.circle")
                .foregroundStyle(.secondary)
        }
    }
}

private struct QuestionCard: View {
    let text: String
    let options: [String]
    let enabled: Bool
    let choose: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(text).font(.body.weight(.medium))
            if !options.isEmpty {
                ForEach(options, id: \.self) { option in
                    Button {
                        choose(option)
                    } label: {
                        Text(option).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!enabled)
                }
                if enabled {
                    Text("Or type your own answer.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 16))
    }
}

/// The Pearl exactly as the widget will draw it at one size.
private struct PreviewCardView: View {
    let card: PreviewCard

    var body: some View {
        let frame = PearlWidgetView.previewFrame(for: card.size)
        VStack(alignment: .leading, spacing: 8) {
            Text(card.label)
                .font(.footnote)
                .foregroundStyle(.secondary)
            PearlWidgetView(output: card.output, size: card.size)
                .frame(width: frame.width, height: frame.height)
                // Home Screen widgets sit on their own background; Lock Screen ones sit on the wallpaper.
                .background(isHomeScreen ? Color(.systemBackground) : .clear, in: .rect(cornerRadius: 20))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 24))
    }

    private var isHomeScreen: Bool {
        card.size == .small || card.size == .medium
    }
}
