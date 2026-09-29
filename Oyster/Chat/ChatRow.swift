import Foundation
import OysterKit

/// One entry in the chat transcript. Everything here is already plain language;
/// the view never sees raw events.
struct ChatRow: Identifiable, Equatable {
    enum Kind: Equatable {
        /// Something the user sent.
        case user(String)
        /// The assistant's reply, grown delta by delta.
        case assistant(String)
        /// A question from the assistant. Option buttons send the option text.
        case question(id: String, text: String, options: [String])
        /// What the Pearl will look like, one card per size the server sent.
        case previews([PreviewCard])
        /// The Pearl was saved to the library.
        case saved(name: String)
        /// The assistant needs the user to sign in somewhere.
        case signIn(provider: String, url: URL)
        /// Signing in came back with an error; the user can ask to try again.
        case signInFailed(provider: String)
        /// Something couldn't be done (unavailable data, a failed turn, …).
        case notice(String)
    }

    let id: UUID
    var kind: Kind

    init(_ kind: Kind, id: UUID = UUID()) {
        self.id = id
        self.kind = kind
    }
}

/// A preview of the Pearl at one widget size.
struct PreviewCard: Equatable, Identifiable {
    let size: Size
    let output: WidgetOutput

    var id: Size { size }

    /// The size in plain words.
    var label: String {
        switch size {
        case .inline: "Lock Screen, one line"
        case .rectangular: "Lock Screen"
        case .small: "Small"
        case .medium: "Medium"
        }
    }

    /// Cards for every size present in `previews`, smallest first.
    static func cards(for previews: Previews) -> [PreviewCard] {
        Size.allCases.compactMap { size in
            previews[size].map { PreviewCard(size: size, output: $0) }
        }
    }
}

/// How a sign-in provider is named to the user.
enum ProviderName {
    private static let known: [String: String] = [
        "plaid": "your bank",
        "github": "GitHub",
        "google": "Google",
        "spotify": "Spotify",
        "strava": "Strava",
    ]

    static func display(for provider: String) -> String {
        if let name = known[provider.lowercased()] { return name }
        let words = provider.split(whereSeparator: { $0 == "_" || $0 == "-" })
        return words.map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }
}

/// The server's redirect back into the app after an OAuth sign-in:
/// `oyster://oauth/complete?provider=<id>&status=ok|error`.
struct OAuthCallback: Equatable {
    static let scheme = "oyster"

    let provider: String
    let succeeded: Bool
}

extension OAuthCallback {
    init?(url: URL) {
        guard url.scheme?.lowercased() == Self.scheme,
              url.host() == "oauth",
              url.path() == "/complete",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let provider = items.first(where: { $0.name == "provider" })?.value, !provider.isEmpty,
              let status = items.first(where: { $0.name == "status" })?.value
        else { return nil }
        self.provider = provider
        self.succeeded = status == "ok"
    }
}
