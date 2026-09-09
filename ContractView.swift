import SwiftUI

struct ContractView: View {
    @ObservedObject var store: ContractStore
    @Environment(\.presentationMode) private var presentationMode
    @State private var showingEditor = false
    @State private var editingContract: Contract?

    private var displayedContracts: [Contract] {
        store.contracts.sorted { first, second in
            let firstIsTerminated = first.status == "Résilié"
            let secondIsTerminated = second.status == "Résilié"
            if firstIsTerminated != secondIsTerminated { return !firstIsTerminated }
            return false
        }
    }

    var body: some View {
        List {
            if store.contracts.isEmpty {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 44))
                            .foregroundColor(.green)
                        Text("Aucun contrat")
                            .font(.title2.bold())
                        Text("Ajoutez votre premier contrat pour commencer le suivi.")
                            .multilineTextAlignment(.center)
                            .foregroundColor(.secondary)
                        Button("Ajouter un contrat") { showingEditor = true }
                            .buttonStyle(.borderedProminent)
                            .tint(.green)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                }
            } else {
                ForEach(displayedContracts) { contract in
                    Button { editingContract = contract } label: {
                        ContractRow(contract: contract)
                    }
                    .buttonStyle(.plain)
                }
                .onDelete { store.delete(at: $0, from: displayedContracts) }
            }
        }
        .background(Color.appBackground.ignoresSafeArea())
        .navigationTitle("Mes contrats")
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
                Button { showingEditor = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showingEditor) {
            ContractEditorView(contract: Contract()) { contract in
                let isFirstContract = store.contracts.isEmpty
                store.add(contract)
                showingEditor = false
                if isFirstContract {
                    Task { await NotificationManager.shared.requestAuthorization() }
                }
            }
        }
        .sheet(item: $editingContract) { contract in
            ContractEditorView(contract: contract) { updated in
                store.update(updated)
                editingContract = nil
            }
        }
    }
}

private struct ContractRow: View {
    let contract: Contract

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(contract.name.isEmpty ? "Sans nom" : contract.name)
                    .font(.headline)
                    .foregroundColor(contract.status == "Résilié" ? .red : .green)
                Spacer()
                Text(contract.status)
                    .font(.caption)
                    .foregroundColor(contract.status == "Résilié" ? .red : .green)
            }
            Text(contract.category + (contract.provider.isEmpty ? "" : " • \(contract.provider)"))
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text("Anniversaire : \(contract.anniversaryDate.formatted(date: .abbreviated, time: .omitted)) - Préavis de : \(contract.cancellationNoticeMonths) mois")
                .font(.caption)
            
            if contract.amount > 0 {
                Text(String(format: "%.2f %@", contract.amount, contract.amountType.unit))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct ContractEditorView: View {
    @Environment(\.presentationMode) private var presentationMode
    @State private var contract: Contract
    let onSave: (Contract) -> Void

    init(contract: Contract, onSave: @escaping (Contract) -> Void) {
        _contract = State(initialValue: contract)
        self.onSave = onSave
    }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField("Nom du contrat", text: $contract.name)
                        .font(.body.bold())
                    Picker("Catégorie", selection: $contract.category) {
                        ForEach(Contract.categories, id: \.self) { Text($0) }
                    }
                    TextField("Fournisseur", text: $contract.provider)
                    Picker("Statut", selection: $contract.status) {
                        ForEach(Contract.statuses, id: \.self) { Text($0) }
                    }
                } header: {
                    Text("Informations")
                        .foregroundColor(.purple)
                }
                Section {
                    DatePicker("Date anniversaire", selection: $contract.anniversaryDate, displayedComponents: .date)
                    Picker("Délai de résiliation", selection: $contract.cancellationNoticeMonths) {
                        ForEach(Contract.noticeOptions, id: \.self) { months in
                            Text(months == 0 ? "Aucun délai" : "\(months) mois avant").tag(months)
                        }
                    }
                } header: {
                    Text("Échéance")
                        .foregroundColor(.purple)
                }
                Section {
                    Picker("Type de montant", selection: $contract.amountType) {
                        ForEach(AmountType.allCases, id: \.self) { type in
                            Text(type.label).tag(type)
                        }
                    }
                    HStack {
                        Text(contract.amountType == .annual ? "Montant annuel" : "Montant mensuel")
                        Spacer()
                        TextField("Montant", value: $contract.amount, format: .number.precision(.fractionLength(2)))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                        Text(contract.amountType.unit).foregroundColor(.secondary)
                    }
                } header: {
                    Text("Montant")
                        .foregroundColor(.purple)
                }
                Section {
                    ForEach(contract.annualAmounts.indices, id: \.self) { index in
                        HStack {
                            Text("Année \(index + 1)")
                            Spacer()
                            TextField("Montant", value: $contract.annualAmounts[index], format: .number.precision(.fractionLength(2)))
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                            Text("€")
                        }
                    }
                    .onDelete { contract.annualAmounts.remove(atOffsets: $0) }
                    Button("Ajouter une année") { contract.annualAmounts.append(0) }
                } header: {
                    Text("Historique des montants annuels")
                        .foregroundColor(.purple)
                }
            }
            .background(Color.appBackground.ignoresSafeArea())
            .navigationBarItems(
                leading: Button("Annuler") { presentationMode.wrappedValue.dismiss() },
                trailing: Button("Enregistrer") { onSave(contract) }
                    .disabled(contract.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            )
        }
    }
}

struct ContractView_Previews: PreviewProvider {
    static var previews: some View {
        ContractView(store: PreviewData.contractStore)
            .previewDisplayName("Mes contrats")
    }
}
