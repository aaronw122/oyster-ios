extension WidgetOutput {
    /// The §2b per-size projection, mirroring the server's `projectForSize`:
    /// fields `size` doesn't show are dropped and `items` is cut to the size's
    /// cap (first N). Lengths are not checked here — see `SizeBudgets.fits`.
    public func projected(for size: Size) -> WidgetOutput {
        let budget = SizeBudgets[size]
        return WidgetOutput(
            value: value,
            subtitle: budget.subtitle == nil ? nil : subtitle,
            items: budget.items.flatMap { limits in items.map { Array($0.prefix(limits.max)) } }
        )
    }
}
