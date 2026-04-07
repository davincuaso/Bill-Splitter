import SwiftUI

/// Sheet for naming the group and managing the people list.
/// People can be added inline, deleted by swiping right-to-left,
/// and renamed by swiping left-to-right or by tapping the row.
struct GroupSetupSheet: View {
    @ObservedObject var viewModel: BillViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var newName = ""
    @State private var personToRename: Person?
    @State private var renameText = ""
    @FocusState private var isAddFieldFocused: Bool

    var body: some View {
        NavigationStack {
            List {
                // MARK: Group name
                Section("Group Name") {
                    TextField("e.g. Dinner at Olivia's", text: $viewModel.groupName)
                        .autocorrectionDisabled()
                }

                // MARK: People
                Section {
                    ForEach(viewModel.people) { person in
                        PersonRow(person: person)
                            // Swipe leading → rename
                            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                Button {
                                    personToRename = person
                                    renameText = person.name
                                } label: {
                                    Label("Rename", systemImage: "pencil")
                                }
                                .tint(.indigo)
                            }
                            // Tap also opens rename
                            .contentShape(Rectangle())
                            .onTapGesture {
                                personToRename = person
                                renameText = person.name
                            }
                    }
                    // Swipe trailing (standard delete)
                    .onDelete { indexSet in
                        indexSet.forEach { viewModel.removePerson(id: viewModel.people[$0].id) }
                    }

                    // Inline add row
                    HStack {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(.indigo)
                        TextField("Add person…", text: $newName)
                            .focused($isAddFieldFocused)
                            .autocorrectionDisabled()
                            .onSubmit { commitAdd() }
                        if !newName.trimmingCharacters(in: .whitespaces).isEmpty {
                            Button("Add", action: commitAdd)
                                .font(.subheadline.bold())
                                .foregroundStyle(.indigo)
                        }
                    }
                } header: {
                    HStack {
                        Text("People")
                        Spacer()
                        if !viewModel.people.isEmpty {
                            Text("\(viewModel.people.count)")
                                .foregroundStyle(.secondary)
                                .textCase(nil)
                        }
                    }
                } footer: {
                    if viewModel.people.isEmpty {
                        Text("Add at least one person to start splitting.")
                    } else {
                        Text("Swipe right on a name to rename · Swipe left to remove")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Group Setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .onAppear { isAddFieldFocused = viewModel.people.isEmpty }
            // MARK: Rename alert
            .alert("Rename Person", isPresented: Binding(
                get: { personToRename != nil },
                set: { if !$0 { personToRename = nil } }
            )) {
                TextField("Name", text: $renameText)
                    .autocorrectionDisabled()
                Button("Save") {
                    let trimmed = renameText.trimmingCharacters(in: .whitespaces)
                    if let person = personToRename, !trimmed.isEmpty {
                        viewModel.updatePerson(id: person.id, name: trimmed)
                    }
                    personToRename = nil
                }
                Button("Cancel", role: .cancel) {
                    personToRename = nil
                }
            } message: {
                if let person = personToRename {
                    Text("Enter a new name for \(person.name).")
                }
            }
        }
    }

    private func commitAdd() {
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        viewModel.addPerson(name: trimmed)
        newName = ""
    }
}

// MARK: - Person row

private struct PersonRow: View {
    let person: Person

    var body: some View {
        HStack(spacing: 12) {
            AvatarChip(person: person, size: .medium)
            VStack(alignment: .leading, spacing: 1) {
                Text(person.name)
                    .font(.body)
            }
            Spacer()
            Image(systemName: "pencil")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    let vm = BillViewModel()
    vm.addPerson(name: "Alice Tan")
    vm.addPerson(name: "Bob Lee")
    vm.addPerson(name: "Carol")
    return GroupSetupSheet(viewModel: vm)
}
