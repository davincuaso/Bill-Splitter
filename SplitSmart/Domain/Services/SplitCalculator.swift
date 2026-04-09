import Foundation

/// Pure, stateless service that computes how much each person owes.
///
/// Usage:
/// ```swift
/// let result = SplitCalculator.calculateSplit(group: group, items: items, charges: charges)
/// ```
public enum SplitCalculator {

    // MARK: - Public API

    /// Calculates the amount owed by each person in the group.
    ///
    /// - Parameters:
    ///   - group:   The dining group. Only people present in the group receive a result entry.
    ///   - items:   Receipt line items, each with assigned people and a quantity.
    ///   - charges: Tax and service-charge configuration.
    /// - Returns:   A `SplitResult` containing per-person amounts and any warnings.
    public static func calculateSplit(
        group: BillGroup,
        items: [BillItem],
        charges: Charges
    ) -> SplitResult {
        var warnings: [SplitWarning] = []

        // Step 1 — Compute each person's raw item subtotal.
        let subtotals = itemSubtotals(
            group: group,
            items: items,
            warnings: &warnings
        )

        // If nobody has any items, return zeroes immediately.
        let sessionSubtotal = subtotals.values.reduce(.zero, +)
        guard sessionSubtotal > .zero else {
            let zeroes = Dictionary(uniqueKeysWithValues: group.people.map { ($0, Decimal.zero) })
            return SplitResult(amountOwed: zeroes, warnings: warnings)
        }

        // Step 2 — Resolve charge amounts in the configured order.
        let chargeAmounts = resolveCharges(subtotal: sessionSubtotal, charges: charges)

        // Step 3 — Attribute each charge proportionally to each person.
        var amountOwed: [Person: Decimal] = subtotals
        for chargeAmount in chargeAmounts {
            for person in group.people {
                let personSubtotal = subtotals[person] ?? .zero
                let proportion = personSubtotal / sessionSubtotal
                amountOwed[person, default: .zero] += proportion * chargeAmount
            }
        }

        // Step 4 — Round to 2 d.p. and absorb any residual into the highest payer.
        amountOwed = roundWithResidualCorrection(
            amounts: amountOwed,
            people: group.people,
            targetTotal: sessionSubtotal + chargeAmounts.reduce(.zero, +)
        )

        return SplitResult(amountOwed: amountOwed, warnings: warnings)
    }

    // MARK: - Step 1: Item subtotals

    /// Returns each group member's share of item costs, before charges.
    private static func itemSubtotals(
        group: BillGroup,
        items: [BillItem],
        warnings: inout [SplitWarning]
    ) -> [Person: Decimal] {
        let groupIDs = Set(group.people.map(\.id))
        var subtotals: [Person: Decimal] = Dictionary(
            uniqueKeysWithValues: group.people.map { ($0, Decimal.zero) }
        )

        for item in items {
            // Warn about assignees outside the group (and exclude them from the split).
            let validAssignees = item.assignedPeople.filter { person in
                if groupIDs.contains(person.id) {
                    return true
                } else {
                    warnings.append(.assigneeNotInGroup(itemName: item.name, personName: person.name))
                    return false
                }
            }

            guard !validAssignees.isEmpty else {
                warnings.append(.itemUnassigned(itemName: item.name))
                continue
            }

            // Split lineTotal evenly among valid assignees.
            let sharePerPerson = item.lineTotal / Decimal(validAssignees.count)
            for person in validAssignees {
                subtotals[person, default: .zero] += sharePerPerson
            }
        }

        return subtotals
    }

    // MARK: - Step 2: Charge resolution

    /// Returns charge amounts in application order (first charge compounds into second).
    ///
    /// Ordering when `applyServiceChargeFirst == true`:
    ///   1. SC  = subtotal × SC%
    ///   2. GST = (subtotal + SC) × GST%
    ///
    /// Ordering when `applyServiceChargeFirst == false`:
    ///   1. GST = subtotal × GST%
    ///   2. SC  = (subtotal + GST) × SC%
    private static func resolveCharges(subtotal: Decimal, charges: Charges) -> [Decimal] {
        typealias ChargeSpec = (rate: Decimal, isEnabled: Bool)

        let sc:  ChargeSpec = (charges.serviceChargePercentage / 100, charges.isServiceChargeEnabled)
        let gst: ChargeSpec = (charges.gstPercentage / 100, charges.isGSTEnabled)

        let first:  ChargeSpec = charges.applyServiceChargeFirst ? sc  : gst
        let second: ChargeSpec = charges.applyServiceChargeFirst ? gst : sc

        var result: [Decimal] = []
        var runningBase = subtotal

        if first.isEnabled {
            let amount = runningBase * first.rate
            result.append(amount)
            runningBase += amount
        }

        if second.isEnabled {
            let amount = runningBase * second.rate
            result.append(amount)
        }

        return result
    }

    // MARK: - Step 4: Rounding

    /// Rounds every person's amount to 2 decimal places, then assigns any leftover
    /// cent(s) to the person with the highest pre-rounding amount (deterministic).
    ///
    /// This guarantees: `sum(amountOwed.values) == targetTotal` to 2 d.p.
    private static func roundWithResidualCorrection(
        amounts: [Person: Decimal],
        people: [Person],
        targetTotal: Decimal
    ) -> [Person: Decimal] {
        var rounded = amounts.mapValues { round2($0) }

        let roundedSum = rounded.values.reduce(.zero, +)
        let targetRounded = round2(targetTotal)
        let residual = targetRounded - roundedSum

        // The residual is typically ±$0.01 per N people due to truncation.
        // Assign it to the person whose unrounded amount is largest.
        if residual != .zero, let topPayer = people.max(by: {
            (amounts[$0] ?? .zero) < (amounts[$1] ?? .zero)
        }) {
            rounded[topPayer, default: .zero] += residual
        }

        return rounded
    }

    // MARK: - Helpers

    private static func round2(_ value: Decimal) -> Decimal {
        var result = Decimal()
        var input = value
        NSDecimalRound(&result, &input, 2, .bankers)
        return result
    }
}
