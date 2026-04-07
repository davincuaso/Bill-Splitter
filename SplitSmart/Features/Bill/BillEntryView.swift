import SwiftUI

/// The main screen. Shows the group overview, receipt items list, and the
/// "Calculate Split" CTA. Sheets/navigation for all editing flows originate here.
struct BillEntryView: View {
    @ObservedObject var viewModel: BillViewModel

    // MARK: - Sheet routing via enum to avoid multiple .sheet modifiers

    private enum ActiveSheet: Identifiable {
        case groupSetup
        case addItem
        case editItem(BillItem)
        case assignItem(BillItem)
        case scanReceipt

        var id: String {
            switch self {
            case .groupSetup:           return "groupSetup"
            case .addItem:              return "addItem"
            case .editItem(let i):      return "edit-\(i.id)"
            case .assignItem(let i):    return "assign-\(i.id)"
            case .scanReceipt:          return "scanReceipt"
            }
        }
    }

    @State private var activeSheet: ActiveSheet?
    @State private var navigateToCharges  = false
    @State private var navigateToSummary  = false

    // MARK: - Body

    var body: some View {
        List {
            peopleStrip
            itemsSection
            addItemRow
        }
        .listStyle(.insetGrouped)
        .navigationTitle(viewModel.groupName)
        .navigationBarTitleDisplayMode(.large)
        .toolbar { toolbarContent }
        .safeAreaInset(edge: .bottom) { calculateButton }
        // Single sheet dispatcher
        .sheet(item: $activeSheet) { sheet in
            sheetContent(for: sheet)
        }
        // Navigation destinations
        .navigationDestination(isPresented: $navigateToCharges) {
            ChargesView(viewModel: viewModel)
        }
        .navigationDestination(isPresented: $navigateToSummary) {
            SummaryView(viewModel: viewModel)
        }
    }

    // MARK: - People strip

    @ViewBuilder
    private var peopleStrip: some View {
        if !viewModel.people.isEmpty {
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(viewModel.people) { person in
                            VStack(spacing: 5) {
                                AvatarChip(person: person, size: .large)
                                Text(person.name)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .frame(maxWidth: 52)
                            }
                        }

                        // Quick-add avatar
                        Button {
                            activeSheet = .groupSetup
                        } label: {
                            VStack(spacing: 5) {
                                Image(systemName: "plus")
                                    .font(.subheadline.bold())
                                    .foregroundStyle(.indigo)
                                    .frame(width: 52, height: 52)
                                    .background(Color.indigo.opacity(0.1))
                                    .clipShape(Circle())
                                Text("Add")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    // MARK: - Items section

    @ViewBuilder
    private var itemsSection: some View {
        Section {
            if viewModel.items.isEmpty {
                emptyItemsPlaceholder
            } else {
                ForEach(viewModel.items) { item in
                    BillItemRow(
                        item: item,
                        currencyCode: viewModel.currencyCode,
                        onAssign:          { activeSheet = .assignItem(item) },
                        onEdit:            { activeSheet = .editItem(item) },
                        onAssignAll:       { viewModel.assignAllPeople(toItemID: item.id) },
                        onClearAssignment: { viewModel.clearAssignees(fromItemID: item.id) }
                    )
                }
                .onDelete { indexSet in
                    indexSet.forEach { viewModel.removeItem(id: viewModel.items[$0].id) }
                }
            }
        } header: {
            HStack(spacing: 6) {
                Text("Items")
                // Unassigned-item badge
                if !viewModel.unassignedItems.isEmpty {
                    let n = viewModel.unassignedItems.count
                    Text("\(n) unassigned")
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange)
                        .clipShape(Capsule())
                        .textCase(nil)
                        .transition(.scale.combined(with: .opacity))
                }
                Spacer()
                if viewModel.subtotal > 0 {
                    Text(viewModel.subtotal.formatted(currencyCode: viewModel.currencyCode))
                        .foregroundStyle(.secondary)
                        .textCase(nil)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: viewModel.unassignedItems.count)
        }
    }

    private var emptyItemsPlaceholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "receipt")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            Text("No items yet")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Tap + Add Item to start entering your receipt")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    // MARK: - Add item row

    private var addItemRow: some View {
        Section {
            Button {
                activeSheet = .addItem
            } label: {
                Label("Add Item", systemImage: "plus.circle.fill")
                    .fontWeight(.medium)
                    .foregroundStyle(.indigo)
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Button {
                activeSheet = .groupSetup
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: viewModel.people.isEmpty ? "person.badge.plus" : "person.2.fill")
                    if !viewModel.people.isEmpty {
                        Text("\(viewModel.people.count)")
                            .font(.subheadline.bold())
                    }
                }
            }
        }

        ToolbarItem(placement: .navigationBarTrailing) {
            HStack(spacing: 16) {
                // Receipt scan button
                Button {
                    activeSheet = .scanReceipt
                } label: {
                    Image(systemName: "doc.text.viewfinder")
                }

                // Charges button
                Button {
                    navigateToCharges = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "percent")
                        chargesIndicator
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var chargesIndicator: some View {
        let activeCount = [
            viewModel.charges.isGSTEnabled,
            viewModel.charges.isServiceChargeEnabled,
        ].filter { $0 }.count

        if activeCount > 0 {
            Text("\(activeCount)")
                .font(.caption2.bold())
                .foregroundStyle(.white)
                .padding(3)
                .background(Color.indigo)
                .clipShape(Circle())
        }
    }

    // MARK: - Calculate button

    private var calculateButton: some View {
        VStack(spacing: 6) {
            // Hint text when action is blocked
            if !viewModel.isReadyToSplit, !viewModel.items.isEmpty {
                Text(blockingHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }

            Button {
                navigateToSummary = true
            } label: {
                HStack {
                    Text("Calculate Split")
                        .fontWeight(.semibold)
                    Spacer()
                    if viewModel.grandTotal > 0 {
                        Text(viewModel.grandTotal.formatted(currencyCode: viewModel.currencyCode))
                            .fontWeight(.semibold)
                            .monospacedDigit()
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(
                    viewModel.isReadyToSplit
                        ? Color.indigo
                        : Color(.tertiarySystemFill)
                )
                .foregroundStyle(
                    viewModel.isReadyToSplit ? .white : Color(.tertiaryLabel)
                )
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .disabled(!viewModel.isReadyToSplit)
            .animation(.easeInOut(duration: 0.2), value: viewModel.isReadyToSplit)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var blockingHint: String {
        if viewModel.people.isEmpty      { return "Add people to the group first" }
        if viewModel.items.isEmpty       { return "Add at least one item" }
        let n = viewModel.unassignedItems.count
        return n == 1 ? "1 item still needs assignment" : "\(n) items still need assignment"
    }

    // MARK: - Sheet content router

    @ViewBuilder
    private func sheetContent(for sheet: ActiveSheet) -> some View {
        switch sheet {
        case .groupSetup:
            GroupSetupSheet(viewModel: viewModel)
        case .addItem:
            AddEditItemSheet(viewModel: viewModel, item: nil)
        case .editItem(let item):
            AddEditItemSheet(viewModel: viewModel, item: item)
        case .assignItem(let item):
            AssignPeopleSheet(assignmentVM: viewModel.makeAssignmentViewModel(for: item))
        case .scanReceipt:
            ReceiptScannerSheet { items, charges, currencyCode in
                viewModel.applyParsedReceipt(items, charges: charges, currencyCode: currencyCode)
            }
        }
    }
}

// MARK: - Preview

#Preview("Empty state") {
    NavigationStack {
        BillEntryView(viewModel: BillViewModel())
    }
}

#Preview("With data") {
    let vm = BillViewModel()
    let alice = vm.addPerson(name: "Alice")
    let bob   = vm.addPerson(name: "Bob")
    let carol = vm.addPerson(name: "Carol Ng")
    let i1 = vm.addItem(name: "Laksa",       price: 8.50)
    let i2 = vm.addItem(name: "Tiger Beer",  price: 12.00, quantity: 3)
    let i3 = vm.addItem(name: "Kaya Toast",  price: 3.50)
    vm.assignPeople([alice],       toItemID: i1.id)
    vm.assignPeople([alice, bob, carol], toItemID: i2.id)
    vm.assignPeople([bob, carol],  toItemID: i3.id)
    return NavigationStack {
        BillEntryView(viewModel: vm)
    }
}
