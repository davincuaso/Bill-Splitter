import Foundation

/// Display-ready summary of what one person owes.
///
/// A pure value type derived from `BillViewModel.makePersonSummaries()`.
/// It pre-computes all display strings so views do zero business logic.
public struct PersonSummaryViewModel: Identifiable {

    // MARK: - Item line

    /// One row in the person's itemized breakdown.
    public struct ItemLineViewModel: Identifiable {
        /// Stable identity for use in `ForEach`.
        public let id: UUID
        public let itemName: String
        /// This person's share of the line total (pre-charge).
        public let shareAmount: Decimal
        /// Human-readable split description, e.g. "Sole", "1 of 3", "1 of 3 × 2".
        public let shareLabel: String
    }

    // MARK: - Properties

    public var id: UUID { person.id }

    public let person: Person
    /// Itemized lines for items this person is assigned to.
    public let itemLines: [ItemLineViewModel]
    /// Sum of item shares before charges.
    public let itemSubtotal: Decimal
    /// Final amount owed including proportional charges (from `SplitResult`).
    public let totalOwed: Decimal
    /// The charge contribution: totalOwed − itemSubtotal.
    public var chargesContribution: Decimal { totalOwed - itemSubtotal }

    // MARK: - Init

    /// - Parameters:
    ///   - person:     The person this summary belongs to.
    ///   - items:      All receipt items (including ones not assigned to this person).
    ///   - totalOwed:  Pre-computed final total from `SplitResult` (includes charges).
    public init(person: Person, items: [BillItem], totalOwed: Decimal) {
        self.person = person
        self.totalOwed = totalOwed

        var lines: [ItemLineViewModel] = []
        var subtotal = Decimal.zero

        for item in items {
            let assigneeCount = item.assignedPeople.count
            guard
                assigneeCount > 0,
                item.assignedPeople.contains(where: { $0.id == person.id })
            else { continue }

            let shareAmount = item.lineTotal / Decimal(assigneeCount)

            let shareLabel: String
            switch assigneeCount {
            case 1:
                shareLabel = "Sole"
            default:
                // Include quantity context when > 1 unit, e.g. "1 of 3 × 2"
                if item.quantity > 1 {
                    shareLabel = "1 of \(assigneeCount) × \(item.quantity)"
                } else {
                    shareLabel = "1 of \(assigneeCount)"
                }
            }

            lines.append(ItemLineViewModel(
                id: item.id,
                itemName: item.name,
                shareAmount: shareAmount,
                shareLabel: shareLabel
            ))
            subtotal += shareAmount
        }

        self.itemLines = lines
        self.itemSubtotal = subtotal
    }
}
