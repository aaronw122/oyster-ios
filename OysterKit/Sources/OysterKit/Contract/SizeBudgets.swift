/// Per-size length budgets (§2b), in Unicode code points. `nil` = not shown at that size.
public struct SizeBudget: Codable, Equatable, Sendable {
    public struct Items: Codable, Equatable, Sendable {
        /// Maximum number of items shown.
        public var max: Int
        public var label: Int
        public var value: Int

        public init(max: Int, label: Int, value: Int) {
            self.max = max
            self.label = label
            self.value = value
        }
    }

    public var value: Int
    public var subtitle: Int?
    public var items: Items?

    public init(value: Int, subtitle: Int?, items: Items?) {
        self.value = value
        self.subtitle = subtitle
        self.items = items
    }

    private enum CodingKeys: String, CodingKey { case value, subtitle, items }

    // Not-shown fields are explicit `null` on the wire, matching the server table.
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(value, forKey: .value)
        try c.encode(subtitle, forKey: .subtitle)
        try c.encode(items, forKey: .items)
    }
}

/// Mirror of the server's `SIZE_BUDGETS` (`fixtures/contract/size-budgets.json`).
public enum SizeBudgets {
    public static let all: [Size: SizeBudget] = [
        .inline: SizeBudget(value: 12, subtitle: nil, items: nil),
        .rectangular: SizeBudget(value: 12, subtitle: 24, items: nil),
        .small: SizeBudget(value: 16, subtitle: 28, items: .init(max: 2, label: 22, value: 10)),
        .medium: SizeBudget(value: 20, subtitle: 40, items: .init(max: 5, label: 22, value: 10)),
    ]

    public static subscript(size: Size) -> SizeBudget {
        all[size]!
    }

    /// Budget violations for `output` rendered at `size`; empty when it fits.
    ///
    /// Mirrors the server's fit check, which projects before measuring: fields
    /// not shown at `size` and items past the cap are ignored, and every shown
    /// string is measured in Unicode code points. An empty `value` is rejected.
    public static func fits(_ output: WidgetOutput, size: Size) -> [String] {
        let budget = self[size]
        var errors: [String] = []

        func check(_ field: String, _ text: String, _ limit: Int) {
            let count = text.codePointCount
            if count > limit {
                errors.append("\(size.rawValue).\(field): \(count) code points exceeds \(limit)")
            }
        }

        if output.value.isEmpty {
            errors.append("\(size.rawValue).value: value is empty")
        } else {
            check("value", output.value, budget.value)
        }
        if let limit = budget.subtitle, let subtitle = output.subtitle {
            check("subtitle", subtitle, limit)
        }
        if let limits = budget.items, let items = output.items {
            for (index, item) in items.prefix(limits.max).enumerated() {
                check("items[\(index)].label", item.label, limits.label)
                if let value = item.value {
                    check("items[\(index)].value", value, limits.value)
                }
            }
        }
        return errors
    }
}

extension String {
    /// Length in Unicode code points — the unit of every contract budget.
    public var codePointCount: Int {
        unicodeScalars.count
    }
}
