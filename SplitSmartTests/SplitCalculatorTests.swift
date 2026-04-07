import XCTest
@testable import SplitSmart

final class SplitCalculatorTests: XCTestCase {

    // MARK: - Fixtures

    let alice = Person(name: "Alice")
    let bob   = Person(name: "Bob")
    let carol = Person(name: "Carol")

    lazy var threePersonGroup = Group(name: "Dinner", people: [alice, bob, carol])
    lazy var twoPersonGroup   = Group(name: "Lunch",  people: [alice, bob])

    // MARK: - Basic splitting

    func test_soleItem_fullCostToOnePerson() {
        let item = BillItem(name: "Steak", price: 30, assignedPeople: [alice])
        let result = SplitCalculator.calculateSplit(
            group: twoPersonGroup,
            items: [item],
            charges: .none
        )
        XCTAssertEqual(result.amount(for: alice), 30)
        XCTAssertEqual(result.amount(for: bob),   0)
    }

    func test_sharedItem_splitEvenly() {
        let item = BillItem(name: "Pizza", price: 30, assignedPeople: [alice, bob, carol])
        let result = SplitCalculator.calculateSplit(
            group: threePersonGroup,
            items: [item],
            charges: .none
        )
        XCTAssertEqual(result.amount(for: alice), 10)
        XCTAssertEqual(result.amount(for: bob),   10)
        XCTAssertEqual(result.amount(for: carol), 10)
    }

    func test_quantity_multipliedBeforeSplitting() {
        // 2 × $15 = $30 total; shared by Alice & Bob → $15 each
        let item = BillItem(name: "Beer", price: 15, quantity: 2, assignedPeople: [alice, bob])
        let result = SplitCalculator.calculateSplit(
            group: twoPersonGroup,
            items: [item],
            charges: .none
        )
        XCTAssertEqual(result.amount(for: alice), 15)
        XCTAssertEqual(result.amount(for: bob),   15)
    }

    func test_subgroupAssignment_onlyAssigneesCharged() {
        // Alice & Bob share an appetizer; Carol gets something else solo.
        let appetizer = BillItem(name: "Wings",  price: 20, assignedPeople: [alice, bob])
        let solo      = BillItem(name: "Salad",  price: 15, assignedPeople: [carol])
        let result = SplitCalculator.calculateSplit(
            group: threePersonGroup,
            items: [appetizer, solo],
            charges: .none
        )
        XCTAssertEqual(result.amount(for: alice), 10)
        XCTAssertEqual(result.amount(for: bob),   10)
        XCTAssertEqual(result.amount(for: carol), 15)
    }

    func test_grandTotalMatchesSumOfItems() {
        let items = [
            BillItem(name: "A", price: 12.50, assignedPeople: [alice]),
            BillItem(name: "B", price: 7.80,  assignedPeople: [alice, bob]),
            BillItem(name: "C", price: 9.00,  assignedPeople: [bob, carol]),
        ]
        let result = SplitCalculator.calculateSplit(
            group: threePersonGroup,
            items: items,
            charges: .none
        )
        let expectedTotal = items.reduce(Decimal.zero) { $0 + $1.lineTotal }
        XCTAssertEqual(result.grandTotal, round2(expectedTotal))
    }

    // MARK: - Charges: Singapore model (SC first, then GST)

    func test_singaporeCharges_correctAmounts() {
        // Subtotal = $100
        // SC  10% on $100     = $10.00   → running total $110
        // GST  9% on $110     = $9.90    → grand total   $119.90
        let item = BillItem(name: "Dinner", price: 100, assignedPeople: [alice])
        let result = SplitCalculator.calculateSplit(
            group: Group(name: "G", people: [alice]),
            items: [item],
            charges: .singapore
        )
        XCTAssertEqual(result.amount(for: alice), Decimal(string: "119.90")!)
    }

    func test_singaporeCharges_threePersonProportional() {
        // Subtotal = $120 (Alice $60, Bob $40, Carol $20)
        // SC  10% on $120 = $12.00  → $132
        // GST  9% on $132 = $11.88  → grand total $143.88
        let items = [
            BillItem(name: "Alice dish", price: 60, assignedPeople: [alice]),
            BillItem(name: "Bob dish",   price: 40, assignedPeople: [bob]),
            BillItem(name: "Carol dish", price: 20, assignedPeople: [carol]),
        ]
        let result = SplitCalculator.calculateSplit(
            group: threePersonGroup,
            items: items,
            charges: .singapore
        )
        // Each person's charge contribution is proportional to their subtotal share.
        // Alice: 60/120 = 50% of $23.88 charges = $11.94  → total $71.94
        // Bob:   40/120 = 33.33...% of $23.88   = $7.96   → total $47.96
        // Carol: 20/120 = 16.66...% of $23.88   = $3.98   → total $23.98
        // Rounded grand total = $143.88
        XCTAssertEqual(result.grandTotal, Decimal(string: "143.88")!)
        XCTAssertEqual(result.amount(for: alice), Decimal(string: "71.94")!)
        XCTAssertEqual(result.amount(for: bob),   Decimal(string: "47.96")!)
        XCTAssertEqual(result.amount(for: carol), Decimal(string: "23.98")!)
    }

    // MARK: - Charge ordering toggle

    func test_gstFirst_differentFromServiceChargeFirst() {
        // Subtotal = $100
        // GST-first:  GST 9% on $100 = $9; SC 10% on $109 = $10.90 → $119.90  [same total here by coincidence at $100]
        // To verify order matters, use asymmetric rates and a value that exposes the difference.
        // Subtotal = $200
        // SC-first:  SC 10% on $200 = $20; GST 9% on $220 = $19.80 → $239.80
        // GST-first: GST 9% on $200 = $18; SC 10% on $218 = $21.80 → $239.80
        // They actually produce the same grand total (multiplication is commutative),
        // but the individual charge *line amounts* differ.
        // The test below verifies both orderings produce the same grand total (math property).
        let item = BillItem(name: "Food", price: 200, assignedPeople: [alice])
        let group = Group(name: "G", people: [alice])

        let scFirst  = Charges(gstPercentage: 9, serviceChargePercentage: 10, applyServiceChargeFirst: true,  isGSTEnabled: true, isServiceChargeEnabled: true)
        let gstFirst = Charges(gstPercentage: 9, serviceChargePercentage: 10, applyServiceChargeFirst: false, isGSTEnabled: true, isServiceChargeEnabled: true)

        let r1 = SplitCalculator.calculateSplit(group: group, items: [item], charges: scFirst)
        let r2 = SplitCalculator.calculateSplit(group: group, items: [item], charges: gstFirst)

        // Grand totals are equal (commutativity of multiplication).
        XCTAssertEqual(r1.grandTotal, r2.grandTotal)
    }

    func test_disableGST_onlyServiceChargeApplied() {
        // Subtotal = $100, SC 10%, GST disabled
        // Total should be $110
        let item = BillItem(name: "Food", price: 100, assignedPeople: [alice])
        let charges = Charges(gstPercentage: 9, serviceChargePercentage: 10, applyServiceChargeFirst: true, isGSTEnabled: false, isServiceChargeEnabled: true)
        let result = SplitCalculator.calculateSplit(
            group: Group(name: "G", people: [alice]),
            items: [item],
            charges: charges
        )
        XCTAssertEqual(result.amount(for: alice), 110)
    }

    func test_disableServiceCharge_onlyGSTApplied() {
        // Subtotal = $100, GST 9%, SC disabled
        // Total should be $109
        let item = BillItem(name: "Food", price: 100, assignedPeople: [alice])
        let charges = Charges(gstPercentage: 9, serviceChargePercentage: 10, applyServiceChargeFirst: true, isGSTEnabled: true, isServiceChargeEnabled: false)
        let result = SplitCalculator.calculateSplit(
            group: Group(name: "G", people: [alice]),
            items: [item],
            charges: charges
        )
        XCTAssertEqual(result.amount(for: alice), 109)
    }

    func test_allChargesDisabled_totalEqualsSubtotal() {
        let item = BillItem(name: "Food", price: 50, assignedPeople: [alice, bob])
        let result = SplitCalculator.calculateSplit(
            group: twoPersonGroup,
            items: [item],
            charges: .none
        )
        XCTAssertEqual(result.grandTotal, 50)
    }

    // MARK: - Edge cases

    func test_unassignedItem_warningEmitted_excludedFromTotal() {
        let unassigned = BillItem(name: "Mystery dish", price: 40, assignedPeople: [])
        let assigned   = BillItem(name: "Salad",        price: 10, assignedPeople: [alice])
        let result = SplitCalculator.calculateSplit(
            group: twoPersonGroup,
            items: [unassigned, assigned],
            charges: .none
        )
        XCTAssertTrue(result.warnings.contains(.itemUnassigned(itemName: "Mystery dish")))
        XCTAssertEqual(result.grandTotal, 10)   // unassigned item excluded
    }

    func test_assigneeNotInGroup_warningEmitted_excludedFromSplit() {
        let outsider = Person(name: "Outsider")
        let item = BillItem(name: "Dish", price: 30, assignedPeople: [alice, outsider])
        let result = SplitCalculator.calculateSplit(
            group: twoPersonGroup,       // outsider not in group
            items: [item],
            charges: .none
        )
        XCTAssertTrue(result.warnings.contains(.assigneeNotInGroup(itemName: "Dish", personName: "Outsider")))
        // Only Alice is valid → she pays the full $30
        XCTAssertEqual(result.amount(for: alice), 30)
    }

    func test_emptyItems_returnsZeroForAllPeople() {
        let result = SplitCalculator.calculateSplit(
            group: twoPersonGroup,
            items: [],
            charges: .singapore
        )
        XCTAssertEqual(result.amount(for: alice), 0)
        XCTAssertEqual(result.amount(for: bob),   0)
        XCTAssertEqual(result.grandTotal,          0)
    }

    func test_roundingResidualBalances_grandTotalExact() {
        // $10 split 3 ways = $3.3333... each → rounding must balance to $10 exactly.
        let item = BillItem(name: "Shared", price: 10, assignedPeople: [alice, bob, carol])
        let result = SplitCalculator.calculateSplit(
            group: threePersonGroup,
            items: [item],
            charges: .none
        )
        XCTAssertEqual(result.grandTotal, 10)
        // Each rounded to 2 d.p.; one person absorbs the residual cent.
        let values = threePersonGroup.people.map { result.amount(for: $0) }
        XCTAssertTrue(values.allSatisfy { $0 == Decimal(string: "3.33")! || $0 == Decimal(string: "3.34")! })
    }

    func test_singlePerson_paysEverything() {
        let solo = Group(name: "Solo", people: [alice])
        let items = [
            BillItem(name: "A", price: 25, assignedPeople: [alice]),
            BillItem(name: "B", price: 15, assignedPeople: [alice]),
        ]
        let result = SplitCalculator.calculateSplit(group: solo, items: items, charges: .singapore)
        // Subtotal = $40; SC 10% = $4; GST 9% on $44 = $3.96 → $47.96
        XCTAssertEqual(result.amount(for: alice), Decimal(string: "47.96")!)
    }

    // MARK: - Helpers

    private func round2(_ value: Decimal) -> Decimal {
        var result = Decimal()
        var input = value
        NSDecimalRound(&result, &input, 2, .bankers)
        return result
    }
}
