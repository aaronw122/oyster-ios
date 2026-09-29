/// What the widget shows for one timeline entry.
public enum PearlWidgetContent: Equatable, Sendable {
    /// A Pearl's data — fresh from the server or its on-device last-good.
    case pearl(PearlData)
    /// No Pearl is configured, or the configured one is no longer saved on this device.
    case choosePearl
    /// Nothing to show until the app has connected and fetched this Pearl.
    case openOyster

    /// The output to render at `size`. Prompts are written to fit every size's budget.
    public func output(for size: Size) -> WidgetOutput {
        switch self {
        case .pearl(let data):
            data.output
        case .choosePearl:
            WidgetOutput(value: "Choose Pearl", subtitle: "Edit this widget")
        case .openOyster:
            WidgetOutput(value: "Open Oyster", subtitle: "Nothing to show yet")
        }
    }

    /// Whether the rendered output is older than the latest refresh.
    public var stale: Bool {
        if case .pearl(let data) = self { data.stale } else { false }
    }

    /// Neutral stand-in rendered (redacted) while the widget loads and in the
    /// widget gallery when no real data is on the device.
    public static let sample = WidgetOutput(
        value: "72°",
        subtitle: "Partly cloudy",
        items: [
            WidgetOutput.Item(label: "High", value: "78°"),
            WidgetOutput.Item(label: "Low", value: "64°"),
            WidgetOutput.Item(label: "Wind", value: "8 mph"),
        ]
    )
}
