import Foundation

/// The App Group shared by the Oyster app and its widget extension.
public enum AppGroup {
    public static let identifier = "group.com.aaronw122.oyster"

    /// `UserDefaults` suite backed by the App Group container.
    /// Returns `nil` when the process lacks the App Group entitlement.
    public static var userDefaults: UserDefaults? {
        UserDefaults(suiteName: identifier)
    }

    /// Root of the App Group shared container.
    /// Returns `nil` when the process lacks the App Group entitlement.
    public static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }
}
