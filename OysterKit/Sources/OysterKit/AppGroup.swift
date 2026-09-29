import Foundation

/// The App Group shared by the Oyster app and its widget extension.
public enum AppGroup {
    public static let identifier = "group.com.aaronw122.oyster"

    /// Root of the App Group shared container.
    /// Returns `nil` when the process lacks the App Group entitlement.
    public static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }

    /// `UserDefaults` suite backed by the App Group container.
    /// Returns `nil` when the process lacks the App Group entitlement
    /// (`UserDefaults(suiteName:)` alone would silently fall back to a
    /// process-local suite that the widget cannot see).
    public static var userDefaults: UserDefaults? {
        guard containerURL != nil else { return nil }
        return UserDefaults(suiteName: identifier)
    }
}
