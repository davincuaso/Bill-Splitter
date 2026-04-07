import Foundation

/// Manages the ephemeral multi-select state for the assignment picker
/// (shown as a sheet or popover when the user taps an item row).
///
/// Lifecycle: created on demand via `BillViewModel.makeAssignmentViewModel(for:)`,
/// presented modally, and discarded when dismissed. The `onConfirm` closure
/// writes the selection back into `BillViewModel`.
@MainActor
public final class ItemAssignmentViewModel: ObservableObject {

    // MARK: - Immutable context

    /// The item being assigned.
    public let item: BillItem

    /// All people available for assignment (the full group).
    public let availablePeople: [Person]

    /// The IDs from the most recent confirmed assignment in the session.
    /// Nil means no prior assignment exists.
    public let lastAssignedIDs: Set<UUID>

    // MARK: - Mutable selection state

    /// IDs of currently selected people. Starts from the item's existing assignees.
    @Published public private(set) var selectedIDs: Set<UUID>

    // MARK: - Private

    private let onConfirm: ([Person]) -> Void

    // MARK: - Init

    public init(
        item: BillItem,
        availablePeople: [Person],
        lastAssignedIDs: Set<UUID> = [],
        onConfirm: @escaping ([Person]) -> Void
    ) {
        self.item = item
        self.availablePeople = availablePeople
        self.lastAssignedIDs = lastAssignedIDs
        self.selectedIDs = Set(item.assignedPeople.map(\.id))
        self.onConfirm = onConfirm
    }

    // MARK: - Computed state

    /// The currently selected `Person` objects, in group order.
    public var selectedPeople: [Person] {
        availablePeople.filter { selectedIDs.contains($0.id) }
    }

    /// True when every person in the group is selected.
    public var isAllSelected: Bool {
        !availablePeople.isEmpty && selectedIDs.count == availablePeople.count
    }

    /// True when no person is selected. Confirm should be disabled in this state.
    public var isNoneSelected: Bool {
        selectedIDs.isEmpty
    }

    /// True when `person` is currently selected.
    public func isSelected(_ person: Person) -> Bool {
        selectedIDs.contains(person.id)
    }

    /// True when a "last selection" shortcut is meaningful to show:
    /// there is a prior selection, it differs from the current selection,
    /// and at least one of those people is still in the group.
    public var canSelectLast: Bool {
        guard !lastAssignedIDs.isEmpty else { return false }
        guard lastAssignedIDs != selectedIDs else { return false }
        return availablePeople.contains { lastAssignedIDs.contains($0.id) }
    }

    /// Applies the last confirmed assignment as the current selection.
    public func selectLast() {
        let validIDs = Set(availablePeople.map(\.id))
        selectedIDs = lastAssignedIDs.intersection(validIDs)
    }

    /// Names of the people in the last selection, for the shortcut label.
    public var lastSelectionLabel: String {
        let names = availablePeople
            .filter { lastAssignedIDs.contains($0.id) }
            .map(\.name)
        switch names.count {
        case 0: return ""
        case 1: return names[0]
        case 2: return "\(names[0]) & \(names[1])"
        default: return "\(names[0]), \(names[1]) +\(names.count - 2)"
        }
    }

    /// Summary label for the bottom of the picker, e.g. "3 people selected".
    public var selectionSummary: String {
        switch selectedIDs.count {
        case 0: return "No one selected"
        case 1: return "1 person selected"
        default: return "\(selectedIDs.count) people selected"
        }
    }

    /// Each person's share of this item if the current selection were confirmed.
    /// Returns `nil` when no one is selected.
    public var projectedSharePerPerson: Decimal? {
        guard !selectedIDs.isEmpty else { return nil }
        return item.lineTotal / Decimal(selectedIDs.count)
    }

    // MARK: - Actions

    /// Toggles a single person in/out of the selection.
    public func toggle(_ person: Person) {
        if selectedIDs.contains(person.id) {
            selectedIDs.remove(person.id)
        } else {
            selectedIDs.insert(person.id)
        }
    }

    /// Selects all available people.
    public func selectAll() {
        selectedIDs = Set(availablePeople.map(\.id))
    }

    /// Clears the entire selection.
    public func clearAll() {
        selectedIDs = []
    }

    /// Writes the confirmed selection back to `BillViewModel` via the closure.
    /// Call this when the user taps "Confirm" / "Done".
    public func confirm() {
        onConfirm(selectedPeople)
    }
}
