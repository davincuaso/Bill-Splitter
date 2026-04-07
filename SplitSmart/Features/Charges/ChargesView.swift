import SwiftUI

/// Lets the user configure GST and service charge rates and application order.
struct ChargesView: View {
    @ObservedObject var viewModel: BillViewModel

    var body: some View {
        Form {
            // MARK: Service Charge
            Section {
                Toggle(isOn: $viewModel.charges.isServiceChargeEnabled) {
                    Label("Service Charge", systemImage: "fork.knife")
                }

                if viewModel.charges.isServiceChargeEnabled {
                    rateRow(
                        label: "Rate",
                        value: $viewModel.charges.serviceChargePercentage
                    )
                }
            } header: {
                Text("Service Charge")
            }

            // MARK: GST
            Section {
                Toggle(isOn: $viewModel.charges.isGSTEnabled) {
                    Label("GST", systemImage: "building.columns")
                }

                if viewModel.charges.isGSTEnabled {
                    rateRow(
                        label: "Rate",
                        value: $viewModel.charges.gstPercentage
                    )
                }
            } header: {
                Text("Goods & Services Tax")
            }

            // MARK: Application order (only relevant when both are on)
            if viewModel.charges.isServiceChargeEnabled && viewModel.charges.isGSTEnabled {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Picker("Order", selection: $viewModel.charges.applyServiceChargeFirst) {
                            Text("SC → GST").tag(true)
                            Text("GST → SC").tag(false)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()

                        Text(orderExplanation)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Application Order")
                } footer: {
                    Text("Singapore standard: Service Charge first, then GST on the combined amount.")
                }
            }

            // MARK: Live preview
            if viewModel.subtotal > 0 {
                Section("Preview") {
                    previewRow("Subtotal", value: viewModel.subtotal)

                    if viewModel.charges.isServiceChargeEnabled {
                        let sc = viewModel.subtotal * viewModel.charges.serviceChargePercentage / 100
                        previewRow(
                            "Service Charge (\(viewModel.charges.serviceChargePercentage.formatted())%)",
                            value: sc,
                            secondary: true
                        )
                    }

                    if viewModel.charges.isGSTEnabled {
                        let gst = viewModel.grandTotal - viewModel.subtotal -
                            (viewModel.charges.isServiceChargeEnabled
                                ? viewModel.subtotal * viewModel.charges.serviceChargePercentage / 100
                                : 0)
                        previewRow(
                            "GST (\(viewModel.charges.gstPercentage.formatted())%)",
                            value: gst,
                            secondary: true
                        )
                    }

                    Divider()

                    HStack {
                        Text("Grand Total")
                            .fontWeight(.semibold)
                        Spacer()
                        Text(viewModel.grandTotal.formatted(currencyCode: viewModel.currencyCode))
                            .fontWeight(.bold)
                            .monospacedDigit()
                    }
                }
            }
        }
        .navigationTitle("Charges & Tax")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Sub-views

    private func rateRow(label: String, value: Binding<Decimal>) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("0", text: value.asText)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 60)
                .foregroundStyle(.indigo)
            Text("%")
                .foregroundStyle(.secondary)
        }
    }

    private func previewRow(_ label: String, value: Decimal, secondary: Bool = false) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(secondary ? .secondary : .primary)
                .font(secondary ? .subheadline : .body)
            Spacer()
            Text(value.formatted(currencyCode: viewModel.currencyCode))
                .foregroundStyle(secondary ? .secondary : .primary)
                .font(secondary ? .subheadline : .body)
                .monospacedDigit()
        }
    }

    private var orderExplanation: String {
        if viewModel.charges.applyServiceChargeFirst {
            let sc = viewModel.charges.serviceChargePercentage
            let gst = viewModel.charges.gstPercentage
            return "SC \(sc.formatted())% applies to subtotal first. GST \(gst.formatted())% then applies to the combined amount."
        } else {
            let sc = viewModel.charges.serviceChargePercentage
            let gst = viewModel.charges.gstPercentage
            return "GST \(gst.formatted())% applies to subtotal first. SC \(sc.formatted())% then applies to the combined amount."
        }
    }
}

#Preview {
    let vm = BillViewModel()
    vm.addPerson(name: "Alice")
    vm.addItem(name: "Laksa", price: 8.50)
    vm.addItem(name: "Kaya Toast", price: 4.00)
    return NavigationStack {
        ChargesView(viewModel: vm)
    }
}
