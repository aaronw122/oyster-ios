/// What a transform returns and a widget renders (§2b). Structural shape only;
/// per-size budgets live in `SizeBudgets`.
public struct WidgetOutput: Codable, Equatable, Sendable {
    public struct Item: Codable, Equatable, Sendable {
        public var label: String
        public var value: String?

        public init(label: String, value: String? = nil) {
            self.label = label
            self.value = value
        }
    }

    public var value: String
    public var subtitle: String?
    public var items: [Item]?

    public init(value: String, subtitle: String? = nil, items: [Item]? = nil) {
        self.value = value
        self.subtitle = subtitle
        self.items = items
    }
}

/// Per-size widget outputs; sizes may be absent.
public typealias Previews = [Size: WidgetOutput]
