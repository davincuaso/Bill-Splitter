import SwiftUI

/// Sheet for adding a new item or editing an existing one.
/// Pass `item: nil` for add mode; pass a `BillItem` for edit mode.
struct AddEditItemSheet: View {
    @ObservedObject var viewModel: BillViewModel
    let item: BillItem?

    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: Field?

    @State private var name: String = ""
    @State private var priceText: String = ""
    @State private var quantity: Int = 1

    private enum Field { case name, price }

    private var isEditing: Bool { item != nil }

    private var parsedPrice: Decimal? {
        Decimal(string: priceText, locale: Locale(identifier: "en_US_POSIX"))
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && parsedPrice != nil && parsedPrice! > 0
    }

    private var lineTotal: Decimal {
        (parsedPrice ?? 0) * Decimal(quantity)
    }

    var body: some View {
        NavigationStack {
            Form {
                // MARK: Details
                Section("Item Details") {
                    TextField("Item name", text: $name)
                        .focused($focusedField, equals: .name)
                        .autocorrectionDisabled()

                    HStack {
                        Text("Price")
                        Spacer()
                        TextField("0.00", text: $priceText)
                            .focused($focusedField, equals: .price)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 120)
                    }

                    Stepper {
                        HStack {
                            Text("Quantity")
                            Spacer()
                            Text("\(quantity)")
                                .foregroundStyle(.secondary)
                        }
                    } onIncrement: {
                        quantity += 1
                    } onDecrement: {
                        if quantity > 1 { quantity -= 1 }
                    }
                }

                // MARK: Line total preview
                if lineTotal > 0 {
                    Section {
                        HStack {
                            Text("Line Total")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(lineTotal.formatted(currencyCode: viewModel.currencyCode))
                                .fontWeight(.semibold)
                        }
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Item" : "Add Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(!canSave)
                }
            }
            .onAppear {
                if let item {
                    name = item.name
                    priceText = (item.price as NSDecimalNumber).stringValue
                    quantity = item.quantity
                } else {
                    focusedField = .name
                }
            }
        }
    }

    private func save() {
        guard let price = parsedPrice else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        if let item {
            viewModel.updateItem(id: item.id, name: trimmedName, price: price, quantity: quantity)
        } else {
            viewModel.addItem(name: trimmedName, price: price, quantity: quantity)
        }
    }
}

#Preview {
    let vm = BillViewModel()
    return AddEditItemSheet(viewModel: vm, item: nil)
}
