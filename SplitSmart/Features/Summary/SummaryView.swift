import SwiftUI

/// The final per-person breakdown screen.
struct SummaryView: View {
    @ObservedObject var viewModel: BillViewModel
    @State private var showShareSheet = false

    private var summaries: [PersonSummaryViewModel] {
        viewModel.makePersonSummaries()
    }

    var body: some View {
        List {
            // MARK: Grand total hero
            Section {
                VStack(spacing: 6) {
                    Text("Grand Total")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .textCase(nil)

                    Text(viewModel.grandTotal.formatted(currencyCode: viewModel.currencyCode))
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.indigo)

                    subtotalSummaryRow
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 12)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            // MARK: Warnings
            if viewModel.hasWarnings {
                Section {
                    ForEach(viewModel.warnings, id: \.description) { warning in
                        Label {
                            Text(warning.description)
                                .font(.footnote)
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                        }
                    }
                } header: {
                    Text("Warnings")
                }
            }

            // MARK: Per-person cards
            Section {
                ForEach(summaries) { summary in
                    PersonCardView(summary: summary, currencyCode: viewModel.currencyCode)
                }
            } header: {
                HStack {
                    Text("Breakdown")
                    Spacer()
                    Text("\(summaries.count) people")
                        .textCase(nil)
                        .foregroundStyle(.secondary)
                }
            }

            // MARK: Charge summary
            chargesSummarySection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Summary")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showShareSheet = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(text: shareText)
        }
    }

    // MARK: - Sub-views

    @ViewBuilder
    private var subtotalSummaryRow: some View {
        HStack(spacing: 16) {
            Label {
                Text(viewModel.subtotal.formatted(currencyCode: viewModel.currencyCode))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } icon: {
                Image(systemName: "cart")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            if viewModel.grandTotal > viewModel.subtotal {
                Label {
                    Text("+ \((viewModel.grandTotal - viewModel.subtotal).formatted(currencyCode: viewModel.currencyCode)) taxes")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: "percent")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    @ViewBuilder
    private var chargesSummarySection: some View {
        let charges = viewModel.charges
        let hasAnyCharge = charges.isGSTEnabled || charges.isServiceChargeEnabled

        if hasAnyCharge && viewModel.subtotal > 0 {
            Section("Applied Charges") {
                if charges.isServiceChargeEnabled {
                    chargeRow(
                        label: "Service Charge",
                        rate: charges.serviceChargePercentage
                    )
                }
                if charges.isGSTEnabled {
                    chargeRow(label: "GST", rate: charges.gstPercentage)
                }
                HStack {
                    Text("Order")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                    Spacer()
                    Text(charges.applyServiceChargeFirst ? "SC → GST" : "GST → SC")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func chargeRow(label: String, rate: Decimal) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(rate.formatted())%")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    // MARK: - Share text

    private var shareText: String {
        var lines: [String] = []
        lines.append("\(viewModel.groupName) — \(viewModel.grandTotal.formatted(currencyCode: viewModel.currencyCode))")
        lines.append(String(repeating: "─", count: 30))
        for summary in summaries {
            lines.append("\(summary.person.name): \(summary.totalOwed.formatted(currencyCode: viewModel.currencyCode))")
        }
        lines.append(String(repeating: "─", count: 30))
        lines.append("Split with SplitSmart")
        return lines.joined(separator: "\n")
    }
}

// MARK: - Share sheet wrapper

private struct ShareSheet: UIViewControllerRepresentable {
    let text: String

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [text], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    let vm = BillViewModel()
    let alice = vm.addPerson(name: "Alice Tan")
    let bob   = vm.addPerson(name: "Bob Lee")
    let carol = vm.addPerson(name: "Carol")
    let i1 = vm.addItem(name: "Chicken Rice", price: 5.50)
    let i2 = vm.addItem(name: "Tiger Beer",   price: 12.00, quantity: 2)
    let i3 = vm.addItem(name: "Laksa",         price: 9.00)
    vm.assignPeople([alice],        toItemID: i1.id)
    vm.assignPeople([alice, bob],   toItemID: i2.id)
    vm.assignPeople([bob, carol],   toItemID: i3.id)
    return NavigationStack {
        SummaryView(viewModel: vm)
    }
}
