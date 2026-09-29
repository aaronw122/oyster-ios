import AuthenticationServices
import UIKit

/// Presents provider sign-in in `ASWebAuthenticationSession`, sharing Safari's
/// cookies so a user already signed in to the provider isn't asked again.
@MainActor
final class WebAuthenticator: NSObject, WebAuthenticating {
    /// Held so the session isn't deallocated while it's on screen.
    private var session: ASWebAuthenticationSession?

    func authenticate(url: URL, callbackScheme: String) async throws -> URL? {
        session?.cancel()
        let result: URL? = try await withCheckedThrowingContinuation { continuation in
            let completion: ASWebAuthenticationSession.CompletionHandler = { callback, error in
                if let callback {
                    continuation.resume(returning: callback)
                } else if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                    continuation.resume(returning: nil)
                } else {
                    continuation.resume(throwing: error ?? ASWebAuthenticationSessionError(.presentationContextInvalid))
                }
            }
            let session: ASWebAuthenticationSession
            if #available(iOS 17.4, *) {
                session = ASWebAuthenticationSession(url: url, callback: .customScheme(callbackScheme), completionHandler: completion)
            } else {
                session = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackScheme, completionHandler: completion)
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.session = session
            if !session.start() {
                // `start()` returning false means the completion handler won't run.
                continuation.resume(throwing: ASWebAuthenticationSessionError(.presentationContextInvalid))
            }
        }
        session = nil
        return result
    }
}

extension WebAuthenticator: ASWebAuthenticationPresentationContextProviding {
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            let windows = scenes.flatMap(\.windows)
            if let key = windows.first(where: \.isKeyWindow) ?? windows.first {
                return key
            }
            return scenes.first.map(UIWindow.init(windowScene:)) ?? ASPresentationAnchor()
        }
    }
}
