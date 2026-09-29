/// Widget size (§2a). `inline`/`rectangular` are Lock Screen
/// (`.accessoryInline` / `.accessoryRectangular`); `small`/`medium` are Home Screen.
///
/// `CodingKeyRepresentable` makes `[Size: T]` encode as a JSON object keyed by
/// the raw value instead of a flat key/value array.
public enum Size: String, Codable, CaseIterable, CodingKeyRepresentable, Sendable {
    case inline
    case rectangular
    case small
    case medium
}
