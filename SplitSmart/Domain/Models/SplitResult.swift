import Foundation

/// The output of a split calculation.
public struct SplitResult: Sendable {
    /// Amount owed per person, rounded to 2 decimal places.
    public let amountOwed: [Person: Decimal]
    /// Non-fatal warnings raised during calculation.
    public let warnings: [SplitWarning]

    /// Convenience accessor — returns 0 if the person is not in the result.
    public func amount(for person: Person) -> Decimal {
        amountOwed[person] ?? .zero
    }

    /// The grand total across all people (sum of item lineTotals + charges).
    public var grandTotal: Decimal {
        amountOwed.values.reduce(.zero, +)
    }
}

// MARK: - Warnings

public enum SplitWarning: Equatable, Sendable {
    /// An item has no people assigned — its cost is excluded from the split.
    case itemUnassigned(itemName: String)
    /// An item's assignedPeople contains someone not in the group.
    case assigneeNotInGroup(itemName: String, personName: String)
}

extension SplitWarning: CustomStringConvertible {
    public var description: String {
        switch self {
        case .itemUnassigned(let name):
            return "\"\(name)\" has no assigned people and was excluded from the split."
        case .assigneeNotInGroup(let item, let person):
            return "\"\(person)\" is assigned to \"\(item)\" but is not in the group."
        }
    }
}
