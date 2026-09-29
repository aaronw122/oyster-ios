import SwiftUI

struct RootView: View {
    let model: AppModel
    @State private var showsSettings = false

    var body: some View {
        TabView {
            ChatView(model: model.chat, openSettings: openSettings)
                .tabItem { Label("Chat", systemImage: "bubble.left.and.bubble.right") }
            PearlsView(disk: model.disk, api: model.api, openSettings: openSettings)
                .tabItem { Label("Pearls", systemImage: "circle.hexagongrid") }
        }
        .sheet(isPresented: needsConnection) {
            ConnectView(model: model, canCancel: false)
        }
        .sheet(isPresented: $showsSettings) {
            ConnectView(model: model, canCancel: true)
        }
        .onOpenURL { url in
            model.chat.handleOAuthCallback(url)
        }
    }

    /// First run: nothing works until a server is set, so the sheet can't be dismissed.
    private var needsConnection: Binding<Bool> {
        Binding(get: { model.config == nil }, set: { _ in })
    }

    private func openSettings() {
        showsSettings = true
    }
}
