import SwiftUI

/// A single row in the bill items list.
///
/// Tap → assignment picker sheet
/// Swipe leading → edit details
/// Swipe trailing → delete
/// Long-press / context menu → quick actions without opening a sheet
struct BillItemRow: View {
    let item: BillItem
    let currencyCode: String
    let onAssign: () -> Void
    let onEdit: () -> Void
    let onAssignAll: () -> Void
    let onClearAssignment: () -> Void

    var isUnassigned: Bool { item.assignedPeople.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            topLine
            assigneeStrip
        }
        .padding(.vertical, 4)
        .listRowBackground(
            // Subtle tint draws attention to unassigned items without being harsh.
            isUnassigned
                ? Color.orange.opacity(0.07)
                : Color(.secondarySystemGroupedBackground)
        )
        .contentShape(Rectangle())
        .onTapGesture { onAssign() }
        // Quick actions via context menu (long-press)
        .contextMenu { contextMenuContent }
        // Edit swipe action
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button { onEdit() } label: {
                Label("Edit", systemImage: "pencil")
            }
            .tint(.indigo)
        }
    }

    // MARK: - Top line

    private var topLine: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name)
                    .font(.body)
                    .fontWeight(.medium)

                if item.quantity > 1 {
                    Text("\(item.quantity) × \(item.price.formatted(currencyCode: currencyCode))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text(item.lineTotal.formatted(currencyCode: currencyCode))
                .font(.body)
                .fontWeight(.semibold)
                .monospacedDigit()
        }
    }

    // MARK: - Assignee strip

    @ViewBuilder
    private var assigneeStrip: some View {
        if isUnassigned {
            Label {
                Text("Tap to assign people")
            } icon: {
                Image(systemName: "person.badge.plus")
            }
            .font(.caption)
            .foregroundStyle(.orange)
        } else {
            HStack(spacing: -6) {
                ForEach(item.assignedPeople.prefix(6)) { person in
                    AvatarChip(person: person, size: .small)
                        .overlay(
                            Circle().stroke(Color(.secondarySystemGroupedBackground), lineWidth: 1.5)
                        )
                }
                if item.assignedPeople.count > 6 {
                    Text("+\(item.assignedPeople.count - 6)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 10)
                }

                Spacer()

                // Per-person share hint
                let count = item.assignedPeople.count
                let share = item.lineTotal / Decimal(count)
                Text(count == 1 ? "Sole" : "\(share.formatted(currencyCode: currencyCode)) each")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    // MARK: - Context menu

    @ViewBuilder
    private var contextMenuContent: some View {
        Button {
            onAssign()
        } label: {
            Label("Assign People…", systemImage: "person.badge.plus")
        }

        Button {
            onAssignAll()
        } label: {
            Label("Split Among Everyone", systemImage: "person.2.fill")
        }

        Button { onEdit() } label: {
            Label("Edit Item", systemImage: "pencil")
        }

        if !isUnassigned {
            Divider()
            Button(role: .destructive) {
                onClearAssignment()
            } label: {
                Label("Clear Assignment", systemImage: "person.badge.minus")
            }
        }
    }
}

#Preview {
    let alice = Person(name: "Alice Tan")
    let bob   = Person(name: "Bob Lee")
    let carol = Person(name: "Carol")
    List {
        BillItemRow(
            item: BillItem(name: "Laksa", price: 8.50, quantity: 2, assignedPeople: [alice]),
            currencyCode: "SGD",
            onAssign: {}, onEdit: {}, onAssignAll: {}, onClearAssignment: {}
        )
        BillItemRow(
            item: BillItem(name: "Tiger Beer", price: 12, assignedPeople: [alice, bob, carol]),
            currencyCode: "SGD",
            onAssign: {}, onEdit: {}, onAssignAll: {}, onClearAssignment: {}
        )
        BillItemRow(
            item: BillItem(name: "Unassigned dish", price: 18),
            currencyCode: "SGD",
            onAssign: {}, onEdit: {}, onAssignAll: {}, onClearAssignment: {}
        )
    }
}
