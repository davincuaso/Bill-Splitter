import SwiftUI

/// Expandable card showing one person's full breakdown.
struct PersonCardView: View {
    let summary: PersonSummaryViewModel
    let currencyCode: String

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // MARK: Header (always visible)
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    AvatarChip(person: summary.person, size: .medium)

                    Text(summary.person.name)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)

                    Spacer()

                    Text(summary.totalOwed.formatted(currencyCode: currencyCode))
                        .font(.body)
                        .fontWeight(.bold)
                        .monospacedDigit()
                        .foregroundStyle(.primary)

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.bold())
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 4)
            }

            // MARK: Expanded breakdown
            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    Divider().padding(.vertical, 8)

                    if summary.itemLines.isEmpty {
                        Text("No items assigned")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.bottom, 4)
                    } else {
                        ForEach(summary.itemLines) { line in
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text(line.itemName)
                                    .font(.subheadline)

                                Text("·")
                                    .foregroundStyle(.tertiary)

                                Text(line.shareLabel)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                Spacer()

                                Text(line.shareAmount.formatted(currencyCode: currencyCode))
                                    .font(.subheadline)
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 3)
                        }
                    }

                    // Charges contribution
                    if summary.chargesContribution > 0 {
                        Divider().padding(.vertical, 6)

                        HStack {
                            Image(systemName: "percent")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("Taxes & Charges")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("+ \(summary.chargesContribution.formatted(currencyCode: currencyCode))")
                                .font(.subheadline)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }

                    // Total line
                    Divider().padding(.vertical, 6)

                    HStack {
                        Text("Total")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(summary.totalOwed.formatted(currencyCode: currencyCode))
                            .font(.subheadline.weight(.bold))
                            .monospacedDigit()
                    }
                }
                .padding(.bottom, 4)
            }
        }
    }
}

#Preview {
    let alice = Person(name: "Alice Tan")
    let items = [
        BillItem(name: "Chicken Rice", price: 5.50, assignedPeople: [alice]),
        BillItem(name: "Tiger Beer", price: 12, quantity: 2, assignedPeople: [alice, Person(name: "Bob")]),
    ]
    let summary = PersonSummaryViewModel(person: alice, items: items, totalOwed: 18.40)
    return List {
        PersonCardView(summary: summary, currencyCode: "SGD")
    }
}
