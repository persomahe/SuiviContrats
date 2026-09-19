import Foundation
import Combine

struct ContractGroup: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String

    init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
    }
}

final class ContractStore: ObservableObject {
    @Published var contracts: [Contract] = [] {
        didSet {
            saveContracts()
        }
    }
    @Published private(set) var groups: [ContractGroup] = [] {
        didSet {
            saveGroups()
        }
    }

    var groupNames: [String] {
        groups.map(\.name).sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }

    private let persistenceKey = "savedContracts"
    private let groupsPersistenceKey = "savedContractGroups"
    private let persistsData: Bool

    init(persisted: Bool = true) {
        persistsData = persisted
        guard persisted else { return }
        if let data = UserDefaults.standard.data(forKey: groupsPersistenceKey),
           let savedGroups = try? JSONDecoder().decode([ContractGroup].self, from: data) {
            groups = savedGroups
        }
        guard let data = UserDefaults.standard.data(forKey: persistenceKey),
              let savedContracts = try? JSONDecoder().decode([Contract].self, from: data) else {
            return
        }

        contracts = savedContracts
        migrateGroupsIfNeeded(from: savedContracts)
        Task { @MainActor in
            savedContracts
                .filter { $0.status != "Résilié" }
                .forEach { NotificationManager.shared.scheduleNotification(for: $0) }
        }
    }

    private func saveContracts() {
        guard persistsData,
              let data = try? JSONEncoder().encode(contracts) else { return }
        UserDefaults.standard.set(data, forKey: persistenceKey)
    }

    private func saveGroups() {
        guard persistsData, let data = try? JSONEncoder().encode(groups) else { return }
        UserDefaults.standard.set(data, forKey: groupsPersistenceKey)
    }

    func add(_ contract: Contract) {
        contracts.append(contract)
        Task { @MainActor in NotificationManager.shared.scheduleNotification(for: contract) }
    }

    func update(_ contract: Contract) {
        guard let index = contracts.firstIndex(where: { $0.id == contract.id }) else { return }
        contracts[index] = contract
        Task { @MainActor in NotificationManager.shared.scheduleNotification(for: contract) }
    }

    func delete(at offsets: IndexSet, from displayedContracts: [Contract]) {
        let contractsToDelete = offsets.compactMap { index in
            displayedContracts.indices.contains(index) ? displayedContracts[index] : nil
        }
        contractsToDelete.forEach { contract in
            Task { @MainActor in NotificationManager.shared.cancelNotification(for: contract) }
        }
        let ids = Set(contractsToDelete.map(\.id))
        contracts.removeAll { ids.contains($0.id) }
    }

    func addGroup(named name: String) {
        let cleanedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedName.isEmpty,
              !groups.contains(where: { $0.name.caseInsensitiveCompare(cleanedName) == .orderedSame }) else { return }
        groups.append(ContractGroup(name: cleanedName))
    }

    func renameGroup(_ group: ContractGroup, to name: String) {
        let cleanedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedName.isEmpty,
              let index = groups.firstIndex(where: { $0.id == group.id }) else { return }
        let oldName = groups[index].name
        groups[index].name = cleanedName
        contracts = contracts.map { contract in
            guard contract.groupName.caseInsensitiveCompare(oldName) == .orderedSame else { return contract }
            var updated = contract
            updated.groupName = cleanedName
            return updated
        }
    }

    func contracts(in group: ContractGroup) -> [Contract] {
        contracts.filter { $0.groupName.caseInsensitiveCompare(group.name) == .orderedSame }
    }

    private func migrateGroupsIfNeeded(from contracts: [Contract]) {
        let existing = Set(groups.map { $0.name.lowercased() })
        let missing = Set(contracts.map { $0.groupName.trimmingCharacters(in: .whitespacesAndNewlines) })
            .filter { !$0.isEmpty && !existing.contains($0.lowercased()) }
        groups.append(contentsOf: missing.sorted().map { ContractGroup(name: $0) })
    }
}
