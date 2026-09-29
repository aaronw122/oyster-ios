import WidgetKit

extension Size {
    /// The contract size a WidgetKit family renders; `nil` for families Oyster
    /// doesn't support.
    public init?(family: WidgetFamily) {
        switch family {
        case .accessoryInline: self = .inline
        case .accessoryRectangular: self = .rectangular
        case .systemSmall: self = .small
        case .systemMedium: self = .medium
        default: return nil
        }
    }

    /// The WidgetKit family this size is rendered in.
    public var widgetFamily: WidgetFamily {
        switch self {
        case .inline: .accessoryInline
        case .rectangular: .accessoryRectangular
        case .small: .systemSmall
        case .medium: .systemMedium
        }
    }
}
