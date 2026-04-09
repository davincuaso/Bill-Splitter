import SwiftUI

/// Multi-select sheet for assigning people to a bill item.
/// Driven entirely by `ItemAssignmentViewModel` — no direct coupling to `BillViewModel`.
struct AssignPeopleSheet: View {
    @StateObject private var vm: ItemAssignmentViewModel
    @Environment(\.dismiss) private var dismiss

    init(assignmentVM: ItemAssignmentViewModel) {
        _vm = StateObject(wrappedValue: assignmentVM)
    }

    var body: some View {
        NavigationStack {
            List {
                quickActionsSection
                peopleSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle(vm.item.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        vm.confirm()
                        dismiss()
                    } label: {
                        Text(confirmLabel)
                            .fontWeight(.semibold)
                    }
                    .disabled(vm.isNoneSelected)
                }
            }
        }
    }

    // MARK: - Quick actions

    private var quickActionsSection: some View {
        Section {
            // Split among everyone
            QuickActionRow(
                icon: "person.2.fill",
                label: "Split Among Everyone",
                subtitle: "\(vm.availablePeople.count) people · \(everyoneShareLabel)",
                isActive: vm.isAllSelected
            ) {
                withAnimation(.easeInOut(duration: 0.15)) { vm.selectAll() }
            }

            // Last selection shortcut
            if vm.canSelectLast {
                QuickActionRow(
                    icon: "clock.arrow.circlepath",
                    label: "Last Selection",
                    subtitle: vm.lastSelectionLabel,
                    isActive: false
                ) {
                    withAnimation(.easeInOut(duration: 0.15)) { vm.selectLast() }
                }
            }
        } header: {
            Text("Quick Split")
        }
    }

    // MARK: - Individual selection

    private var peopleSection: some View {
        Section {
            ForEach(vm.availablePeople) { person in
                PersonSelectionRow(
                    person: person,
                    isSelected: vm.isSelected(person),
                    sharePreview: sharePreview(for: person)
                ) {
                    withAnimation(.easeInOut(duration: 0.15)) { vm.toggle(person) }
                }
            }
        } header: {
            HStack {
                Text("Select People")
                Spacer()
                if !vm.isNoneSelected {
                    Button("Clear") {
                        withAnimation { vm.clearAll() }
                    }
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textCase(nil)
                }
            }
        } footer: {
            selectionFooter
        }
    }

    // MARK: - Helpers

    private var confirmLabel: String {
        switch vm.selectedIDs.count {
        case 0: return "Confirm"
        case 1: return "Split: Sole"
        default: return "Split Among \(vm.selectedIDs.count)"
        }
    }

    private var everyoneShareLabel: String {
        guard vm.availablePeople.count > 0 else { return "" }
        let share = vm.item.lineTotal / Decimal(vm.availablePeople.count)
        return share.formatted() + " each"
    }

    private func sharePreview(for person: Person) -> String? {
        guard vm.isSelected(person), let share = vm.projectedSharePerPerson else { return nil }
        return share.formatted()
    }

    @ViewBuilder
    private var selectionFooter: some View {
        if let share = vm.projectedSharePerPerson {
            HStack {
                Text(vm.selectionSummary)
                Spacer()
                Text("\(share.formatted()) each")
                    .fontWeight(.medium)
            }
            .font(.footnote)
        } else {
            Text(vm.selectionSummary)
                .font(.footnote)
        }
    }
}

// MARK: - Quick action row

private struct QuickActionRow: View {
    let icon: String
    let label: String
    let subtitle: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.body)
                    .foregroundStyle(isActive ? AnyShapeStyle(.secondary) : AnyShapeStyle(.indigo))
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 1) {
                    Text(label)
                        .foregroundStyle(isActive ? .secondary : .primary)
                        .font(.body)
                    Text(subtitle)
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }

                Spacer()

                if isActive {
                    Image(systemName: "checkmark")
                        .font(.subheadline.bold())
                        .foregroundStyle(.indigo)
                }
            }
        }
        .disabled(isActive)
    }
}

// MARK: - Person selection row

private struct PersonSelectionRow: View {
    let person: Person
    let isSelected: Bool
    let sharePreview: String?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                AvatarChip(person: person, size: .medium)

                Text(person.name)
                    .foregroundStyle(.primary)

                Spacer()

                if let share = sharePreview, isSelected {
                    Text(share)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? AnyShapeStyle(.indigo) : AnyShapeStyle(.tertiary))
                    .animation(.easeInOut(duration: 0.15), value: isSelected)
            }
        }
    }
}

#Preview {
    let alice = Person(name: "Alice Tan")
    let bob   = Person(name: "Bob Lee")
    let carol = Person(name: "Carol")
    let item  = BillItem(name: "Pad Thai", price: 14, assignedPeople: [alice])
    let vm = ItemAssignmentViewModel(
        item: item,
        availablePeople: [alice, bob, carol],
        lastAssignedIDs: [alice.id, bob.id]
    ) { _ in }
    return AssignPeopleSheet(assignmentVM: vm)
}
