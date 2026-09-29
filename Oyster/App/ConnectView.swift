import OysterKit
import SwiftUI

/// Points the app at an Oyster server. Shown on first run and from Settings.
struct ConnectView: View {
    let model: AppModel
    /// Whether the sheet can be dismissed without connecting.
    let canCancel: Bool

    @Environment(\.dismiss) private var dismiss
    @State private var address: String
    @State private var token: String
    @State private var error: AppModel.ConnectError?
    @State private var isConnecting = false

    init(model: AppModel, canCancel: Bool) {
        self.model = model
        self.canCancel = canCancel
        _address = State(initialValue: model.config?.baseURL.absoluteString ?? "")
        _token = State(initialValue: model.config?.token ?? "")
    }

    private var canConnect: Bool {
        !isConnecting
            && !address.trimmingCharacters(in: .whitespaces).isEmpty
            && !token.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("oyster.example.com", text: $address)
                        .textContentType(.URL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Server")
                }
                Section {
                    SecureField("Access token", text: $token)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Access token")
                } footer: {
                    Text("Your server and token come from whoever runs your Oyster server. They're kept on this iPhone and shared with your widgets.")
                }
                if let error {
                    Section {
                        Label(error.message, systemImage: "exclamationmark.circle")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(canCancel ? "Settings" : "Connect to Oyster")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if canCancel {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isConnecting {
                        ProgressView()
                    } else {
                        Button("Connect", action: connect).disabled(!canConnect)
                    }
                }
            }
            .interactiveDismissDisabled(!canCancel || isConnecting)
        }
    }

    private func connect() {
        isConnecting = true
        error = nil
        Task {
            do throws(AppModel.ConnectError) {
                try await model.connect(address: address, token: token)
                dismiss()
            } catch {
                self.error = error
            }
            isConnecting = false
        }
    }
}
