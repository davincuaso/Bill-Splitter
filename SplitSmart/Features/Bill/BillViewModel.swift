import Foundation
import Combine

/// The single source of truth for an in-progress bill splitting session.
///
/// Responsibilities:
/// - Manages the people in the group.
/// - Manages receipt items (add / edit / remove).
/// - Manages charge configuration (GST, service charge).
/// - Triggers live recalculation via Combine whenever state changes.
/// - Exposes computed display data consumed by views.
///
/// All mutations are intentionally routed through explicit methods so that
/// business rules (e.g. removing a person also cleans their assignments) are
/// enforced in one place, never leaked into views.
@MainActor
public final class BillViewModel: ObservableObject {

    // MARK: - Published state

    /// The ordered list of people in this bill's group.
    @Published public private(set) var people: [Person] = []

    /// Display name shown in the navigation bar.
    @Published public var groupName: String = "New Bill"

    /// ISO 4217 currency code used for formatting throughout the app.
    @Published public var currencyCode: String = "SGD"

    /// The receipt line items.
    @Published public private(set) var items: [BillItem] = []

    /// Tax and service-charge configuration. Directly mutable so views can bind
    /// individual fields: `$viewModel.charges.gstPercentage`.
    @Published public var charges: Charges

    /// The most recent split calculation output. `nil` when no people are present
    /// or no items have been added yet.
    @Published public private(set) var splitResult: SplitResult?

    // MARK: - Dependencies

    private let calculator: any SplitCalculating
    private var cancellables = Set<AnyCancellable>()

    /// The people IDs from the most recently confirmed item assignment.
    /// Used as a smart default when new items are added.
    private var lastAssignedIDs: Set<UUID> = []

    // MARK: - Init

    public init(
        charges: Charges = .singapore,
        calculator: any SplitCalculating = DefaultSplitCalculator()
    ) {
        self.charges = charges
        self.calculator = calculator

        // Restore the last saved session before wiring up any Combine pipelines,
        // so the initial load doesn't trigger unnecessary saves.
        if let saved = SessionPersistence.load() {
            self.groupName = saved.groupName
            self.currencyCode = saved.currencyCode
            self.people = saved.people
            self.items = saved.items
            self.charges = saved.charges
            self.lastAssignedIDs = saved.lastAssignedIDs
        }

        setupAutoRecalculation()
        setupPersistence()
    }

    // MARK: - Reactive recalculation

    /// Recalculates 150 ms after any change to people, items, or charges.
    private func setupAutoRecalculation() {
        Publishers.CombineLatest3($people, $items, $charges)
            .debounce(for: .milliseconds(150), scheduler: RunLoop.main)
            .sink { [weak self] people, items, charges in
                self?.recalculate(people: people, items: items, charges: charges)
            }
            .store(in: &cancellables)
    }

    private func recalculate(people: [Person], items: [BillItem], charges: Charges) {
        guard !people.isEmpty else {
            splitResult = nil
            return
        }
        let group = BillGroup(name: groupName, people: people)
        splitResult = calculator.calculateSplit(group: group, items: items, charges: charges)
    }

    // MARK: - Persistence

    /// Saves the session 1 s after any state change. Coarser debounce than
    /// recalculation to avoid hammering UserDefaults while the user types.
    private func setupPersistence() {
        Publishers.CombineLatest($people, $items)
            .combineLatest($charges)
            .combineLatest($groupName)
            .debounce(for: .seconds(1), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.saveSession() }
            .store(in: &cancellables)
    }

    private func saveSession() {
        let snapshot = SessionSnapshot(
            groupName: groupName,
            currencyCode: currencyCode,
            people: people,
            items: items,
            charges: charges,
            lastAssignedIDs: lastAssignedIDs
        )
        SessionPersistence.save(snapshot)
    }

    /// Wipes the stored session and resets the ViewModel to blank defaults.
    public func clearSession() {
        groupName = "New Bill"
        currencyCode = "SGD"
        people = []
        items = []
        charges = .singapore
        lastAssignedIDs = []
        splitResult = nil
        SessionPersistence.clear()
    }

    // MARK: - Computed properties

    /// Sum of all item line totals before charges.
    public var subtotal: Decimal {
        items.reduce(.zero) { $0 + $1.lineTotal }
    }

    /// Grand total including all enabled charges.
    public var grandTotal: Decimal {
        splitResult?.grandTotal ?? .zero
    }

    /// Non-fatal warnings from the last calculation (e.g. unassigned items).
    public var warnings: [SplitWarning] {
        splitResult?.warnings ?? []
    }

    /// True when the last calculation produced at least one warning.
    public var hasWarnings: Bool { !warnings.isEmpty }

    /// Items that have no assigned people — these are excluded from the split
    /// and will produce a warning.
    public var unassignedItems: [BillItem] {
        items.filter { $0.assignedPeople.isEmpty }
    }

    /// True when a split can be calculated cleanly (people present, items present,
    /// all items assigned).
    public var isReadyToSplit: Bool {
        !people.isEmpty && !items.isEmpty && unassignedItems.isEmpty
    }

    // MARK: - People management

    /// Adds a new person to the group and returns them.
    @discardableResult
    public func addPerson(name: String) -> Person {
        let person = Person(name: name)
        people.append(person)
        return person
    }

    /// Removes a person from the group and strips them from all item assignments.
    public func removePerson(id: UUID) {
        people.removeAll { $0.id == id }
        for i in items.indices {
            items[i].assignedPeople.removeAll { $0.id == id }
        }
    }

    /// Updates a person's display name everywhere it appears (group + assignments).
    public func updatePerson(id: UUID, name: String) {
        guard let pi = people.firstIndex(where: { $0.id == id }) else { return }
        people[pi].name = name
        // Keep the denormalized copies inside item assignments in sync.
        for ii in items.indices {
            for ai in items[ii].assignedPeople.indices
                where items[ii].assignedPeople[ai].id == id {
                items[ii].assignedPeople[ai].name = name
            }
        }
    }

    // MARK: - Item management

    /// Adds a new receipt line item and returns it.
    /// Smart default: automatically assigns the item to the same people as the
    /// last confirmed assignment, so repeat items don't need manual re-assignment.
    @discardableResult
    public func addItem(name: String, price: Decimal, quantity: Int = 1) -> BillItem {
        let item = BillItem(name: name, price: price, quantity: quantity)
        items.append(item)
        // Apply smart default only if those people are still in the group.
        if !lastAssignedIDs.isEmpty {
            let defaultPeople = people.filter { lastAssignedIDs.contains($0.id) }
            if !defaultPeople.isEmpty {
                assignPeople(defaultPeople, toItemID: item.id)
            }
        }
        return item
    }

    /// Removes an item by ID.
    public func removeItem(id: UUID) {
        items.removeAll { $0.id == id }
    }

    /// Partially updates an item. Pass only the fields you want to change.
    public func updateItem(
        id: UUID,
        name: String? = nil,
        price: Decimal? = nil,
        quantity: Int? = nil
    ) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        if let name     { items[i].name = name }
        if let price    { items[i].price = price }
        if let quantity { items[i].quantity = quantity }
    }

    /// Replaces the full item list (e.g. after receipt scanning).
    /// Existing assignments are discarded since the item IDs will be new.
    public func importItems(_ newItems: [BillItem]) {
        items = newItems
    }

    /// Replaces items and updates charges from a scanned/reviewed receipt.
    /// If `detectedCurrencyCode` is non-nil, the session currency is also updated.
    public func applyParsedReceipt(
        _ newItems: [BillItem],
        charges importedCharges: Charges,
        currencyCode detectedCurrencyCode: String? = nil
    ) {
        importItems(newItems)
        charges = importedCharges
        if let code = detectedCurrencyCode {
            currencyCode = code
        }
    }

    // MARK: - Assignment management

    /// Replaces all assignees for an item. Silently ignores people not in the group.
    /// Records the assignment as the new smart default for future items.
    public func assignPeople(_ newPeople: [Person], toItemID itemID: UUID) {
        guard let i = items.firstIndex(where: { $0.id == itemID }) else { return }
        let groupIDs = Set(people.map(\.id))
        let valid = newPeople.filter { groupIDs.contains($0.id) }
        items[i].assignedPeople = valid
        // Update the smart default whenever a non-empty assignment is confirmed.
        if !valid.isEmpty {
            lastAssignedIDs = Set(valid.map(\.id))
        }
    }

    /// Toggles a single person's assignment on an item.
    public func togglePerson(_ person: Person, onItemID itemID: UUID) {
        guard let i = items.firstIndex(where: { $0.id == itemID }) else { return }
        if items[i].assignedPeople.contains(where: { $0.id == person.id }) {
            items[i].assignedPeople.removeAll { $0.id == person.id }
        } else {
            items[i].assignedPeople.append(person)
        }
    }

    /// Assigns every person in the group to an item ("Everyone" shortcut).
    public func assignAllPeople(toItemID itemID: UUID) {
        guard let i = items.firstIndex(where: { $0.id == itemID }) else { return }
        items[i].assignedPeople = people
    }

    /// Removes all assignees from an item.
    public func clearAssignees(fromItemID itemID: UUID) {
        guard let i = items.firstIndex(where: { $0.id == itemID }) else { return }
        items[i].assignedPeople = []
    }

    // MARK: - Summary helpers

    /// Amount owed by a specific person after the last calculation.
    public func amount(for person: Person) -> Decimal {
        splitResult?.amount(for: person) ?? .zero
    }

    /// Builds display-ready summaries for all people, sorted by amount descending
    /// (highest payer first).
    public func makePersonSummaries() -> [PersonSummaryViewModel] {
        people
            .map { PersonSummaryViewModel(person: $0, items: items, totalOwed: amount(for: $0)) }
            .sorted { $0.totalOwed > $1.totalOwed }
    }

    // MARK: - Child ViewModel factory

    /// Creates an `ItemAssignmentViewModel` for the assignment picker sheet.
    /// The child VM's `confirm()` writes back into this VM automatically.
    /// Passes `lastAssignedIDs` so the sheet can offer a "Last Selection" shortcut.
    public func makeAssignmentViewModel(for item: BillItem) -> ItemAssignmentViewModel {
        ItemAssignmentViewModel(
            item: item,
            availablePeople: people,
            lastAssignedIDs: lastAssignedIDs
        ) { [weak self] selectedPeople in
            self?.assignPeople(selectedPeople, toItemID: item.id)
        }
    }
}
