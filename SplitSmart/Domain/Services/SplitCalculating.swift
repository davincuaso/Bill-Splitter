import Foundation

/// Abstracts the split calculation so ViewModels can be tested with a mock
/// and so alternative implementations (e.g. server-side, ML-assisted) can be
/// swapped in without touching view-layer code.
public protocol SplitCalculating {
    func calculateSplit(group: Group, items: [BillItem], charges: Charges) -> SplitResult
}

/// Production implementation — thin wrapper around the pure `SplitCalculator` enum.
public struct DefaultSplitCalculator: SplitCalculating {
    public init() {}

    public func calculateSplit(group: Group, items: [BillItem], charges: Charges) -> SplitResult {
        SplitCalculator.calculateSplit(group: group, items: items, charges: charges)
    }
}
