import XCTest
import Combine
@testable import SplitSmart

// MARK: - Mock calculator

/// Synchronous stub that returns a fixed result, used to isolate ViewModel logic
/// from the real SplitCalculator in tests that don't need arithmetic correctness.
struct MockSplitCalculator: SplitCalculating {
    var stubbedResult: SplitResult?

    func calculateSplit(group: Group, items: [BillItem], charges: Charges) -> SplitResult {
        stubbedResult ?? SplitResult(amountOwed: [:], warnings: [])
    }
}

// MARK: - Tests

@MainActor
final class BillViewModelTests: XCTestCase {

    private var sut: BillViewModel!
    private var cancellables = Set<AnyCancellable>()

    override func setUp() {
        super.setUp()
        sut = BillViewModel(charges: .none, calculator: DefaultSplitCalculator())
    }

    override func tearDown() {
        cancellables.removeAll()
        sut = nil
        super.tearDown()
    }

    // MARK: - People

    func test_addPerson_appendsToPeopleList() {
        let alice = sut.addPerson(name: "Alice")
        XCTAssertEqual(sut.people.count, 1)
        XCTAssertEqual(sut.people.first?.name, "Alice")
        XCTAssertEqual(sut.people.first?.id, alice.id)
    }

    func test_removePerson_removeFromPeopleAndAssignments() {
        let alice = sut.addPerson(name: "Alice")
        let bob   = sut.addPerson(name: "Bob")
        let item  = sut.addItem(name: "Dish", price: 20)
        sut.assignPeople([alice, bob], toItemID: item.id)

        sut.removePerson(id: alice.id)

        XCTAssertEqual(sut.people.count, 1)
        XCTAssertFalse(sut.items[0].assignedPeople.contains { $0.id == alice.id })
        XCTAssertTrue(sut.items[0].assignedPeople.contains { $0.id == bob.id })
    }

    func test_updatePerson_syncsNameInAssignments() {
        let alice = sut.addPerson(name: "Alice")
        let item  = sut.addItem(name: "Dish", price: 10)
        sut.assignPeople([alice], toItemID: item.id)

        sut.updatePerson(id: alice.id, name: "Alicia")

        XCTAssertEqual(sut.people[0].name, "Alicia")
        XCTAssertEqual(sut.items[0].assignedPeople[0].name, "Alicia")
    }

    // MARK: - Items

    func test_addItem_appendsToItemsList() {
        let item = sut.addItem(name: "Pasta", price: 18.50, quantity: 2)
        XCTAssertEqual(sut.items.count, 1)
        XCTAssertEqual(sut.items[0].lineTotal, 37.00)
        XCTAssertEqual(item.id, sut.items[0].id)
    }

    func test_removeItem_removesFromList() {
        let item = sut.addItem(name: "Pizza", price: 25)
        sut.removeItem(id: item.id)
        XCTAssertTrue(sut.items.isEmpty)
    }

    func test_updateItem_patchesFields() {
        let item = sut.addItem(name: "Old", price: 10, quantity: 1)
        sut.updateItem(id: item.id, name: "New", price: 20, quantity: 3)
        XCTAssertEqual(sut.items[0].name,     "New")
        XCTAssertEqual(sut.items[0].price,    20)
        XCTAssertEqual(sut.items[0].quantity, 3)
    }

    func test_updateItem_partialUpdate_leavesOtherFieldsUnchanged() {
        let item = sut.addItem(name: "Dish", price: 15, quantity: 2)
        sut.updateItem(id: item.id, price: 20)
        XCTAssertEqual(sut.items[0].name,     "Dish")
        XCTAssertEqual(sut.items[0].price,    20)
        XCTAssertEqual(sut.items[0].quantity, 2)
    }

    func test_importItems_replacesExistingItems() {
        sut.addItem(name: "Old item", price: 5)
        let newItems = [
            BillItem(name: "Scanned A", price: 12),
            BillItem(name: "Scanned B", price: 8),
        ]
        sut.importItems(newItems)
        XCTAssertEqual(sut.items.count, 2)
        XCTAssertEqual(sut.items[0].name, "Scanned A")
    }

    // MARK: - Subtotal

    func test_subtotal_sumOfAllLineTotals() {
        sut.addItem(name: "A", price: 10, quantity: 2)   // $20
        sut.addItem(name: "B", price: 5)                 // $5
        XCTAssertEqual(sut.subtotal, 25)
    }

    // MARK: - Assignment

    func test_assignPeople_setsAssigneesOnItem() {
        let alice = sut.addPerson(name: "Alice")
        let bob   = sut.addPerson(name: "Bob")
        let item  = sut.addItem(name: "Shared", price: 30)

        sut.assignPeople([alice, bob], toItemID: item.id)

        XCTAssertEqual(sut.items[0].assignedPeople.count, 2)
    }

    func test_assignPeople_ignoresPeopleNotInGroup() {
        let alice    = sut.addPerson(name: "Alice")
        let outsider = Person(name: "Outsider")
        let item     = sut.addItem(name: "Dish", price: 20)

        sut.assignPeople([alice, outsider], toItemID: item.id)

        XCTAssertEqual(sut.items[0].assignedPeople.count, 1)
        XCTAssertEqual(sut.items[0].assignedPeople[0].id, alice.id)
    }

    func test_togglePerson_addsWhenAbsent() {
        let alice = sut.addPerson(name: "Alice")
        let item  = sut.addItem(name: "Dish", price: 20)

        sut.togglePerson(alice, onItemID: item.id)
        XCTAssertEqual(sut.items[0].assignedPeople.count, 1)
    }

    func test_togglePerson_removesWhenPresent() {
        let alice = sut.addPerson(name: "Alice")
        let item  = sut.addItem(name: "Dish", price: 20)
        sut.assignPeople([alice], toItemID: item.id)

        sut.togglePerson(alice, onItemID: item.id)
        XCTAssertTrue(sut.items[0].assignedPeople.isEmpty)
    }

    func test_assignAllPeople_assignsEveryoneInGroup() {
        sut.addPerson(name: "Alice")
        sut.addPerson(name: "Bob")
        sut.addPerson(name: "Carol")
        let item = sut.addItem(name: "Feast", price: 90)

        sut.assignAllPeople(toItemID: item.id)
        XCTAssertEqual(sut.items[0].assignedPeople.count, 3)
    }

    func test_clearAssignees_removesAll() {
        let alice = sut.addPerson(name: "Alice")
        let item  = sut.addItem(name: "Dish", price: 20)
        sut.assignPeople([alice], toItemID: item.id)

        sut.clearAssignees(fromItemID: item.id)
        XCTAssertTrue(sut.items[0].assignedPeople.isEmpty)
    }

    // MARK: - isReadyToSplit

    func test_isReadyToSplit_falseWhenNoPeople() {
        sut.addItem(name: "Dish", price: 10)
        XCTAssertFalse(sut.isReadyToSplit)
    }

    func test_isReadyToSplit_falseWhenUnassignedItems() {
        sut.addPerson(name: "Alice")
        sut.addItem(name: "Dish", price: 10)   // not assigned
        XCTAssertFalse(sut.isReadyToSplit)
    }

    func test_isReadyToSplit_trueWhenAllAssigned() {
        let alice = sut.addPerson(name: "Alice")
        let item  = sut.addItem(name: "Dish", price: 10)
        sut.assignPeople([alice], toItemID: item.id)
        XCTAssertTrue(sut.isReadyToSplit)
    }

    // MARK: - Live recalculation (async, waits for debounce)

    func test_splitResult_updatesAfterDebounce() async throws {
        let alice = sut.addPerson(name: "Alice")
        let item  = sut.addItem(name: "Dish", price: 40)
        sut.assignPeople([alice], toItemID: item.id)

        // Wait for debounce window + buffer
        try await Task.sleep(nanoseconds: 300_000_000)  // 300 ms

        XCTAssertNotNil(sut.splitResult)
        XCTAssertEqual(sut.grandTotal, 40)
    }

    func test_splitResult_nilWhenNoPeople() async throws {
        sut.addItem(name: "Dish", price: 20)
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertNil(sut.splitResult)
    }

    // MARK: - ItemAssignmentViewModel

    func test_makeAssignmentViewModel_preloadsExistingAssignees() {
        let alice = sut.addPerson(name: "Alice")
        let bob   = sut.addPerson(name: "Bob")
        let item  = sut.addItem(name: "Dish", price: 30)
        sut.assignPeople([alice], toItemID: item.id)

        let assignVM = sut.makeAssignmentViewModel(for: sut.items[0])

        XCTAssertTrue(assignVM.isSelected(alice))
        XCTAssertFalse(assignVM.isSelected(bob))
        XCTAssertEqual(assignVM.availablePeople.count, 2)
    }

    func test_makeAssignmentViewModel_confirm_writesBackToBillViewModel() async throws {
        let alice = sut.addPerson(name: "Alice")
        let bob   = sut.addPerson(name: "Bob")
        let item  = sut.addItem(name: "Dish", price: 30)

        let assignVM = sut.makeAssignmentViewModel(for: item)
        assignVM.toggle(alice)
        assignVM.toggle(bob)
        assignVM.confirm()

        XCTAssertEqual(sut.items[0].assignedPeople.count, 2)
    }

    func test_assignmentViewModel_selectAll_selectsEveryone() {
        sut.addPerson(name: "Alice")
        sut.addPerson(name: "Bob")
        sut.addPerson(name: "Carol")
        let item = sut.addItem(name: "Dish", price: 60)

        let assignVM = sut.makeAssignmentViewModel(for: item)
        assignVM.selectAll()

        XCTAssertTrue(assignVM.isAllSelected)
        XCTAssertEqual(assignVM.selectedPeople.count, 3)
    }

    func test_assignmentViewModel_projectedShare_dividesBySelectedCount() {
        sut.addPerson(name: "Alice")
        sut.addPerson(name: "Bob")
        let item = sut.addItem(name: "Dish", price: 30)

        let assignVM = sut.makeAssignmentViewModel(for: item)
        assignVM.selectAll()

        XCTAssertEqual(assignVM.projectedSharePerPerson, 15)
    }
}

// MARK: - PersonSummaryViewModel tests

@MainActor
final class PersonSummaryViewModelTests: XCTestCase {

    func test_itemLines_onlyIncludesPersonsItems() {
        let alice = Person(name: "Alice")
        let bob   = Person(name: "Bob")
        let items = [
            BillItem(name: "Alice's dish", price: 20, assignedPeople: [alice]),
            BillItem(name: "Shared dish",  price: 30, assignedPeople: [alice, bob]),
            BillItem(name: "Bob's dish",   price: 15, assignedPeople: [bob]),
        ]
        let summary = PersonSummaryViewModel(person: alice, items: items, totalOwed: 35)

        XCTAssertEqual(summary.itemLines.count, 2)
        XCTAssertTrue(summary.itemLines.allSatisfy { $0.itemName != "Bob's dish" })
    }

    func test_itemSubtotal_sumOfShares() {
        let alice = Person(name: "Alice")
        let bob   = Person(name: "Bob")
        let items = [
            BillItem(name: "Sole",   price: 20, assignedPeople: [alice]),            // $20
            BillItem(name: "Shared", price: 30, assignedPeople: [alice, bob]),       // $15 each
        ]
        let summary = PersonSummaryViewModel(person: alice, items: items, totalOwed: 35)
        XCTAssertEqual(summary.itemSubtotal, 35)
    }

    func test_shareLabel_sole() {
        let alice = Person(name: "Alice")
        let items = [BillItem(name: "Steak", price: 50, assignedPeople: [alice])]
        let summary = PersonSummaryViewModel(person: alice, items: items, totalOwed: 50)
        XCTAssertEqual(summary.itemLines[0].shareLabel, "Sole")
    }

    func test_shareLabel_multiPerson() {
        let alice = Person(name: "Alice")
        let bob   = Person(name: "Bob")
        let carol = Person(name: "Carol")
        let items = [BillItem(name: "Pizza", price: 30, assignedPeople: [alice, bob, carol])]
        let summary = PersonSummaryViewModel(person: alice, items: items, totalOwed: 10)
        XCTAssertEqual(summary.itemLines[0].shareLabel, "1 of 3")
    }

    func test_shareLabel_multiPersonMultiQuantity() {
        let alice = Person(name: "Alice")
        let bob   = Person(name: "Bob")
        let items = [BillItem(name: "Beer", price: 8, quantity: 4, assignedPeople: [alice, bob])]
        let summary = PersonSummaryViewModel(person: alice, items: items, totalOwed: 16)
        XCTAssertEqual(summary.itemLines[0].shareLabel, "1 of 2 × 4")
    }

    func test_chargesContribution_differenceFromSubtotal() {
        let alice = Person(name: "Alice")
        let items = [BillItem(name: "Food", price: 100, assignedPeople: [alice])]
        // totalOwed = $119.90 (SG charges), itemSubtotal = $100
        let summary = PersonSummaryViewModel(person: alice, items: items, totalOwed: Decimal(string: "119.90")!)
        XCTAssertEqual(summary.chargesContribution, Decimal(string: "19.90")!)
    }
}
