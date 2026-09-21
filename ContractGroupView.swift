import SwiftUI

struct ContractGroupView: View {
    @ObservedObject var store: ContractStore
    @Environment(\.presentationMode) private var presentationMode
    @State private var showingEditor = false
    @State private var editingGroup: ContractGroup?

    var body: some View {
        List {
            if store.groups.isEmpty {
                Text("Aucun groupe")
                    .foregroundColor(.secondary)
            } else {
                ForEach(store.groups) { group in
                    Button {
                        editingGroup = group
                    } label: {
                        HStack {
                            Text(group.name)
                                .foregroundColor(.appDarkGreen)
                            Spacer()
                            Text("\(store.contracts.filter { $0.groupID == group.id }.count)")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .onDelete { offsets in
                    offsets.map { store.groups[$0] }.forEach(store.deleteGroup)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.appBackground.ignoresSafeArea())
        .navigationTitle("Gestion des groupes")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    presentationMode.wrappedValue.dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .accessibilityLabel("Retour")
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showingEditor = true } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingEditor) {
            ContractGroupEditorView { name in
                var group = ContractGroup()
                group.name = name
                store.addGroup(group)
                showingEditor = false
            }
        }
        .sheet(item: $editingGroup) { group in
            ContractGroupEditorView(group: group) { name in
                var updatedGroup = group
                updatedGroup.name = name
                store.updateGroup(updatedGroup)
                editingGroup = nil
            }
        }
    }
}

private struct ContractGroupEditorView: View {
    @Environment(\.presentationMode) private var presentationMode
    @State private var name: String
    private let onSave: (String) -> Void

    init(group: ContractGroup? = nil, onSave: @escaping (String) -> Void) {
        _name = State(initialValue: group?.name ?? "")
        self.onSave = onSave
    }

    var body: some View {
        NavigationView {
            Form {
                TextField("Nom", text: $name)
            }
            .navigationTitle("Groupe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Annuler") { presentationMode.wrappedValue.dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Enregistrer") {
                        onSave(name.trimmingCharacters(in: .whitespacesAndNewlines))
                        presentationMode.wrappedValue.dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

struct ContractGroupView_Previews: PreviewProvider {
    static var previews: some View {
        ContractGroupView(store: PreviewData.contractStore)
    }
}
