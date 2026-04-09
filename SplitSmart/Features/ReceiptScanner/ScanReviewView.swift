import SwiftUI

// MARK: - Editable item

/// Mutable copy of a `ParsedItem` used only inside the review screen.
struct EditableItem: Identifiable {
    var id: UUID
    var name: String
    var priceText: String
    var quantity: Int
    let lineConfidence: Float
    let rawLine: String

    /// Snapshot of name at parse time — used to detect user edits for the correction store.
    let initialName: String
    /// Snapshot of priceText at parse time — used to detect user edits for the correction store.
    let initialPriceText: String

    init(from item: ParsedItem) {
        id               = item.id
        name             = item.name
        priceText        = Self.format(item.price)
        quantity         = item.quantity
        lineConfidence   = item.lineConfidence
        rawLine          = item.rawLine
        initialName      = item.name
        initialPriceText = Self.format(item.price)
    }

    var parsedPrice: Decimal? {
        Decimal(string: priceText, locale: Locale(identifier: "en_US_POSIX"))
    }
    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && parsedPrice != nil
            && parsedPrice! > 0
    }
    var lineTotal: Decimal {
        (parsedPrice ?? 0) * Decimal(quantity)
    }
    var isLowConfidence: Bool { lineConfidence < 0.70 }

    private static func format(_ d: Decimal) -> String {
        let s = (d as NSDecimalNumber).stringValue
        return s.contains(".") ? s : s + ".00"
    }
}

// MARK: - Review view

/// Shows the parser's output in an editable form before the user imports it.
///
/// The user can: edit any name/price, adjust quantities, delete bad lines,
/// add manually-entered items, and tweak the detected charge rates.
/// All confirmed user edits are written back to `correctionStore` so the parser
/// can apply them automatically on future scans of the same receipt lines.
struct ScanReviewView: View {
    let parsedReceipt:   ParsedReceipt
    let correctionStore: ParserCorrectionStore
    let onImport: ([BillItem], Charges, String?) -> Void

    @Environment(\.dismiss) private var dismiss

    // MARK: Editable state

    @State private var items: [EditableItem]
    @State private var gstEnabled: Bool
    @State private var gstText:    String
    @State private var scEnabled:  Bool
    @State private var scText:     String
    @State private var applyScFirst: Bool = true

    @State private var showAddItemSheet = false

    // MARK: Init

    init(
        parsedReceipt: ParsedReceipt,
        correctionStore: ParserCorrectionStore,
        onImport: @escaping ([BillItem], Charges, String?) -> Void
    ) {
        self.parsedReceipt   = parsedReceipt
        self.correctionStore = correctionStore
        self.onImport        = onImport

        let dc = parsedReceipt.detectedCharges
        _items      = State(initialValue: parsedReceipt.items.map(EditableItem.init))
        _gstEnabled = State(initialValue: dc.gstPercentage != nil)
        _gstText    = State(initialValue: dc.gstPercentage.map { Self.fmt($0) } ?? "9")
        _scEnabled  = State(initialValue: dc.serviceChargePercentage != nil)
        _scText     = State(initialValue: dc.serviceChargePercentage.map { Self.fmt($0) } ?? "10")
    }

    private static func fmt(_ d: Decimal) -> String {
        (d as NSDecimalNumber).stringValue
    }

    // MARK: Computed

    private var validItems: [EditableItem] { items.filter(\.isValid) }
    private var canImport:  Bool           { !validItems.isEmpty }

    private var parsedSubtotal: Decimal {
        validItems.reduce(.zero) { $0 + $1.lineTotal }
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            List {
                warningBanner
                itemsSection
                chargesSection
                summarySection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Review Receipt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") { commitImport() }
                        .fontWeight(.semibold)
                        .disabled(!canImport)
                }
            }
            .sheet(isPresented: $showAddItemSheet) {
                AddManualItemSheet { name, price, qty in
                    items.append(EditableItem(from: ParsedItem(
                        name: name, price: price, quantity: qty,
                        lineConfidence: 1.0, rawLine: ""
                    )))
                }
            }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var warningBanner: some View {
        if !parsedReceipt.warnings.isEmpty {
            Section {
                ForEach(parsedReceipt.warnings, id: \.self) { warning in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: warningIcon(warning))
                            .foregroundStyle(warningColor(warning))
                        Text(warningMessage(warning))
                            .font(.subheadline)
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                Text("Parser Notes")
            }
        }
    }

    private var itemsSection: some View {
        Section {
            ForEach($items) { $item in
                EditableItemRow(item: $item)
            }
            .onDelete { indexSet in
                // Record "skip" corrections for parser-originated lines before removing.
                for index in indexSet where !items[index].rawLine.isEmpty {
                    correctionStore.record(
                        ParserCorrection(shouldSkip: true),
                        for: items[index].rawLine
                    )
                }
                items.remove(atOffsets: indexSet)
            }
            .onMove { from, to in
                items.move(fromOffsets: from, toOffset: to)
            }

            Button {
                showAddItemSheet = true
            } label: {
                Label("Add Item Manually", systemImage: "plus.circle.fill")
                    .foregroundStyle(.indigo)
            }
        } header: {
            HStack {
                Text("Items")
                Spacer()
                Text("\(validItems.count) of \(items.count) valid")
                    .foregroundStyle(.secondary)
                    .textCase(nil)
                    .font(.caption)
            }
        } footer: {
            Text("Tap a field to edit · Swipe left to delete · Drag to reorder")
                .font(.caption2)
        }
    }

    private var chargesSection: some View {
        Section("Detected Charges") {
            // Detected currency
            if let code = parsedReceipt.detectedCurrencyCode {
                HStack {
                    Label("Currency", systemImage: "dollarsign.circle")
                    Spacer()
                    Text(code)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            // GST / VAT
            chargeRow(
                label: parsedReceipt.detectedCharges.gstLabel,
                icon: "building.columns",
                enabled: $gstEnabled,
                rateText: $gstText
            )

            // Service charge
            chargeRow(
                label: parsedReceipt.detectedCharges.serviceLabel,
                icon: "fork.knife",
                enabled: $scEnabled,
                rateText: $scText
            )

            // Order (only relevant when both are on)
            if gstEnabled && scEnabled {
                Picker("Apply Order", selection: $applyScFirst) {
                    Text("SC → \(parsedReceipt.detectedCharges.gstLabel)").tag(true)
                    Text("\(parsedReceipt.detectedCharges.gstLabel) → SC").tag(false)
                }
                .pickerStyle(.segmented)
                .padding(.vertical, 2)
            }
        }
    }

    @ViewBuilder
    private var summarySection: some View {
        if parsedSubtotal > 0 {
            Section("Summary") {
                summaryRow("Items subtotal", value: parsedSubtotal)
                subtotalReconciliationRow
                if let total = parsedReceipt.detectedTotal {
                    summaryRow("Receipt total (with charges)", value: total)
                }
            }
        }
    }

    @ViewBuilder
    private var subtotalReconciliationRow: some View {
        if let detected = parsedReceipt.detectedSubtotal {
            let isMatch = abs(parsedSubtotal - detected) <= Decimal(string: "0.05")!
            HStack {
                Text("Receipt subtotal")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(detected.formatted())
                    .monospacedDigit()
                Image(systemName: isMatch ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .foregroundStyle(isMatch ? Color.green : Color.orange)
                    .font(.caption)
            }
            .font(.subheadline)
        }
    }

    // MARK: - Row helpers

    private func chargeRow(
        label: String,
        icon: String,
        enabled: Binding<Bool>,
        rateText: Binding<String>
    ) -> some View {
        HStack {
            Label(label, systemImage: icon)
            Spacer()
            if enabled.wrappedValue {
                TextField("0", text: rateText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 50)
                    .foregroundStyle(.indigo)
                Text("%")
                    .foregroundStyle(.secondary)
            }
            Toggle("", isOn: enabled)
                .labelsHidden()
        }
    }

    private func summaryRow(_ label: String, value: Decimal?) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            if let v = value {
                Text(v.formatted()).monospacedDigit()
            }
        }
        .font(.subheadline)
    }

    // MARK: - Warning helpers

    private func warningIcon(_ w: ParseWarning) -> String {
        switch w {
        case .lowOCRConfidence:        return "eye.trianglebadge.exclamationmark"
        case .noItemsDetected:         return "exclamationmark.triangle.fill"
        case .noChargesDetected:       return "percent"
        case .quantityDivisionApplied: return "info.circle"
        case .totalMismatch:           return "exclamationmark.circle.fill"
        }
    }

    private func warningColor(_ w: ParseWarning) -> Color {
        switch w {
        case .lowOCRConfidence, .noItemsDetected, .totalMismatch: return .orange
        case .noChargesDetected:                                   return .secondary
        case .quantityDivisionApplied:                             return .blue
        }
    }

    private func warningMessage(_ w: ParseWarning) -> String {
        switch w {
        case .lowOCRConfidence:
            return "Some text had low confidence. Check items marked with ⚠."
        case .noItemsDetected:
            return "No items were detected. You can add them manually below."
        case .noChargesDetected:
            return "No GST or service charge was found. You can set them manually."
        case .quantityDivisionApplied:
            return "Multi-quantity prices were divided to give per-unit costs (e.g. \u{201C}2 × Beer $12\u{201D} → $6 each). Verify these look correct."
        case .totalMismatch(let computed, let detected):
            return "Items sum (\(computed.formatted())) doesn't match the receipt subtotal (\(detected.formatted())). Some items may be missing or duplicated."
        }
    }

    // MARK: - Import

    private func commitImport() {
        let billItems = validItems.map { item in
            BillItem(
                name:     item.name.trimmingCharacters(in: .whitespaces),
                price:    item.parsedPrice!,
                quantity: item.quantity
            )
        }

        let gstRate = Decimal(string: gstText, locale: Locale(identifier: "en_US_POSIX")) ?? 9
        let scRate  = Decimal(string: scText,  locale: Locale(identifier: "en_US_POSIX")) ?? 10

        let charges = Charges(
            gstPercentage:           gstRate,
            serviceChargePercentage: scRate,
            applyServiceChargeFirst: applyScFirst,
            isGSTEnabled:            gstEnabled,
            isServiceChargeEnabled:  scEnabled
        )

        // Persist user corrections for lines that were edited.
        // Only record for parser-originated lines (rawLine is non-empty).
        for item in validItems where !item.rawLine.isEmpty {
            let trimmedName  = item.name.trimmingCharacters(in: .whitespaces)
            let nameChanged  = trimmedName != item.initialName
            let priceChanged = item.priceText != item.initialPriceText

            if nameChanged || priceChanged {
                correctionStore.record(
                    ParserCorrection(
                        correctedName:  nameChanged  ? trimmedName     : nil,
                        correctedPrice: priceChanged ? item.parsedPrice : nil
                    ),
                    for: item.rawLine
                )
            }
        }

        onImport(billItems, charges, parsedReceipt.detectedCurrencyCode)
    }
}

// MARK: - Editable item row

private struct EditableItemRow: View {
    @Binding var item: EditableItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // ── Name + confidence indicator ──────────────────────────────
            HStack(spacing: 8) {
                if item.isLowConfidence {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                TextField("Item name", text: $item.name)
                    .font(.body.weight(.medium))
                    .autocorrectionDisabled()
            }

            // ── Quantity + price ─────────────────────────────────────────
            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    Button {
                        if item.quantity > 1 { item.quantity -= 1 }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundStyle(item.quantity > 1 ? AnyShapeStyle(.indigo) : AnyShapeStyle(.tertiary))
                    }
                    .buttonStyle(.plain)

                    Text("\(item.quantity)")
                        .monospacedDigit()
                        .frame(minWidth: 16, alignment: .center)
                        .font(.subheadline)

                    Button {
                        item.quantity += 1
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(.indigo)
                    }
                    .buttonStyle(.plain)
                }

                Text("×")
                    .foregroundStyle(.tertiary)
                    .font(.caption)

                HStack(spacing: 2) {
                    TextField("0.00", text: $item.priceText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
                        .frame(maxWidth: 80)
                        .foregroundStyle(item.isValid ? AnyShapeStyle(.primary) : AnyShapeStyle(.red))
                }

                Spacer()

                if item.quantity > 1 {
                    Text("= \(item.lineTotal.formatted())")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .font(.subheadline)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Add manual item sheet

private struct AddManualItemSheet: View {
    let onAdd: (String, Decimal, Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name      = ""
    @State private var priceText = ""
    @State private var quantity  = 1
    @FocusState private var nameFieldFocused: Bool

    private var price: Decimal? {
        Decimal(string: priceText, locale: Locale(identifier: "en_US_POSIX"))
    }
    private var canAdd: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && price != nil && price! > 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Item Details") {
                    TextField("Name", text: $name)
                        .focused($nameFieldFocused)
                        .autocorrectionDisabled()

                    HStack {
                        Text("Price")
                        Spacer()
                        TextField("0.00", text: $priceText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 100)
                    }

                    Stepper {
                        HStack {
                            Text("Quantity")
                            Spacer()
                            Text("\(quantity)").foregroundStyle(.secondary)
                        }
                    } onIncrement: {
                        quantity += 1
                    } onDecrement: {
                        if quantity > 1 { quantity -= 1 }
                    }
                }
            }
            .navigationTitle("Add Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onAdd(name.trimmingCharacters(in: .whitespaces), price!, quantity)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(!canAdd)
                }
            }
            .onAppear { nameFieldFocused = true }
        }
    }
}
